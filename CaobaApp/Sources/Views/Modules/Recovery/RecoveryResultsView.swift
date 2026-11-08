import SwiftUI
import QuickLook
import CaobaCore

/// Cuadrícula de lo recuperado: filtro por tipo, miniaturas que se cargan al verse,
/// vista previa con QuickLook (doble clic o espacio) y «Ordenar por fecha…».
struct RecoveryResultsView: View {
    @Environment(AppState.self) private var appState
    @Bindable var results: RecoveryResults
    @FocusState private var gridFocused: Bool

    private let cellSize: CGFloat = 140

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            toolbar
            if let summary = results.organizeSummary { organizeSummary(summary) }
            if results.isLoading {
                ProgressView("Leyendo lo recuperado…").frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                grid
            }
        }
        .task(id: results.folder) { await results.load() }
        .quickLookPreview($results.previewURL, in: results.filteredFiles)
    }

    // MARK: Barra

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
            Button("Ordenar por fecha…") { chooseOrganizeDestination() }
                .disabled(results.filteredFiles.isEmpty || appState.jobRunner.isRunning)
                .help("Copia lo que se ve a otra carpeta en AAAA/MM-DD/AAAA-MM-DD_HHMMSS. Los originales no se tocan.")
        }
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
        let files = results.filteredFiles
        return ScrollView {
            LazyVGrid(columns: [GridItem(.adaptive(minimum: cellSize, maximum: cellSize + 40), spacing: 10)], spacing: 10) {
                ForEach(files, id: \.self) { url in
                    RecoveredFileCell(url: url, size: cellSize, thumbnails: results.thumbnails,
                                      isSelected: results.selection == url)
                        .onTapGesture(count: 2) { results.selection = url; results.previewURL = url }
                        .onTapGesture { results.selection = url; gridFocused = true }
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
            if files.isEmpty { ContentUnavailableView("Nada de este tipo", systemImage: "photo.on.rectangle") }
        }
        .caobaPanel(padding: 6)
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

/// Una celda: miniatura (o icono mientras carga o si no hay), nombre y tipo.
private struct RecoveredFileCell: View {
    let url: URL
    let size: CGFloat
    let thumbnails: QuickLookThumbnails
    let isSelected: Bool
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
            Text(url.lastPathComponent).font(.caption).lineLimit(1).truncationMode(.middle)
        }
        .padding(6)
        .background(RoundedRectangle(cornerRadius: 6).fill(isSelected ? Color.accentColor.opacity(0.25) : .clear))
        .contentShape(Rectangle())
        // Se carga al aparecer y se cancela al salir de la pantalla (la tarea muere con la celda).
        .task(id: url) {
            image = await thumbnails.thumbnail(for: url, size: size, scale: scale)
            failed = image == nil && !Task.isCancelled
        }
    }
}
