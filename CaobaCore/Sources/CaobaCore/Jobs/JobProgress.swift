import Foundation

/// Fase en la que está un trabajo. La app la traduce a texto.
public enum JobPhase: String, Sendable, Codable {
    case scanning
    case thumbnails
    case processingImages
    case watermarking
    case writingMetadata
    case renaming
    case readingMetadata
    case generatingContactSheet
    case generatingCollage
    case generatingKenBurns
    case encodingVideo
    case analyzingAudio
    case mixingAudio
    case generatingFrames
}

/// Estado de avance que el motor va emitiendo mientras trabaja.
public struct JobProgress: Sendable, Equatable {
    public var phase: JobPhase
    /// De 0 a 1. `nil` cuando no se puede estimar (indeterminado).
    public var fraction: Double?
    /// Nombre del fichero que se está tratando, si aplica.
    public var currentFile: String?

    public init(phase: JobPhase, fraction: Double? = nil, currentFile: String? = nil) {
        self.phase = phase
        self.fraction = fraction
        self.currentFile = currentFile
    }

    /// Progreso calculado como "i de n".
    public static func step(_ index: Int, of total: Int, phase: JobPhase, file: String? = nil) -> JobProgress {
        let fraction = total > 0 ? Double(index) / Double(total) : nil
        return JobProgress(phase: phase, fraction: fraction, currentFile: file)
    }
}

/// Callback de progreso. Se llama desde tareas en segundo plano, por eso es `Sendable`.
public typealias ProgressHandler = @Sendable (JobProgress) -> Void

/// Resumen de un trabajo por lotes.
public struct BatchSummary: Sendable, Equatable {
    public var processed: Int
    public var skipped: Int
    public var failures: [String]

    public init(processed: Int = 0, skipped: Int = 0, failures: [String] = []) {
        self.processed = processed
        self.skipped = skipped
        self.failures = failures
    }
}

public extension Task where Success == Never, Failure == Never {
    /// Lanza `CaobaError.cancelled` si la tarea se ha cancelado. Los trabajos
    /// largos lo llaman en cada iteración.
    static func checkCaobaCancellation() throws {
        if Task.isCancelled { throw CaobaError.cancelled }
    }
}

/// Limita cuántas tareas concurrentes pueden pasar a la vez. Lo usamos para no
/// decodificar cientos de imágenes al mismo tiempo.
public actor AsyncSemaphore {
    private let limit: Int
    private var current = 0
    private var waiters: [CheckedContinuation<Void, Never>] = []

    public init(limit: Int) {
        self.limit = max(1, limit)
    }

    public func wait() async {
        if current < limit {
            current += 1
            return
        }
        await withCheckedContinuation { waiters.append($0) }
    }

    public func signal() {
        if let next = waiters.first {
            waiters.removeFirst()
            next.resume()
        } else {
            current -= 1
        }
    }

    /// Ejecuta `body` dentro del límite de concurrencia.
    public func run<T: Sendable>(_ body: @Sendable () async throws -> T) async rethrows -> T {
        await wait()
        defer { signal() }
        return try await body()
    }
}
