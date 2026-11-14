import Foundation
import DiskArbitration
import IOKit
import Observation
import CaobaCore

/// Un disco externo físico (tarjeta, lector, disco USB) en el que se puede buscar.
struct ExternalDisk: Identifiable, Equatable, Sendable {
    /// Nombre BSD del disco entero (`disk4`).
    let bsdName: String
    /// Nombre del volumen; `nil` si no tiene (tarjeta formateada en crudo, dañada…).
    let volumeName: String?
    /// Por dónde está conectada: «Lector SD del Mac», el modelo del lector USB…
    let connection: String
    /// Marca de la cámara que la usó, deducida de las carpetas de `DCIM`. Solo si está montada.
    let cameraBrand: String?
    /// Espacio usado y capacidad del volumen, en bytes. Solo si está montada.
    let usedBytes: Int64?
    let volumeCapacity: Int64?
    let size: Int64
    /// `VolumeKind` de DiskArbitration del primer volumen: `msdos`, `exfat`, `ntfs`, `hfs`… `nil` si no se reconoce.
    let volumeKind: String?
    /// Nombre del sistema de archivos para enseñar («exFAT», «FAT»…), sacado de `volumeKind`.
    let volumeType: String?
    /// Dónde están montados sus volúmenes (para no dejar que el destino caiga dentro).
    let mountPoints: [URL]
    let isDiskImage: Bool

    var id: String { bsdName }
    /// Lo que se enseña como título: el nombre del volumen o, si no tiene, un texto genérico.
    var name: String { volumeName ?? L("Sin nombre de volumen") }
    /// Dispositivo en bruto, el que lee PhotoRec: más rápido que `/dev/diskN` (sin caché).
    var rawDevice: String { "/dev/r" + bsdName }
    /// PhotoRec solo sabe distinguir lo libre de lo ocupado en FAT y exFAT.
    var supportsFreeSpace: Bool { volumeKind == "msdos" || volumeKind == "exfat" }
}

/// Lista los discos externos físicos y la mantiene al día cuando se conectan o se quitan,
/// con DiskArbitration. Nunca ofrece el disco interno ni el disco con el que arranca el Mac;
/// el lector SD integrado sí, porque macOS lo marca como interno pero extraíble.
@MainActor
@Observable
final class ExternalDiskMonitor {
    private(set) var disks: [ExternalDisk] = []

    /// Solo para probar: enseña también las imágenes de disco montadas (`hdiutil attach`).
    /// Se activa con `defaults write com.marcosesperon.caoba caoba.dev.recoveryDiskImages -bool YES`.
    static let showDiskImagesKey = "caoba.dev.recoveryDiskImages"

    /// Contenido de un disco APFS «sintetizado» (el contenedor virtual que macOS crea encima del físico).
    nonisolated private static let apfsContainerContent = "EF57347C-0000-11AA-AA11-00306543ECAC"

    /// Claves propias que se añaden a la descripción de DiskArbitration con lo que se saca de IOKit.
    /// Disco físico entero en el que vive un contenedor APFS (`disk6` → `disk5`).
    nonisolated private static let apfsStoreKey = "caoba.apfsStoreWholeDisk"
    /// Nombre del fichero de una imagen de disco («CAOBA-3.17.0.dmg») o «Disco en RAM».
    nonisolated private static let imageNameKey = "caoba.imageName"

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

    /// Olvida lo que sabe y vuelve a preguntar a macOS: al abrir una sesión nueva, DiskArbitration
    /// avisa otra vez de cada disco conectado. No monta ni desmonta nada.
    func reload() {
        stop()
        descriptions = [:]
        disks = []
        start()
    }

    /// Callback de C de DiskArbitration. Llega siempre a la cola principal (la que se le dio
    /// a la sesión), así que se puede entrar en el `MainActor` sin saltos. El contexto y la
    /// descripción no son `Sendable` para Swift, pero no salen de ese hilo.
    nonisolated private static func handle(_ disk: DADisk, removed: Bool, context: UnsafeMutableRawPointer?) {
        guard let context, let bsd = DADiskGetBSDName(disk).map({ String(cString: $0) }) else { return }
        nonisolated(unsafe) let description = removed ? nil : (DADiskCopyDescription(disk) as? [String: Any]).map { withIOKitDetails($0, of: disk) }
        nonisolated(unsafe) let monitorPointer = context
        MainActor.assumeIsolated {
            let monitor = Unmanaged<ExternalDiskMonitor>.fromOpaque(monitorPointer).takeUnretainedValue()
            monitor.descriptions[bsd] = description
            monitor.rebuild()
        }
    }

    /// Completa la descripción con lo que DiskArbitration no da y hay que buscar en IOKit:
    /// de qué disco físico cuelga un contenedor APFS y de qué fichero sale una imagen de disco.
    nonisolated private static func withIOKitDetails(_ description: [String: Any], of disk: DADisk) -> [String: Any] {
        let isContainer = (description["DAMediaContent"] as? String) == apfsContainerContent
        let isImage = (description["DAMediaWhole"] as? Bool) == true && (description["DADeviceModel"] as? String) == "Disk Image"
        guard isContainer || isImage else { return description }
        let media = DADiskCopyIOMedia(disk)
        guard media != 0 else { return description }
        defer { IOObjectRelease(media) }
        var result = description
        if isContainer, let store = parentProperty("BSD Name", of: media) as? String {
            result[apfsStoreKey] = wholeDiskName(of: store) ?? store
        }
        if isImage, let name = imageName(of: media) { result[imageNameKey] = name }
        return result
    }

    /// Busca una propiedad en los padres de un objeto de IOKit (sin mirar el propio objeto).
    nonisolated private static func parentProperty(_ key: String, of entry: io_registry_entry_t) -> Any? {
        var parent: io_registry_entry_t = 0
        guard IORegistryEntryGetParentEntry(entry, kIOServicePlane, &parent) == KERN_SUCCESS else { return nil }
        defer { IOObjectRelease(parent) }
        return IORegistryEntrySearchCFProperty(parent, kIOServicePlane, key as CFString, kCFAllocatorDefault,
                                               IOOptionBits(kIORegistryIterateRecursively | kIORegistryIterateParents))
    }

    /// Nombre del fichero de una imagen de disco. Las de ahora guardan `DiskImageURL` y las
    /// antiguas (y los discos en RAM) `image-path`, como datos.
    nonisolated private static func imageName(of media: io_registry_entry_t) -> String? {
        var path: String?
        if let url = parentProperty("DiskImageURL", of: media) {
            path = (url as? URL)?.path ?? (url as? String).flatMap { URL(string: $0)?.path ?? $0 }
        } else if let data = parentProperty("image-path", of: media) as? Data {
            path = String(decoding: data.prefix { $0 != 0 }, as: UTF8.self)
        }
        guard let path, !path.isEmpty else { return nil }
        if path.hasPrefix("ram://") { return L("Disco en RAM") }
        return (path as NSString).lastPathComponent
    }

    /// Vuelve a montar la lista a partir de las descripciones conocidas.
    private func rebuild() {
        let showImages = UserDefaults.standard.bool(forKey: Self.showDiskImagesKey)
        let wholes = descriptions.filter { isOffered($0.value, showImages: showImages) && !bootWholeDisks.contains($0.key) }
        let list = wholes.map { bsd, whole -> ExternalDisk in
            // Volúmenes del disco: él mismo (tarjeta sin particiones), sus particiones (`disk4s1`…)
            // y, si está en APFS, los volúmenes de sus contenedores, que macOS pone en otro disco virtual.
            let containers = Set(descriptions.filter { ($0.value[Self.apfsStoreKey] as? String) == bsd }.keys)
            let owners = containers.union([bsd])
            let volumes = descriptions.filter { owners.contains($0.key) || Self.wholeDiskName(of: $0.key).map(owners.contains) == true }
                .sorted { $0.key < $1.key }.map(\.value)
            let main = volumes.first { $0["DAVolumeKind"] != nil }
            let volumeName = (main?["DAVolumeName"] as? String)?.trimmingCharacters(in: .whitespaces)
            let mountPoints = volumes.compactMap { $0["DAVolumePath"] as? URL }
            let space = mountPoints.first.flatMap(Self.space(of:))
            return ExternalDisk(bsdName: bsd, volumeName: volumeName?.isEmpty == false ? volumeName : nil,
                                connection: Self.connection(of: whole),
                                cameraBrand: Self.cameraBrand(in: mountPoints),
                                usedBytes: space?.used, volumeCapacity: space?.capacity,
                                size: (whole["DAMediaSize"] as? NSNumber)?.int64Value ?? 0,
                                volumeKind: main?["DAVolumeKind"] as? String,
                                volumeType: (main?["DAVolumeKind"] as? String).map(Self.fileSystemName(of:)),
                                mountPoints: mountPoints,
                                isDiskImage: (whole["DADeviceModel"] as? String) == "Disk Image")
        }
        let sorted = list.sorted { $0.bsdName.localizedStandardCompare($1.bsdName) == .orderedAscending }
        if sorted != disks { disks = sorted }
    }

    /// Un disco entero externo y físico. Los internos solo si son extraíbles: es el lector SD
    /// integrado, que macOS da por interno (el SSD del Mac no es extraíble y se queda fuera).
    /// Las imágenes de disco solo con el ajuste de desarrollo.
    private func isOffered(_ d: [String: Any], showImages: Bool) -> Bool {
        guard (d["DAMediaWhole"] as? Bool) == true else { return false }
        if (d["DADeviceInternal"] as? Bool) == true, (d["DAMediaRemovable"] as? Bool) != true { return false }
        // Los contenedores APFS sintetizados son virtuales: el físico ya sale aparte.
        if (d["DAMediaContent"] as? String) == Self.apfsContainerContent { return false }
        let isImage = (d["DADeviceModel"] as? String) == "Disk Image"
        if isImage { return showImages }
        return (d["DADeviceProtocol"] as? String) != "Virtual Interface"
    }

    /// Por dónde está conectado, a partir de la descripción del disco entero.
    private static func connection(of whole: [String: Any]) -> String {
        let model = (whole["DADeviceModel"] as? String)?.trimmingCharacters(in: .whitespaces)
        if model == "Disk Image" { return (whole[imageNameKey] as? String) ?? L("Imagen de disco") }
        if (whole["DADeviceInternal"] as? Bool) == true {
            return (whole["DADeviceProtocol"] as? String) == "Secure Digital" ? L("Lector SD del Mac") : L("Lector interno del Mac")
        }
        // Lector o disco USB: su modelo («STORAGE DEVICE», «SD Card Reader»…) o, si no lo dice, el tipo de conexión.
        if let model, !model.isEmpty { return model }
        return (whole["DADeviceProtocol"] as? String) ?? L("Disco externo")
    }

    /// Nombre legible de un `DAVolumeKind`. DiskArbitration no da otro texto (no existe
    /// `DAVolumeType`), así que se traducen los habituales y el resto sale tal cual.
    private static func fileSystemName(of kind: String) -> String {
        switch kind {
        case "msdos": return "FAT"
        case "exfat": return "exFAT"
        case "ntfs": return "NTFS"
        case "hfs": return "HFS+"
        case "apfs": return "APFS"
        default: return kind
        }
    }

    /// Marca de la cámara según las carpetas de `DCIM` del primer volumen montado que la tenga.
    /// Solo lista la carpeta: no abre ni escribe nada en la tarjeta.
    private static func cameraBrand(in mountPoints: [URL]) -> String? {
        for mount in mountPoints {
            let dcim = mount.appendingPathComponent("DCIM", isDirectory: true)
            guard let folders = try? FileManager.default.contentsOfDirectory(atPath: dcim.path) else { continue }
            if let brand = CameraBrand.detect(dcimFolders: folders) { return brand }
        }
        return nil
    }

    /// Espacio usado y capacidad del volumen montado, según el sistema de archivos.
    private static func space(of mount: URL) -> (used: Int64, capacity: Int64)? {
        guard let values = try? mount.resourceValues(forKeys: [.volumeTotalCapacityKey, .volumeAvailableCapacityKey]),
              let total = values.volumeTotalCapacity, let available = values.volumeAvailableCapacity else { return nil }
        return (Int64(total - available), Int64(total))
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
