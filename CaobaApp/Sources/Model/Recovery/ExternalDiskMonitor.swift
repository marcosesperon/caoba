import Foundation
import DiskArbitration
import Observation

/// Un disco externo físico (tarjeta, lector, disco USB) en el que se puede buscar.
struct ExternalDisk: Identifiable, Equatable, Sendable {
    /// Nombre BSD del disco entero (`disk4`).
    let bsdName: String
    /// Lo que se enseña: el nombre del volumen o, si no tiene, el del dispositivo.
    let name: String
    let size: Int64
    /// `VolumeKind` de DiskArbitration del primer volumen: `msdos`, `exfat`, `ntfs`, `hfs`… `nil` si no se reconoce.
    let volumeKind: String?
    /// Texto del sistema de archivos tal como lo da macOS («MS-DOS (FAT32)», «ExFAT»…).
    let volumeType: String?
    /// Dónde están montados sus volúmenes (para no dejar que el destino caiga dentro).
    let mountPoints: [URL]
    let isDiskImage: Bool

    var id: String { bsdName }
    /// Dispositivo en bruto, el que lee PhotoRec: más rápido que `/dev/diskN` (sin caché).
    var rawDevice: String { "/dev/r" + bsdName }
    /// PhotoRec solo sabe distinguir lo libre de lo ocupado en FAT y exFAT.
    var supportsFreeSpace: Bool { volumeKind == "msdos" || volumeKind == "exfat" }
}

/// Lista los discos externos físicos y la mantiene al día cuando se conectan o se quitan,
/// con DiskArbitration. Nunca ofrece el disco interno ni el disco con el que arranca el Mac.
@MainActor
@Observable
final class ExternalDiskMonitor {
    private(set) var disks: [ExternalDisk] = []

    /// Solo para probar: enseña también las imágenes de disco montadas (`hdiutil attach`).
    /// Se activa con `defaults write com.marcosesperon.caoba caoba.dev.recoveryDiskImages -bool YES`.
    static let showDiskImagesKey = "caoba.dev.recoveryDiskImages"

    /// Contenido de un disco APFS «sintetizado» (el contenedor virtual que macOS crea encima del físico).
    private static let apfsContainerContent = "EF57347C-0000-11AA-AA11-00306543ECAC"

    @ObservationIgnored private var session: DASession?
    /// Descripción de cada disco o partición conocida, por nombre BSD.
    @ObservationIgnored private var descriptions: [String: [String: Any]] = [:]
    /// Discos enteros que no se ofrecen nunca: el que lleva el sistema arrancado.
    @ObservationIgnored private var bootWholeDisks: Set<String> = []

    func start() {
        guard session == nil, let session = DASessionCreate(kCFAllocatorDefault) else { return }
        self.session = session
        bootWholeDisks = Self.bootWholeDisks()
        let context = Unmanaged.passUnretained(self).toOpaque()
        // Las tres notificaciones llegan a la cola principal: aparece, desaparece o cambia (se monta, se renombra…).
        DARegisterDiskAppearedCallback(session, nil, { disk, context in
            ExternalDiskMonitor.handle(disk, removed: false, context: context)
        }, context)
        DARegisterDiskDisappearedCallback(session, nil, { disk, context in
            ExternalDiskMonitor.handle(disk, removed: true, context: context)
        }, context)
        DARegisterDiskDescriptionChangedCallback(session, nil, nil, { disk, _, context in
            ExternalDiskMonitor.handle(disk, removed: false, context: context)
        }, context)
        DASessionSetDispatchQueue(session, .main)
    }

    func stop() {
        guard let session else { return }
        DASessionSetDispatchQueue(session, nil)
        self.session = nil
    }

    /// Callback de C de DiskArbitration. Llega siempre a la cola principal (la que se le dio
    /// a la sesión), así que se puede entrar en el `MainActor` sin saltos. El contexto y la
    /// descripción no son `Sendable` para Swift, pero no salen de ese hilo.
    nonisolated private static func handle(_ disk: DADisk, removed: Bool, context: UnsafeMutableRawPointer?) {
        guard let context, let bsd = DADiskGetBSDName(disk).map({ String(cString: $0) }) else { return }
        nonisolated(unsafe) let description = removed ? nil : DADiskCopyDescription(disk) as? [String: Any]
        nonisolated(unsafe) let monitorPointer = context
        MainActor.assumeIsolated {
            let monitor = Unmanaged<ExternalDiskMonitor>.fromOpaque(monitorPointer).takeUnretainedValue()
            monitor.descriptions[bsd] = description
            monitor.rebuild()
        }
    }

    /// Vuelve a montar la lista a partir de las descripciones conocidas.
    private func rebuild() {
        let showImages = UserDefaults.standard.bool(forKey: Self.showDiskImagesKey)
        let wholes = descriptions.filter { isOffered($0.value, showImages: showImages) && !bootWholeDisks.contains($0.key) }
        let list = wholes.map { bsd, whole -> ExternalDisk in
            // Volúmenes del disco: él mismo (tarjeta sin particiones) y sus particiones (`disk4s1`…).
            let volumes = descriptions.filter { $0.key == bsd || Self.wholeDiskName(of: $0.key) == bsd }
                .sorted { $0.key < $1.key }.map(\.value)
            let main = volumes.first { $0["DAVolumeKind"] != nil }
            let name = (main?["DAVolumeName"] as? String) ?? (whole["DADeviceModel"] as? String)
                ?? (whole["DAMediaName"] as? String) ?? bsd
            return ExternalDisk(bsdName: bsd, name: name.trimmingCharacters(in: .whitespaces),
                                size: (whole["DAMediaSize"] as? NSNumber)?.int64Value ?? 0,
                                volumeKind: main?["DAVolumeKind"] as? String, volumeType: main?["DAVolumeType"] as? String,
                                mountPoints: volumes.compactMap { $0["DAVolumePath"] as? URL },
                                isDiskImage: (whole["DADeviceModel"] as? String) == "Disk Image")
        }
        let sorted = list.sorted { $0.bsdName.localizedStandardCompare($1.bsdName) == .orderedAscending }
        if sorted != disks { disks = sorted }
    }

    /// Un disco entero externo y físico. Las imágenes de disco solo con el ajuste de desarrollo.
    private func isOffered(_ d: [String: Any], showImages: Bool) -> Bool {
        guard (d["DAMediaWhole"] as? Bool) == true, (d["DADeviceInternal"] as? Bool) != true else { return false }
        // Los contenedores APFS sintetizados son virtuales: el físico ya sale aparte.
        if (d["DAMediaContent"] as? String) == Self.apfsContainerContent { return false }
        let isImage = (d["DADeviceModel"] as? String) == "Disk Image"
        if isImage { return showImages }
        return (d["DADeviceProtocol"] as? String) != "Virtual Interface"
    }

    /// `disk4s1` → `disk4`; `nil` si ya es un disco entero.
    nonisolated static func wholeDiskName(of bsd: String) -> String? {
        guard let range = bsd.range(of: #"^disk\d+"#, options: .regularExpression), range.upperBound < bsd.endIndex else { return nil }
        return String(bsd[range])
    }

    /// Discos físicos del volumen de arranque (`diskutil info -plist /`). Con un Mac que arranca
    /// desde un disco externo, ese disco no debe aparecer nunca.
    nonisolated private static func bootWholeDisks() -> Set<String> {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/sbin/diskutil")
        process.arguments = ["info", "-plist", "/"]
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice
        guard (try? process.run()) != nil else { return [] }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        guard let info = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any] else { return [] }
        var names: Set<String> = []
        if let parent = info["ParentWholeDisk"] as? String { names.insert(parent) }
        for store in (info["APFSPhysicalStores"] as? [[String: Any]]) ?? [] {
            if let bsd = store["APFSPhysicalStore"] as? String { names.insert(wholeDiskName(of: bsd) ?? bsd) }
        }
        return names
    }
}
