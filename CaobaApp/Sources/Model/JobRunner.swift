import Foundation
import Observation
import CaobaCore

/// Resultado de un trabajo, para mostrarlo al usuario.
struct JobOutcome: Equatable {
    enum Kind { case success, warning, error, cancelled }
    var kind: Kind
    var message: String
    /// Ruta a abrir con el botón "Abrir", si aplica.
    var openURL: URL?
}

/// Ejecuta un trabajo largo del motor, publica su progreso y permite cancelarlo.
@MainActor
@Observable
final class JobRunner {
    private(set) var isRunning = false
    private(set) var progress: JobProgress?
    var outcome: JobOutcome?
    private var task: Task<Void, Never>?

    /// Lanza el trabajo. `body` recibe el callback de progreso y devuelve el mensaje final.
    func run(openURL: URL? = nil, quietOnSuccess: Bool = false, _ body: @escaping @Sendable (@escaping ProgressHandler) async throws -> BatchSummary) {
        guard !isRunning else { return }
        isRunning = true
        progress = nil
        outcome = nil
        task = Task { [weak self] in
            guard let self else { return }
            let handler: ProgressHandler = { p in
                Task { @MainActor in self.progress = p }
            }
            do {
                let summary = try await body(handler)
                let outcome = Self.outcome(for: summary, openURL: openURL)
                finish(with: outcome)
                if quietOnSuccess, outcome.kind == .success { self.outcome = nil }
            } catch let error as CaobaError where error == .cancelled {
                finish(with: JobOutcome(kind: .cancelled, message: L("Cancelado por el usuario.")))
            } catch {
                finish(with: JobOutcome(kind: .error, message: Self.describe(error)))
            }
        }
    }

    func cancel() {
        task?.cancel()
    }

    private func finish(with outcome: JobOutcome) {
        isRunning = false
        progress = nil
        task = nil
        self.outcome = outcome
    }

    /// Texto de resultado a partir del resumen del lote.
    static func outcome(for summary: BatchSummary, openURL: URL?) -> JobOutcome {
        var parts: [String] = [String(localized: "\(summary.processed) archivos procesados.")]
        if summary.skipped > 0 { parts.append(String(localized: "\(summary.skipped) omitidos.")) }
        if !summary.failures.isEmpty {
            parts.append(String(localized: "\(summary.failures.count) con error:"))
            parts.append(contentsOf: summary.failures.prefix(5))
        }
        let kind: JobOutcome.Kind = summary.failures.isEmpty ? .success : (summary.processed > 0 ? .warning : .error)
        return JobOutcome(kind: kind, message: parts.joined(separator: "\n"), openURL: openURL)
    }

    /// Errores del motor en lenguaje de usuario.
    static func describe(_ error: Error) -> String {
        guard let caoba = error as? CaobaError else { return error.localizedDescription }
        switch caoba {
        case .cancelled: return L("Cancelado por el usuario.")
        case .cannotReadImage(let name): return L("No se pudo leer la imagen: \(name)")
        case .cannotWriteImage(let name): return L("No se pudo escribir la imagen: \(name)")
        case .noFiles: return L("No hay archivos que procesar.")
        case .invalidParameters(let what): return L("Parámetros no válidos: \(what)")
        case .metadataWriteFailed(let what): return L("No se pudieron escribir los metadatos: \(what)")
        case .fileOperationFailed(let what): return L("Error de archivo: \(what)")
        }
    }
}

extension JobPhase {
    /// Texto de la fase para la hoja de progreso.
    var label: String {
        switch self {
        case .scanning: return L("Leyendo carpeta…")
        case .thumbnails: return L("Generando miniaturas…")
        case .processingImages: return L("Procesando imágenes…")
        case .watermarking: return L("Aplicando marca de agua…")
        case .writingMetadata: return L("Escribiendo metadatos…")
        case .renaming: return L("Renombrando…")
        case .readingMetadata: return L("Leyendo metadatos…")
        case .generatingContactSheet: return L("Generando contact sheet…")
        case .generatingCollage: return L("Generando collage…")
        case .generatingKenBurns: return L("Generando efectos Ken Burns…")
        case .encodingVideo: return L("Codificando vídeo…")
        case .analyzingAudio: return L("Analizando audio…")
        case .mixingAudio: return L("Mezclando audio…")
        case .generatingFrames: return L("Generando fotogramas…")
        }
    }
}
