import Foundation
import Observation
import CaobaCore

/// Lo recuperado en una carpeta: bloques, filtro por tipo, marcas para eliminar y orden por
/// fecha. Sirve mientras PhotoRec busca (en directo, refrescado desde la sesión) y al terminar.
@MainActor
@Observable
final class RecoveryResults {
    /// Filtro de la cuadrícula: todo, un grupo o «Otros».
    enum Filter: Hashable {
        case all
        case group(RecoveryFileGroup)
        case other
    }

    /// Mientras PhotoRec escribe, un fichero que ha cambiado hace menos de esto no se enseña:
    /// probablemente es el que está escribiendo (no se puede borrar ni dar miniatura todavía).
    static let settleTime: TimeInterval = 3

    let folder: URL
    /// `true` mientras PhotoRec sigue buscando: el último bloque está «en curso».
    var isLive: Bool
    private(set) var blocks: [RecoveredFiles.Block] = []
    private(set) var isLoading = true
    var filter: Filter = .all
    var selection: URL?
    /// Fichero abierto en la vista previa de QuickLook (`nil` = cerrada).
    var previewURL: URL?
    /// Ficheros marcados para eliminar.
    private(set) var checked: Set<URL> = []
    /// Último fichero marcado a mano, para marcar un tramo con mayúsculas + clic.
    @ObservationIgnored private var anchor: URL?
    /// Cuántos ficheros se han eliminado desde aquí, y el último problema al eliminar.
    private(set) var deletedCount = 0
    private(set) var deleteError: String?
    private(set) var isDeleting = false
    /// Resumen del último «Ordenar por fecha» y dónde se dejó.
    private(set) var organizeSummary: PhotoOrganizer.Summary?
    private(set) var organizedFolder: URL?

    @ObservationIgnored let thumbnails = QuickLookThumbnails()
    @ObservationIgnored private var isRefreshing = false

    init(folder: URL, isLive: Bool = false) {
        self.folder = folder
        self.isLive = isLive
    }

    // MARK: Lista

    /// Vuelve a leer la carpeta fuera del hilo principal (puede haber miles de ficheros).
    /// Las marcas de lo que ya no existe se quitan.
    func refresh() async {
        guard !isRefreshing else { return }
        isRefreshing = true
        defer { isRefreshing = false }
        let folder = folder
        let settle = isLive ? Self.settleTime : 0
        let fresh = await Task.detached { RecoveredFiles.blocks(in: folder, settledFor: settle) }.value
        if fresh != blocks { blocks = fresh }
        let existing = Set(fresh.flatMap(\.files))
        if !checked.isSubset(of: existing) { checked.formIntersection(existing) }
        if let preview = previewURL, !existing.contains(preview) { previewURL = nil }
        isLoading = false
    }

    var files: [URL] { blocks.flatMap(\.files) }

    var filteredFiles: [URL] { filteredBlocks.flatMap(\.files) }

    /// Bloques con solo lo que deja ver el filtro; los que se quedan vacíos no salen.
    var filteredBlocks: [RecoveredFiles.Block] {
        blocks.compactMap { block in
            var visible = block
            visible.files = block.files.filter(matchesFilter)
            return visible.files.isEmpty ? nil : visible
        }
    }

    var counts: RecoveredFiles.Counts { RecoveredFiles.count(files) }

    /// Bloque en el que sigue escribiendo PhotoRec: el último, mientras busca.
    func isInProgress(_ block: RecoveredFiles.Block) -> Bool {
        isLive && block.number == blocks.last?.number
    }

    private func matchesFilter(_ url: URL) -> Bool {
        switch filter {
        case .all: return true
        case .group(let group): return RecoveryFileGroup.group(of: url) == group
        case .other: return RecoveryFileGroup.group(of: url) == nil
        }
    }

    // MARK: Marcas

    func isChecked(_ url: URL) -> Bool { checked.contains(url) }

    /// Marca o desmarca un fichero. Con `extend` (mayúsculas), deja todo el tramo desde el
    /// último marcado a mano igual que este, en el orden que se ve.
    func toggle(_ url: URL, extend: Bool) {
        let mark = !checked.contains(url)
        let visible = filteredFiles
        if extend, let anchor, let from = visible.firstIndex(of: anchor), let to = visible.firstIndex(of: url) {
            let range = visible[min(from, to)...max(from, to)]
            if mark { checked.formUnion(range) } else { checked.subtract(range) }
        } else if mark {
            checked.insert(url)
        } else {
            checked.remove(url)
        }
        anchor = url
    }

    /// Marca todo lo que deja ver el filtro (por ejemplo, todos los vídeos).
    func checkVisible() { checked.formUnion(filteredFiles) }

    func uncheckAll() {
        checked.removeAll()
        anchor = nil
    }

    /// Marca lo que se ve de un bloque, o lo desmarca si ya estaba todo marcado.
    func toggleBlock(_ block: RecoveredFiles.Block) {
        let visible = block.files.filter(matchesFilter)
        if Set(visible).isSubset(of: checked) { checked.subtract(visible) } else { checked.formUnion(visible) }
    }

    func isBlockChecked(_ block: RecoveredFiles.Block) -> Bool {
        let visible = block.files.filter(matchesFilter)
        return !visible.isEmpty && Set(visible).isSubset(of: checked)
    }

    // MARK: Eliminar

    /// Borra para siempre lo marcado (la vista ya ha pedido confirmación).
    func deleteChecked() async {
        let toDelete = Array(checked)
        guard !toDelete.isEmpty, !isDeleting else { return }
        isDeleting = true
        let result = await Task.detached { RecoveredFiles.delete(toDelete) }.value
        deletedCount += result.deleted
        deleteError = result.failures.isEmpty ? nil
            : L("No se han podido eliminar \(result.failures.count) ficheros: \(result.failures.prefix(3).joined(separator: "; "))")
        checked.subtract(toDelete)
        isDeleting = false
        await refresh()
    }

    /// Borra un bloque entero. El que está en curso no se puede.
    func deleteBlock(_ block: RecoveredFiles.Block) async {
        guard !isInProgress(block), !isDeleting else { return }
        isDeleting = true
        let result = await Task.detached { Result { try RecoveredFiles.deleteBlock(block) } }.value
        switch result {
        case .success(let count):
            deletedCount += count
            deleteError = nil
        case .failure(let error):
            deleteError = L("No se ha podido eliminar el bloque \(block.number): \(error.localizedDescription)")
        }
        checked.subtract(block.files)
        isDeleting = false
        await refresh()
    }

    // MARK: Ordenar por fecha

    /// Copia lo que se ve (el filtro actual) a `destination`, ordenado por fecha, con la
    /// hoja de progreso de la app. El resumen se enseña en la propia pantalla de resultados.
    func organize(into destination: URL, with jobRunner: JobRunner) {
        let toCopy = filteredFiles
        organizeSummary = nil
        organizedFolder = destination
        jobRunner.run(openURL: destination, quietOnSuccess: true) { [weak self] progress in
            let summary = try await PhotoOrganizer.organize(toCopy, into: destination, progress: progress)
            await MainActor.run { self?.organizeSummary = summary }
            return BatchSummary(processed: summary.copied, failures: summary.failures)
        }
    }
}
