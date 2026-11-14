import Foundation
import AppKit
import Observation
import CaobaCore

/// Estado del módulo «Recuperar fotos»: opciones, búsqueda en marcha y resultado.
/// Vive en `AppState` y no en la vista, para que una recuperación de una hora siga
/// su curso aunque el usuario se vaya a otro módulo.
@MainActor
@Observable
final class RecoverySession {
    enum Phase: Equatable {
        /// Eligiendo tarjeta y opciones.
        case setup
        /// Desmontando la tarjeta y esperando la contraseña (hasta que PhotoRec arranca).
        case starting
        /// PhotoRec trabajando.
        case running
        /// PhotoRec detenido donde estaba. `automatic`: lo paró CAOBA porque el destino se llenaba.
        case paused(automatic: Bool)
        /// Pulsado «Cancelar»: esperando a que PhotoRec pare.
        case cancelling
        /// Terminado (bien, con problemas o cancelado).
        case finished(RecoveryResult)
    }

    // MARK: Opciones
    let diskMonitor = ExternalDiskMonitor()
    var selectedDiskID: String?
    var fileSystem: RecoveryFileSystem = .other
    var scope: RecoveryScope = .freeSpace
    var groups: Set<RecoveryFileGroup> = RecoveryFileGroup.photographerDefault
    var includeOtherFiles = false
    /// Carpeta elegida por el usuario. Cada recuperación crea dentro su propia subcarpeta.
    var destinationFolder: URL? = UserDefaults.standard.url(forKey: RecoverySession.destinationKey) {
        didSet { UserDefaults.standard.set(destinationFolder, forKey: Self.destinationKey) }
    }

    // MARK: En marcha
    private(set) var phase: Phase = .setup
    private(set) var startDate: Date?
    private(set) var counts = RecoveredFiles.Counts()
    /// Subcarpeta de esta recuperación (`Recuperado <tarjeta> <fecha>`).
    private(set) var outputFolder: URL?
    /// Lo recuperado, para la cuadrícula: en directo mientras busca y al terminar.
    private(set) var results: RecoveryResults?
    /// Lo que ocupa la carpeta de esta recuperación y lo que queda libre en su disco.
    private(set) var usedSpace: Int64 = 0
    private(set) var freeSpace: Int64?

    /// Con menos de esto libre en el destino, CAOBA pausa PhotoRec antes de que el disco se
    /// llene (lleno, PhotoRec se para y la búsqueda no se puede retomar).
    static let minimumFreeSpace: Int64 = 2_000_000_000

    private static let destinationKey = "caoba.recovery.destination"
    @ObservationIgnored private var runner: PhotoRecRunning = AuthOpenPhotoRecRunner()
    @ObservationIgnored private var pollTask: Task<Void, Never>?

    init() {
        // Al cerrar la app (⌘Q) se para PhotoRec: si no, seguiría como proceso suelto hasta acabar.
        NotificationCenter.default.addObserver(forName: NSApplication.willTerminateNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.runner.cancel() }
        }
    }

    var selectedDisk: ExternalDisk? { diskMonitor.disks.first { $0.id == selectedDiskID } }
    var isBusy: Bool {
        switch phase {
        case .starting, .running, .paused, .cancelling: return true
        case .setup, .finished: return false
        }
    }

    var isPaused: Bool {
        if case .paused = phase { return true }
        return false
    }

    /// Si hay sitio para seguir (para «Continuar» tras una pausa por espacio).
    var hasEnoughFreeSpace: Bool { (freeSpace ?? .max) >= Self.minimumFreeSpace }
    var isPhotoRecAvailable: Bool { AuthOpenPhotoRecRunner.bundledPhotoRec != nil }

    /// «Solo espacio libre» solo si la tarjeta es FAT o exFAT; si no, se busca en toda.
    var effectiveScope: RecoveryScope {
        selectedDisk?.supportsFreeSpace == true ? scope : .wholeDisk
    }

    // MARK: Comprobaciones

    /// Lo que impide empezar, ya explicado. `nil` si se puede.
    var blockingProblem: String? {
        guard isPhotoRecAvailable else { return L("Esta copia de CAOBA no lleva PhotoRec: no se puede recuperar.") }
        guard let disk = selectedDisk else { return L("Elige la tarjeta.") }
        guard !groups.isEmpty || includeOtherFiles else { return L("Elige qué tipo de ficheros buscar.") }
        guard let destination = destinationFolder else { return L("Elige dónde guardar lo recuperado.") }
        if Self.isOnDisk(destination, disk) {
            return L("La carpeta de destino está en la propia tarjeta. Elige una en otro disco: escribir en la tarjeta pisaría lo que se quiere recuperar.")
        }
        return nil
    }

    /// Aviso (no impide empezar) si en el destino podría no caber todo.
    var spaceWarning: String? {
        guard let disk = selectedDisk, let destination = destinationFolder,
              let free = try? destination.resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey])
                .volumeAvailableCapacityForImportantUsage else { return nil }
        let needed = neededSpace(for: disk)
        guard free < needed else { return nil }
        let format = ByteCountFormatter()
        return L("En el destino quedan \(format.string(fromByteCount: free)) libres y lo recuperado puede ocupar hasta \(format.string(fromByteCount: needed)). Si se va llenando, CAOBA pausará la búsqueda para que elimines lo que no quieras y sigas.")
    }

    /// Lo máximo que puede salir: lo libre de la tarjeta (si se sabe) o la tarjeta entera.
    private func neededSpace(for disk: ExternalDisk) -> Int64 {
        guard effectiveScope == .freeSpace, let mount = disk.mountPoints.first,
              let free = try? mount.resourceValues(forKeys: [.volumeAvailableCapacityKey]).volumeAvailableCapacity else {
            return disk.size
        }
        return Int64(free)
    }

    /// Si `url` está en un volumen de ese disco. Se mira el dispositivo del volumen
    /// (`statfs`), no la ruta, para que no lo engañen enlaces ni nombres parecidos.
    static func isOnDisk(_ url: URL, _ disk: ExternalDisk) -> Bool {
        var info = statfs()
        guard statfs(url.path, &info) == 0 else { return false }
        let device = withUnsafeBytes(of: info.f_mntfromname) { String(decoding: $0.prefix { $0 != 0 }, as: UTF8.self) }
        let bsd = device.replacingOccurrences(of: "/dev/", with: "")
        return (ExternalDiskMonitor.wholeDiskName(of: bsd) ?? bsd) == disk.bsdName
    }

    // MARK: Acciones

    func start() {
        guard blockingProblem == nil, let disk = selectedDisk, let destination = destinationFolder else { return }
        let options = PhotoRecOptions(device: disk.rawDevice, fileSystem: fileSystem, scope: effectiveScope,
                                      groups: groups, includeOtherFiles: includeOtherFiles)
        phase = .starting
        counts = RecoveredFiles.Counts()
        startDate = nil
        Task { await run(disk: disk, options: options, destination: destination) }
    }

    func cancel() {
        switch phase {
        case .running, .paused:
            phase = .cancelling
            runner.cancel()
        default:
            break
        }
    }

    /// Detiene PhotoRec donde está (a mano o porque el destino se llena).
    func pause(automatic: Bool = false) {
        guard phase == .running, runner.pause() else { return }
        phase = .paused(automatic: automatic)
    }

    /// Reanuda PhotoRec. Si el destino sigue casi lleno, no: se volvería a parar enseguida.
    func resume() {
        guard isPaused, hasEnoughFreeSpace, runner.resume() else { return }
        phase = .running
    }

    /// Enseña los resultados de una carpeta ya recuperada, sin buscar. Para capturas y
    /// pruebas: `--state recovery.results=<carpeta>`.
    func showResults(of folder: URL) {
        guard !isBusy else { return }
        outputFolder = folder
        results = RecoveryResults(folder: folder)
        phase = .finished(.completed(counts: RecoveredFiles.count(in: folder)))
    }

    #if DEBUG
    /// Búsqueda de mentira con `DemoPhotoRecRunner`, sin tarjeta ni contraseña, para probar y
    /// capturar: `--state recovery.demo=<carpeta con fotos>` y `recovery.demoOut=<destino>`.
    func startDemo(source: URL, destination: URL) {
        guard !isBusy else { return }
        runner = DemoPhotoRecRunner(source: source)
        phase = .starting
        counts = RecoveredFiles.Counts()
        Task {
            guard let output = try? Self.makeOutputFolder(in: destination, diskName: "DEMO") else { phase = .setup; return }
            outputFolder = output
            startPolling(output)
            let outcome = (try? await runner.run(arguments: [], device: "demo", outputFolder: output)) ?? .cancelled
            stopPolling(output)
            if case .finished(let report, let exitCode) = outcome {
                finish(Self.result(of: report, exitCode: exitCode, counts: counts), disk: nil)
            } else {
                finish(.cancelled(counts: counts), disk: nil)
            }
            runner = AuthOpenPhotoRecRunner()
        }
    }
    #endif

    /// Vuelve a las opciones para otra recuperación (lo recuperado se queda en su carpeta).
    func reset() {
        guard !isBusy else { return }
        phase = .setup
        counts = RecoveredFiles.Counts()
        startDate = nil
        results = nil
        usedSpace = 0
        freeSpace = nil
    }

    private func run(disk: ExternalDisk, options: PhotoRecOptions, destination: URL) async {
        let output: URL
        do {
            output = try Self.makeOutputFolder(in: destination, diskName: disk.name)
            outputFolder = output
            try await DiskMounter.unmount(disk)
        } catch DiskMounter.Failure.busy {
            finish(.failed(L("No se puede desmontar la tarjeta porque alguna app la está usando. Cierra las ventanas del Finder o las apps que tengan algo abierto en ella y vuelve a probar.")), disk: nil)
            return
        } catch {
            finish(.failed(L("No se ha podido crear la carpeta de destino: \(error.localizedDescription)")), disk: nil)
            return
        }

        do {
            let arguments = try PhotoRecCommand.arguments(for: options, outputFolder: output)
            startPolling(output)
            let outcome = try await runner.run(arguments: arguments, device: options.device, outputFolder: output)
            stopPolling(output)
            switch outcome {
            case .notAuthorized:
                // Se cerró el diálogo de la contraseña: no ha llegado a empezar, se deja todo como estaba.
                try? FileManager.default.removeItem(at: output)
                outputFolder = nil
                await DiskMounter.mount(disk)
                phase = .setup
            case .cancelled:
                finish(.cancelled(counts: counts), disk: disk)
            case .finished(let report, let exitCode):
                finish(Self.result(of: report, exitCode: exitCode, counts: counts), disk: disk)
            }
        } catch {
            stopPolling(output)
            finish(.failed(Self.describe(error)), disk: disk)
        }
    }

    private func finish(_ result: RecoveryResult, disk: ExternalDisk?) {
        if let results {
            // La misma cuadrícula de la búsqueda, ya sin bloque en curso: se relee completa.
            results.isLive = false
            Task { await results.refresh() }
        } else if let folder = outputFolder, (result.counts?.total ?? 0) > 0 {
            results = RecoveryResults(folder: folder)
        }
        phase = .finished(result)
        if let disk { Task { await DiskMounter.mount(disk) } }
    }

    /// Cada medio segundo: si PhotoRec ya ha arrancado (crea su log nada más empezar, o sea,
    /// tras la contraseña) pasa a «buscando» y prepara la cuadrícula; cuenta lo recuperado, mira
    /// el espacio (y pausa si el destino se llena) y, cada dos segundos, refresca la cuadrícula.
    private func startPolling(_ folder: URL) {
        pollTask?.cancel()
        let started = folder.appendingPathComponent(PhotoRecCommand.logFileName)
        pollTask = Task { [weak self] in
            var tick = 0
            while !Task.isCancelled {
                let (counts, used, free) = await Task.detached {
                    (RecoveredFiles.count(in: folder), RecoveredFiles.diskUsage(of: folder), Self.freeSpace(at: folder))
                }.value
                guard let self else { return }
                if self.phase == .starting, FileManager.default.fileExists(atPath: started.path) {
                    self.phase = .running
                    self.startDate = Date()
                    self.results = RecoveryResults(folder: folder, isLive: true)
                }
                self.counts = counts
                self.usedSpace = used
                self.freeSpace = free
                if self.phase == .running, !self.hasEnoughFreeSpace { self.pause(automatic: true) }
                if tick % 4 == 0, let results = self.results { await results.refresh() }
                tick += 1
                try? await Task.sleep(for: .milliseconds(500))
            }
        }
    }

    /// Espacio libre de verdad en el disco de `url` (no el «disponible para lo importante»,
    /// que cuenta lo que macOS podría purgar: PhotoRec se encuentra el disco lleno antes).
    nonisolated private static func freeSpace(at url: URL) -> Int64? {
        (try? url.resourceValues(forKeys: [.volumeAvailableCapacityKey]).volumeAvailableCapacity).map(Int64.init)
    }

    private func stopPolling(_ folder: URL) {
        pollTask?.cancel()
        pollTask = nil
        counts = RecoveredFiles.count(in: folder)
        usedSpace = RecoveredFiles.diskUsage(of: folder)
        freeSpace = Self.freeSpace(at: folder)
    }

    // MARK: Ayudas

    /// `Recuperado EOS_DIGITAL 2026-11-08 13.45` dentro del destino (con `_2`… si ya existe).
    private static func makeOutputFolder(in destination: URL, diskName: String) throws -> URL {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyy-MM-dd HH.mm"
        let safeName = diskName.replacingOccurrences(of: "/", with: "-").replacingOccurrences(of: ":", with: "-")
        let base = L("Recuperado") + " \(safeName) \(f.string(from: Date()))"
        var folder = destination.appendingPathComponent(base, isDirectory: true)
        var n = 2
        while FileManager.default.fileExists(atPath: folder.path) {
            folder = destination.appendingPathComponent("\(base) \(n)", isDirectory: true)
            n += 1
        }
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        return folder
    }

    private static func result(of report: PhotoRecReport, exitCode: Int?, counts: RecoveredFiles.Counts) -> RecoveryResult {
        if report.succeeded { return .completed(counts: counts) }
        guard let problem = report.problems.first else {
            // Ni log ni mensaje: PhotoRec no llegó a arrancar o se cortó sin decir nada.
            let code = exitCode.map(String.init) ?? "?"
            return .completedWithProblem(counts: counts, message: L("PhotoRec no ha llegado a terminar y no ha dejado ningún mensaje (código \(code)). Vuelve a probar; si se repite, saca la tarjeta y vuelve a meterla."))
        }
        return .completedWithProblem(counts: counts, message: message(for: problem))
    }

    /// Los problemas de PhotoRec, explicados para quien no es técnico.
    static func message(for problem: PhotoRecProblem) -> String {
        switch problem {
        case .cannotOpenDevice:
            return L("No se ha podido leer la tarjeta. Comprueba que sigue conectada y vuelve a probar.")
        case .destinationMissing:
            return L("La carpeta de destino ha desaparecido mientras se recuperaba. Comprueba que el disco de destino sigue conectado.")
        case .destinationNotWritable:
            return L("No hay permiso para guardar en la carpeta de destino. Elige otra.")
        case .destinationFull:
            return L("El disco de destino se ha llenado. Lo recuperado hasta ese momento se conserva; libera espacio o elige otro disco para buscar el resto.")
        case .notExtFileSystem:
            return L("La tarjeta no es ext2/3/4. Vuelve a probar con «FAT, exFAT, NTFS, HFS+».")
        case .stopped:
            return L("La búsqueda se ha parado antes de terminar.")
        case .other(let line):
            return L("PhotoRec ha dado un error: \(line)")
        }
    }

    private static func describe(_ error: Error) -> String {
        switch error {
        case PhotoRecRunnerError.photoRecMissing:
            return L("Esta copia de CAOBA no lleva PhotoRec: no se puede recuperar.")
        case PhotoRecRunnerError.couldNotLaunch(let message):
            return L("macOS no ha dejado lanzar la recuperación: \(message)")
        default:
            return JobRunner.describe(error)
        }
    }
}

/// Cómo terminó una recuperación.
enum RecoveryResult: Equatable {
    /// PhotoRec llegó al final sin problemas.
    case completed(counts: RecoveredFiles.Counts)
    /// Terminó, pero con un problema (destino lleno…); lo recuperado se conserva.
    case completedWithProblem(counts: RecoveredFiles.Counts, message: String)
    /// El usuario la paró; lo recuperado hasta entonces se conserva.
    case cancelled(counts: RecoveredFiles.Counts)
    /// No llegó a buscar (no se pudo desmontar, crear la carpeta…).
    case failed(String)

    var counts: RecoveredFiles.Counts? {
        switch self {
        case .completed(let c), .completedWithProblem(let c, _), .cancelled(let c): return c
        case .failed: return nil
        }
    }
}
