import SwiftUI
import QuickLook
import CaobaCore

/// Cuadrícula de lo recuperado, agrupada por bloques (cada carpeta `recup_dir.N` de PhotoRec):
/// filtro por tipo, casillas para eliminar lo que no interesa (sueltas, en tramo, lo que se ve o
/// el bloque entero), miniaturas que se cargan al verse, vista previa con QuickLook (doble clic
/// o espacio) y «Ordenar por fecha…». Funciona igual mientras PhotoRec busca y al terminar.
struct RecoveryResultsView: View {
    @Environment(AppState.self) private var appState
    @Bindable var results: RecoveryResults
    @FocusState private var gridFocused: Bool
    /// Lo que espera confirmación para eliminarse.
    @State private var pendingDeletion: PendingDeletion?

    private let cellSize: CGFloat = 140

    enum PendingDeletion: Identifiable {
        case checked(Int)
        case block(RecoveredFiles.Block)
        var id: String {
            switch self {
            case .checked: return "checked"
            case .block(let block): return "block-\(block.number)"
            }
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            toolbar
            markBar
            if let summary = results.organizeSummary { organizeSummary(summary) }
            if results.isLoading {
                ProgressView("Leyendo lo recuperado…").frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                grid
            }
        }
        .task(id: results.folder) { await results.refresh() }
        .quickLookPreview($results.previewURL, in: results.filteredFiles)
        .alert(deletionTitle, isPresented: Binding(get: { pendingDeletion != nil }, set: { if !$0 { pendingDeletion = nil } }),
               presenting: pendingDeletion) { deletion in
            Button("Eliminar", role: .destructive) { confirm(deletion) }
            Button("Cancelar", role: .cancel) {}
        } message: { _ in
            Text("Se borran del disco y no se puede deshacer. Siguen en la tarjeta si hace falta volver a buscarlos.")
        }
    }

    // MARK: Barras

    private var toolbar: some View {
        HStack(spacing: 12) {
            let counts = results.counts
            Picker("", selection: $results.filter) {
                Text("Todo (\(results.files.count))").tag(RecoveryResults.Filter.all)
                ForEach(RecoveryFileGroup.allCases, id: \.self) { group in
                    Text("\(Text(group.title)) (\(counts.byGroup[group] ?? 0))").tag(RecoveryResults.Filter.group(group))
                }
                if counts.other > 0 {
                    Text("Otros (\(counts.other))").tag(RecoveryResults.Filter.other)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .fixedSize()
            Spacer()
            // Ordenar es para el final: mientras busca, la lista aún no está completa.
            if !results.isLive {
                Button("Ordenar por fecha…") { chooseOrganizeDestination() }
                    .disabled(results.filteredFiles.isEmpty || appState.jobRunner.isRunning)
                    .help("Copia lo que se ve a otra carpeta en AAAA/MM-DD/AAAA-MM-DD_HHMMSS. Los originales no se tocan.")
            }
        }
    }

    /// Marcar y eliminar, con lo eliminado hasta ahora y el último problema, si lo hubo.
    private var markBar: some View {
        HStack(spacing: 10) {
            Button("Marcar lo que se ve") { results.checkVisible() }
                .disabled(results.filteredFiles.isEmpty)
                .help("Marca todo lo que deja ver el filtro: por ejemplo, con «Vídeo», todos los vídeos.")
            Button("Desmarcar todo") { results.uncheckAll() }
                .disabled(results.checked.isEmpty)
            Button("Eliminar marcadas (\(results.checked.count))", role: .destructive) {
                pendingDeletion = .checked(results.checked.count)
            }
            .disabled(results.checked.isEmpty || results.isDeleting)
            if results.isDeleting { ProgressView().controlSize(.small) }
            Spacer()
            if let error = results.deleteError {
                Label(error, systemImage: "exclamationmark.triangle").foregroundStyle(.orange).lineLimit(1)
            } else if results.deletedCount > 0 {
                Text("\(results.deletedCount) eliminados").foregroundStyle(.secondary)
            }
        }
        .font(.callout)
        .controlSize(.small)
    }

    private func organizeSummary(_ summary: PhotoOrganizer.Summary) -> some View {
        HStack(spacing: 10) {
            Image(systemName: summary.failures.isEmpty ? "checkmark.circle" : "exclamationmark.triangle")
                .foregroundStyle(summary.failures.isEmpty ? .green : .orange)
            VStack(alignment: .leading, spacing: 2) {
                Text("Ordenado: \(summary.dated) con fecha y \(summary.undated) sin fecha (en «\(PhotoOrganizer.undatedFolder)»).")
                if !summary.failures.isEmpty {
                    Text("\(summary.failures.count) no se pudieron copiar: \(summary.failures.prefix(3).joined(separator: "; "))")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
            Spacer()
            if let folder = results.organizedFolder {
                Button("Mostrar en el Finder") { NSWorkspace.shared.activateFileViewerSelecting([folder]) }
            }
        }
        .caobaPanel()
    }

    // MARK: Cuadrícula

    private var grid: some View {
        let blocks = results.filteredBlocks
        return ScrollView {
            LazyVGrid(columns: [GridItem(.adaptive(minimum: cellSize, maximum: cellSize + 40), spacing: 10)],
                      spacing: 10, pinnedViews: [.sectionHeaders]) {
                ForEach(blocks) { block in
                    Section {
                        ForEach(block.files, id: \.self) { url in
                            RecoveredFileCell(url: url, size: cellSize, thumbnails: results.thumbnails,
                                              isSelected: results.selection == url, isChecked: results.isChecked(url)) {
                                // Mayúsculas + clic en la casilla: todo el tramo desde la última marcada.
                                results.toggle(url, extend: NSEvent.modifierFlags.contains(.shift))
                            }
                            .onTapGesture(count: 2) { results.selection = url; results.previewURL = url }
                            .onTapGesture { results.selection = url; gridFocused = true }
                        }
                    } header: {
                        blockHeader(block)
                    }
                }
            }
            .padding(4)
        }
        .focusable()
        .focused($gridFocused)
        .focusEffectDisabled()
        .onKeyPress(.space) {
            guard let selection = results.selection else { return .ignored }
            results.previewURL = results.previewURL == nil ? selection : nil
            return .handled
        }
        .overlay {
            if blocks.isEmpty {
                if results.isLive {
                    ContentUnavailableView("Todavía no hay nada", systemImage: "magnifyingglass",
                                           description: Text("Lo que encuentre PhotoRec irá saliendo aquí."))
                } else {
                    ContentUnavailableView("Nada de este tipo", systemImage: "photo.on.rectangle")
                }
            }
        }
        .caobaPanel(padding: 6)
    }

    /// «Bloque 3 · 500 ficheros», con marcar y eliminar el bloque. El que está en curso no se elimina.
    private func blockHeader(_ block: RecoveredFiles.Block) -> some View {
        let inProgress = results.isInProgress(block)
        return HStack(spacing: 10) {
            Text("Bloque \(block.number)").font(.headline)
            Text("\(block.files.count) ficheros").foregroundStyle(.secondary)
            if inProgress {
                Label("en curso", systemImage: "arrow.down.circle").foregroundStyle(.secondary)
            }
            Spacer()
            Button(results.isBlockChecked(block) ? "Desmarcar bloque" : "Marcar bloque") { results.toggleBlock(block) }
            if !inProgress {
                Button("Eliminar bloque…", role: .destructive) {
                    // El bloque entero, aunque el filtro oculte parte: se busca el completo.
                    pendingDeletion = .block(results.blocks.first { $0.number == block.number } ?? block)
                }
                .disabled(results.isDeleting)
            }
        }
        .font(.callout)
        .controlSize(.small)
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .background(.bar, in: RoundedRectangle(cornerRadius: 6))
    }

    // MARK: Eliminar

    private var deletionTitle: String {
        switch pendingDeletion {
        case .checked(let count): return L("¿Eliminar \(count) ficheros?")
        case .block(let block): return L("¿Eliminar el bloque \(block.number) entero (\(block.files.count) ficheros)?")
        case nil: return ""
        }
    }

    private func confirm(_ deletion: PendingDeletion) {
        Task {
            switch deletion {
            case .checked: await results.deleteChecked()
            case .block(let block): await results.deleteBlock(block)
            }
        }
    }

    private func chooseOrganizeDestination() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.canCreateDirectories = true
        panel.prompt = L("Ordenar aquí")
        panel.message = L("Elige la carpeta donde copiar lo recuperado ordenado por fecha.")
        if panel.runModal() == .OK, let url = panel.url { results.organize(into: url, with: appState.jobRunner) }
    }
}

/// Una celda: miniatura (o icono mientras carga o si no hay), nombre y casilla para eliminar.
private struct RecoveredFileCell: View {
    let url: URL
    let size: CGFloat
    let thumbnails: QuickLookThumbnails
    let isSelected: Bool
    let isChecked: Bool
    let toggleCheck: () -> Void
    @Environment(\.displayScale) private var scale
    @State private var image: CGImage?
    @State private var failed = false

    var body: some View {
        VStack(spacing: 4) {
            ZStack {
                if let image {
                    Image(decorative: image, scale: scale).resizable().scaledToFit()
                } else if failed {
                    Image(systemName: "doc.questionmark").font(.largeTitle).foregroundStyle(.secondary)
                } else {
                    ProgressView().controlSize(.small)
                }
            }
            .frame(width: size, height: size * 0.75)
            .opacity(isChecked ? 0.55 : 1)
            .overlay(alignment: .topLeading) {
                // La casilla tiene su propio clic: marcar no cambia la selección ni abre la vista previa.
                Image(systemName: isChecked ? "checkmark.square.fill" : "square")
                    .font(.title3)
                    .foregroundStyle(isChecked ? Color.red : Color.white)
                    .shadow(color: .black.opacity(0.6), radius: 2)
                    .padding(4)
                    .contentShape(Rectangle())
                    .onTapGesture(perform: toggleCheck)
                    .help("Marcar para eliminar (mayúsculas + clic: marca el tramo)")
            }
            Text(url.lastPathComponent).font(.caption).lineLimit(1).truncationMode(.middle)
        }
        .padding(6)
        .background(RoundedRectangle(cornerRadius: 6).fill(isSelected ? Color.accentColor.opacity(0.25) : .clear))
        .overlay(RoundedRectangle(cornerRadius: 6).stroke(isChecked ? Color.red : .clear, lineWidth: 2))
        .contentShape(Rectangle())
        // Se carga al aparecer y se cancela al salir de la pantalla (la tarea muere con la celda).
        .task(id: url) {
            image = await thumbnails.thumbnail(for: url, size: size, scale: scale)
            failed = image == nil && !Task.isCancelled
        }
    }
}
