import Foundation

/// Desmonta y vuelve a montar una tarjeta con `diskutil`, sin expulsarla y sin
/// permisos de administrador. Antes de leerla en bruto hay que desmontarla para que
/// macOS no escriba nada en ella mientras PhotoRec trabaja (y para que la deje abrir).
enum DiskMounter {
    enum Failure: Error, Equatable {
        /// `diskutil` no pudo: casi siempre porque alguna app tiene abierto algo de la tarjeta.
        case busy(String)
    }

    /// Desmonta todos los volúmenes del disco (`diskutil unmountDisk`), sin expulsarlo.
    static func unmount(_ disk: ExternalDisk) async throws {
        try await diskutil(["unmountDisk", "/dev/" + disk.bsdName])
    }

    /// Vuelve a montar lo que se pueda (`diskutil mountDisk`). Si falla no es grave: la
    /// tarjeta sigue intacta y basta con sacarla y volverla a meter.
    static func mount(_ disk: ExternalDisk) async {
        try? await diskutil(["mountDisk", "/dev/" + disk.bsdName])
    }

    private static func diskutil(_ arguments: [String]) async throws {
        let message: String? = try await withCheckedThrowingContinuation { continuation in
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/sbin/diskutil")
            process.arguments = arguments
            let pipe = Pipe()
            process.standardOutput = pipe
            process.standardError = pipe
            process.terminationHandler = { process in
                let text = String(decoding: pipe.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
                continuation.resume(returning: process.terminationStatus == 0 ? nil : text)
            }
            do { try process.run() } catch { continuation.resume(throwing: error) }
        }
        if let message { throw Failure.busy(message.trimmingCharacters(in: .whitespacesAndNewlines)) }
    }
}
