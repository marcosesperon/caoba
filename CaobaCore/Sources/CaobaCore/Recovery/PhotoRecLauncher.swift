import Foundation

/// Lanza PhotoRec como proceso normal (del usuario) leyendo la tarjeta por un descriptor ya
/// abierto (`AuthOpen`), que le llega como entrada estándar: PhotoRec la abre como
/// `/dev/fd/0`. Su salida por pantalla va a `photorec-output.txt` en la carpeta de salida.
public final class PhotoRecLauncher: @unchecked Sendable {
    /// Lo que PhotoRec escribe por pantalla (el fallo al abrir el disco solo sale por ahí).
    public static let outputFileName = "photorec-output.txt"
    /// Cómo ve PhotoRec la tarjeta: la entrada estándar.
    public static let deviceInput = "/dev/fd/0"

    public struct Exit: Sendable, Equatable {
        public var status: Int32
        /// Lo pararon desde fuera (al cancelar).
        public var wasTerminated: Bool
    }

    private let process = Process()
    private let lock = NSLock()
    private var terminated = false

    public init() {}

    /// Lanza PhotoRec y espera a que acabe. `arguments` son los de `PhotoRecCommand`; donde
    /// aparezca `devicePath` se pone `/dev/fd/0`. `device` se puede cerrar después.
    public func run(photoRec: URL, arguments: [String], devicePath: String, device: FileHandle,
                    outputFolder: URL) async throws -> Exit {
        let outputURL = outputFolder.appendingPathComponent(Self.outputFileName)
        FileManager.default.createFile(atPath: outputURL.path, contents: nil)
        let output = try FileHandle(forWritingTo: outputURL)
        defer { try? output.close() }

        process.executableURL = photoRec
        process.arguments = arguments.map { $0 == devicePath ? Self.deviceInput : $0 }
        process.currentDirectoryURL = outputFolder
        process.standardInput = device
        process.standardOutput = output
        process.standardError = output

        return try await withCheckedThrowingContinuation { continuation in
            process.terminationHandler = { [weak self] process in
                let wasTerminated = self?.lock.withLock { self?.terminated ?? false } ?? false
                continuation.resume(returning: Exit(status: process.terminationStatus, wasTerminated: wasTerminated))
            }
            do { try process.run() } catch { continuation.resume(throwing: error) }
        }
    }

    /// Pide a PhotoRec que pare (SIGTERM): termina limpiamente y `run` vuelve poco después.
    /// Si estaba en pausa, antes se le despierta: un proceso detenido no atiende la señal.
    public func terminate() {
        lock.withLock { terminated = true }
        guard process.isRunning else { return }
        _ = process.resume()
        process.terminate()
    }

    /// Detiene PhotoRec (SIGSTOP) sin perder nada: se queda justo donde estaba hasta `resume()`.
    /// Para cuando el destino se está llenando o el usuario quiere revisar con calma.
    @discardableResult
    public func pause() -> Bool {
        process.isRunning && process.suspend()
    }

    /// Reanuda PhotoRec (SIGCONT) donde se quedó.
    @discardableResult
    public func resume() -> Bool {
        process.isRunning && process.resume()
    }

    /// Identificador del proceso (0 si no ha arrancado). Para las pruebas.
    public var processIdentifier: Int32 { process.processIdentifier }
}
