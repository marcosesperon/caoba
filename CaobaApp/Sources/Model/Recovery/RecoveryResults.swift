import Foundation
import Observation
import CaobaCore

/// Lo recuperado en una carpeta: lista, filtro por tipo, selección y orden por fecha.
@MainActor
@Observable
final class RecoveryResults {
    /// Filtro de la cuadrícula: todo, un grupo o «Otros».
    enum Filter: Hashable {
        case all
        case group(RecoveryFileGroup)
        case other
    }

    let folder: URL
    private(set) var files: [URL] = []
    private(set) var isLoading = true
    var filter: Filter = .all
    var selection: URL?
    /// Fichero abierto en la vista previa de QuickLook (`nil` = cerrada).
    var previewURL: URL?
    /// Resumen del último «Ordenar por fecha» y dónde se dejó.
    private(set) var organizeSummary: PhotoOrganizer.Summary?
    private(set) var organizedFolder: URL?

    @ObservationIgnored let thumbnails = QuickLookThumbnails()

    init(folder: URL) {
        self.folder = folder
    }

    /// Lista los ficheros fuera del hilo principal (puede haber miles).
    func load() async {
        let folder = folder
        files = await Task.detached { RecoveredFiles.list(in: folder) }.value
        isLoading = false
    }

    var filteredFiles: [URL] {
        switch filter {
        case .all: return files
        case .group(let group): return files.filter { RecoveryFileGroup.group(of: $0) == group }
        case .other: return files.filter { RecoveryFileGroup.group(of: $0) == nil }
        }
    }

    var counts: RecoveredFiles.Counts { RecoveredFiles.count(files) }

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
