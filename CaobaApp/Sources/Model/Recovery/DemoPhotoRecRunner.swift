#if DEBUG
import Foundation
import CaobaCore

/// PhotoRec de mentira, solo en las compilaciones de desarrollo: va copiando las fotos de una
/// carpeta a `recup_dir.N` de poco en poco, como si las encontrara en una tarjeta. Sirve para
/// probar y capturar la cuadrícula en directo, eliminar mientras busca y la pausa, sin tarjeta
/// ni contraseña. Se lanza con `--state recovery.demo=<carpeta con fotos>`.
@MainActor
final class DemoPhotoRecRunner: PhotoRecRunning {
    /// Ficheros por bloque: pocos, para ver varios bloques enseguida (PhotoRec usa 500).
    static let filesPerBlock = 12

    private let source: URL
    private var paused = false
    private var cancelled = false

    init(source: URL) {
        self.source = source
    }

    func run(arguments: [String], device: String, outputFolder: URL) async throws -> PhotoRecOutcome {
        let fm = FileManager.default
        let photos = ((try? fm.contentsOfDirectory(at: source, includingPropertiesForKeys: nil)) ?? [])
            .filter { RecoveryFileGroup.group(of: $0) != nil }
            .sorted { $0.lastPathComponent < $1.lastPathComponent }
        let log = outputFolder.appendingPathComponent(PhotoRecCommand.logFileName)
        try "PhotoRec (demo)\n".write(to: log, atomically: true, encoding: .utf8)

        for (index, photo) in photos.enumerated() {
            while paused && !cancelled { try? await Task.sleep(for: .milliseconds(100)) }
            if cancelled { return .cancelled }
            let block = outputFolder.appendingPathComponent("\(PhotoRecCommand.outputPrefix).\(index / Self.filesPerBlock + 1)")
            try? fm.createDirectory(at: block, withIntermediateDirectories: true)
            let name = String(format: "f%07d.", (index + 1) * 2048) + photo.pathExtension.lowercased()
            // Clon APFS: instantáneo y sin ocupar sitio de más.
            try? fm.copyItem(at: photo, to: block.appendingPathComponent(name))
            try? await Task.sleep(for: .milliseconds(400))
        }
        try "PhotoRec (demo)\nPhotoRec exited normally.\n".write(to: log, atomically: true, encoding: .utf8)
        return .finished(PhotoRecReport.parse(log: try String(contentsOf: log, encoding: .utf8)), exitCode: 0)
    }

    func cancel() { cancelled = true }

    func pause() -> Bool {
        paused = true
        return true
    }

    func resume() -> Bool {
        paused = false
        return true
    }
}
#endif
