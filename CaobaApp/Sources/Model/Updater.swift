import SwiftUI
import CaobaCore

/// Descarga el DMG de una release, lo verifica, sustituye la app instalada y
/// la relanza. Si no puede instalar (carpeta no escribible, app ejecutándose
/// desde el DMG o desde la carpeta de compilación), abre el DMG descargado
/// para que el usuario arrastre la app a Aplicaciones.
@Observable
@MainActor
final class Updater {
    static let shared = Updater()

    enum Phase: Equatable {
        case idle
        case downloading(Double)
        case verifying
        case installing
        case relaunching
        case manual(String)
        case failed(String)
    }

    private(set) var phase: Phase = .idle
    private var task: Task<Void, Never>?
    /// Solo para pruebas: app a sustituir en lugar de la que se ejecuta (y sin relanzar).
    var testTarget: URL?

    var isBusy: Bool {
        switch phase {
        case .downloading, .verifying, .installing, .relaunching: return true
        default: return false
        }
    }

    func cancel() {
        task?.cancel()
        task = nil
        phase = .idle
    }

    func update(to release: VersionCheck.Release) {
        guard !isBusy else { return }
        task = Task { await run(release) }
    }

    private func run(_ release: VersionCheck.Release) async {
        guard let dmgURL = release.dmg else {
            phase = .failed(L("La release no tiene un DMG adjunto."))
            return
        }
        do {
            phase = .downloading(0)
            let dmg = try await download(dmgURL)
            try Task.checkCancellation()
            phase = .verifying
            let mount = try await Self.mount(dmg)
            defer { Task.detached { try? await Self.run("/usr/bin/hdiutil", ["detach", mount.path, "-quiet", "-force"]) } }
            let newApp = mount.appendingPathComponent("CAOBA.app")
            try Self.verify(newApp, expectedVersion: release.version)
            try Task.checkCancellation()

            let target = testTarget ?? Bundle.main.bundleURL
            guard Self.canReplace(target) else {
                phase = .manual(L("No se puede sustituir la app desde aquí. Se ha abierto el DMG: arrastra CAOBA a Aplicaciones."))
                NSWorkspace.shared.open(dmg)
                return
            }
            phase = .installing
            try Self.replace(target, with: newApp)
            if testTarget != nil {
                phase = .idle
                return
            }
            phase = .relaunching
            Self.relaunch(target)
        } catch is CancellationError {
            phase = .idle
        } catch {
            phase = .failed(JobRunner.describe(error))
        }
    }

    // MARK: Pasos

    /// Descarga a un fichero temporal, informando del progreso, y le quita la cuarentena.
    private func download(_ url: URL) async throws -> URL {
        let destination = try TempFiles.makeFileURL(extension: "dmg")
        let downloader = Downloader()
        try await downloader.download(url, to: destination) { [weak self] fraction in
            Task { @MainActor in self?.phase = .downloading(fraction) }
        }
        Self.removeQuarantine(destination)
        return destination
    }

    private static func mount(_ dmg: URL) async throws -> URL {
        let point = FileManager.default.temporaryDirectory.appendingPathComponent("caoba-update-\(UUID().uuidString)")
        try await run("/usr/bin/hdiutil", ["attach", dmg.path, "-mountpoint", point.path, "-nobrowse", "-quiet", "-noautoopen"])
        return point
    }

    /// El DMG trae CAOBA.app, con la versión anunciada y una firma que verifica.
    private static func verify(_ app: URL, expectedVersion: String) throws {
        guard FileManager.default.fileExists(atPath: app.path) else { throw CaobaError.cannotReadImage("CAOBA.app") }
        let plist = app.appendingPathComponent("Contents/Info.plist")
        let version = (NSDictionary(contentsOf: plist)?["CFBundleShortVersionString"] as? String) ?? ""
        guard version == expectedVersion else { throw CaobaError.invalidParameters(L("El DMG trae la versión ") + version + L(", no la ") + expectedVersion) }
        let check = Process()
        check.executableURL = URL(fileURLWithPath: "/usr/bin/codesign")
        check.arguments = ["--verify", "--deep", "--strict", app.path]
        try check.run()
        check.waitUntilExit()
        guard check.terminationStatus == 0 else { throw CaobaError.invalidParameters(L("La firma de la app descargada no verifica.")) }
    }

    /// Solo se sustituye una app instalada en una carpeta escribible, que no sea
    /// un DMG montado ni la carpeta de compilación.
    private static func canReplace(_ app: URL) -> Bool {
        let folder = app.deletingLastPathComponent()
        guard FileManager.default.isWritableFile(atPath: folder.path) else { return false }
        if app.path.hasPrefix("/Volumes/") { return false }
        if app.path.contains("/DerivedData/") || app.path.contains("/build/") { return false }
        return app.pathExtension == "app"
    }

    /// Copia la nueva junto a la actual, intercambia y borra la antigua; así nunca falta la app.
    private static func replace(_ current: URL, with newApp: URL) throws {
        let fm = FileManager.default
        let folder = current.deletingLastPathComponent()
        let staged = folder.appendingPathComponent(".CAOBA-nueva-\(UUID().uuidString).app")
        let old = folder.appendingPathComponent(".CAOBA-antigua-\(UUID().uuidString).app")
        try fm.copyItem(at: newApp, to: staged)
        removeQuarantine(staged)
        try fm.moveItem(at: current, to: old)
        do {
            try fm.moveItem(at: staged, to: current)
        } catch {
            try? fm.moveItem(at: old, to: current)
            throw error
        }
        try? fm.removeItem(at: old)
    }

    /// Lanza la app nueva en cuanto esta haya salido.
    private static func relaunch(_ app: URL) {
        let script = "while kill -0 \(ProcessInfo.processInfo.processIdentifier) 2>/dev/null; do sleep 0.2; done; open -n \"\(app.path)\""
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/sh")
        process.arguments = ["-c", script]
        try? process.run()
        NSApp.terminate(nil)
    }

    /// Quita el atributo de cuarentena (la firma es ad hoc; si no, macOS avisaría al abrir).
    private static func removeQuarantine(_ url: URL) {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/xattr")
        process.arguments = ["-rd", "com.apple.quarantine", url.path]
        try? process.run()
        process.waitUntilExit()
    }

    private static func run(_ tool: String, _ arguments: [String]) async throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: tool)
        process.arguments = arguments
        process.standardError = FileHandle.nullDevice
        try process.run()
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            process.terminationHandler = { _ in continuation.resume() }
        }
        guard process.terminationStatus == 0 else { throw CaobaError.invalidParameters((tool as NSString).lastPathComponent + " " + (arguments.first ?? "")) }
    }
}

/// Descarga con `URLSession` y delegado: progreso real y cancelación.
private final class Downloader: NSObject, URLSessionDownloadDelegate, @unchecked Sendable {
    private var progress: (@Sendable (Double) -> Void)?
    private var destination: URL?
    private var continuation: CheckedContinuation<Void, Error>?
    private var task: URLSessionDownloadTask?

    func download(_ url: URL, to destination: URL, progress: @escaping @Sendable (Double) -> Void) async throws {
        self.progress = progress
        self.destination = destination
        let session = URLSession(configuration: .ephemeral, delegate: self, delegateQueue: nil)
        defer { session.finishTasksAndInvalidate() }
        try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
                self.continuation = continuation
                let task = session.downloadTask(with: url)
                self.task = task
                task.resume()
            }
        } onCancel: {
            task?.cancel()
        }
    }

    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didWriteData bytesWritten: Int64, totalBytesWritten: Int64, totalBytesExpectedToWrite: Int64) {
        guard totalBytesExpectedToWrite > 0 else { return }
        progress?(min(0.99, Double(totalBytesWritten) / Double(totalBytesExpectedToWrite)))
    }

    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didFinishDownloadingTo location: URL) {
        // El fichero temporal del sistema desaparece al volver: se mueve ya.
        guard let destination else { return }
        do {
            try? FileManager.default.removeItem(at: destination)
            try FileManager.default.moveItem(at: location, to: destination)
            if let http = downloadTask.response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
                throw CaobaError.cannotReadImage(downloadTask.originalRequest?.url?.lastPathComponent ?? "DMG")
            }
            progress?(1)
            continuation?.resume()
        } catch {
            continuation?.resume(throwing: error)
        }
        continuation = nil
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        guard let error, let continuation else { return }
        self.continuation = nil
        if (error as NSError).code == NSURLErrorCancelled { continuation.resume(throwing: CancellationError()) } else { continuation.resume(throwing: error) }
    }
}

