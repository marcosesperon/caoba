import Foundation

/// Mandos de una descarga en marcha: pausar, seguir y cancelar desde otro hilo.
public final class CardImportControl: @unchecked Sendable {
    private let lock = NSLock()
    private var paused = false
    private var cancelled = false

    public init() {}

    public var isPaused: Bool { lock.withLock { paused } }
    public var isCancelled: Bool { lock.withLock { cancelled } }

    public func pause() { lock.withLock { paused = true } }
    public func resume() { lock.withLock { paused = false } }
    /// Cancelar también despierta una descarga en pausa, para que pueda acabar.
    public func cancel() { lock.withLock { cancelled = true; paused = false } }
}

/// Cómo va una descarga, para enseñarlo.
public struct CardImportProgress: Sendable, Equatable {
    public var filesDone = 0
    public var filesTotal = 0
    public var bytesDone: Int64 = 0
    public var bytesTotal: Int64 = 0
    public var currentName = ""

    public init(filesTotal: Int = 0, bytesTotal: Int64 = 0) {
        self.filesTotal = filesTotal
        self.bytesTotal = bytesTotal
    }
}

/// Cómo terminó una descarga.
public struct CardImportSummary: Sendable, Equatable {
    public enum Ending: Sendable, Equatable {
        case completed
        case cancelled
        /// La tarjeta desapareció a mitad (se sacó o se desmontó).
        case cardRemoved
    }

    /// Por qué no se pudo copiar una foto (el texto lo pone la app, traducido).
    public enum Problem: Sendable, Equatable {
        /// La copia no coincidía con la tarjeta ni al segundo intento.
        case verificationFailed
        /// Otro error, con el mensaje del sistema.
        case other(String)
    }

    public var copied = 0
    public var alreadyThere = 0
    /// Lo que no se pudo copiar: nombre en la tarjeta y motivo.
    public var failures: [(name: String, problem: Problem)] = []
    public var ending: Ending = .completed

    public init() {}

    public static func == (lhs: CardImportSummary, rhs: CardImportSummary) -> Bool {
        lhs.copied == rhs.copied && lhs.alreadyThere == rhs.alreadyThere && lhs.ending == rhs.ending
            && lhs.failures.map(\.name) == rhs.failures.map(\.name) && lhs.failures.map(\.problem) == rhs.failures.map(\.problem)
    }
}

/// Recorre un plan copiando cada foto con `VerifiedCopier`.
///
/// - Antes de cada foto mira si cabe; si no, avisa con `onNeedsSpace`, se pone en pausa y
///   espera a que se libere sitio y se reanude (o a que se cancele).
/// - Si la comprobación falla, repite esa foto una vez; si vuelve a fallar, la apunta y sigue.
/// - Al empezar borra las copias a medias de una descarga anterior cortada.
public enum CardImporter {
    /// Margen libre que se deja además de lo que ocupa la foto.
    public static let spaceMargin: Int64 = 50_000_000

    public static func run(_ plan: CardImportPlan, cardVolume: URL, control: CardImportControl,
                           freeSpace: @Sendable (URL) -> Int64? = Self.freeSpace(at:),
                           onNeedsSpace: @Sendable (Int64) -> Void = { _ in },
                           progress: @Sendable (CardImportProgress) -> Void = { _ in }) async -> CardImportSummary {
        var summary = CardImportSummary()
        summary.alreadyThere = plan.alreadyThere
        var state = CardImportProgress(filesTotal: plan.tasks.count, bytesTotal: plan.bytesToCopy)
        let fm = FileManager.default

        let folders = Set(plan.tasks.flatMap { [$0.destination] + $0.companions.map(\.destination) }.map { $0.deletingLastPathComponent() })
        VerifiedCopier.removePartials(in: folders)

        for task in plan.tasks {
            // Pausa a mano: se espera aquí, entre fotos.
            while control.isPaused { try? await Task.sleep(for: .milliseconds(200)) }
            if control.isCancelled { summary.ending = .cancelled; break }
            if !fm.fileExists(atPath: cardVolume.path) || !fm.fileExists(atPath: task.source.url.path) {
                summary.ending = .cardRemoved
                break
            }
            // ¿Cabe? Si no, pausa hasta que haya sitio.
            let needed = task.totalSize + spaceMargin
            if let free = freeSpace(task.destination.deletingLastPathComponent().existingAncestor), free < needed {
                control.pause()
                onNeedsSpace(needed)
                while control.isPaused { try? await Task.sleep(for: .milliseconds(200)) }
                if control.isCancelled { summary.ending = .cancelled; break }
            }

            state.currentName = task.source.url.lastPathComponent
            progress(state)
            let before = state.bytesDone
            var failure: CardImportSummary.Problem?
            for (source, destination) in [(task.source, task.destination)] + task.companions.map({ ($0.source, $0.destination) }) {
                if let problem = copyWithRetry(source, to: destination, control: control, onBytes: { bytes in
                    state.bytesDone += bytes
                    progress(state)
                }) {
                    failure = problem
                    break
                }
            }
            if control.isCancelled { summary.ending = .cancelled; break }
            if let failure {
                summary.failures.append((task.source.url.lastPathComponent, failure))
                state.bytesDone = before + task.totalSize
            } else {
                summary.copied += 1
            }
            state.filesDone += 1
            progress(state)
        }
        return summary
    }

    /// Copia con un reintento si la comprobación falla. Devuelve el motivo si no se pudo
    /// (al cancelar no hay motivo: quien llama ya mira si se ha cancelado).
    private static func copyWithRetry(_ source: CardFile, to destination: URL, control: CardImportControl,
                                      onBytes: (Int64) -> Void) -> CardImportSummary.Problem? {
        for attempt in 1...2 {
            do {
                try VerifiedCopier.copy(source, to: destination, progress: onBytes, isCancelled: { control.isCancelled })
                return nil
            } catch VerifiedCopier.Failure.cancelled {
                return nil
            } catch VerifiedCopier.Failure.verificationFailed where attempt == 1 {
                continue
            } catch VerifiedCopier.Failure.verificationFailed {
                return .verificationFailed
            } catch {
                return .other(error.localizedDescription)
            }
        }
        return nil
    }

    /// Espacio libre de verdad en el disco de `url`.
    public static func freeSpace(at url: URL) -> Int64? {
        (try? url.resourceValues(forKeys: [.volumeAvailableCapacityKey]).volumeAvailableCapacity).map(Int64.init)
    }
}

extension URL {
    /// La propia carpeta o la primera de sus padres que exista (la de fecha aún no se ha creado).
    var existingAncestor: URL {
        var url = self
        while !FileManager.default.fileExists(atPath: url.path), url.pathComponents.count > 1 {
            url = url.deletingLastPathComponent()
        }
        return url
    }
}
