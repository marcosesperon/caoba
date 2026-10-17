import SwiftUI
import CaobaCore

/// Lista compartida de ficheros con casilla por fichero, "Todas / Ninguna",
/// miniatura, orden (nombre / fecha) y filtro de orientación.
struct FileListView: View {
    @Environment(AppState.self) private var appState
    var allowsReorder = false
    /// Si se pasa, un clic en la fila la selecciona (para fichas de detalle).
    var selection: Binding<URL?>? = nil
    /// Nombres que llevan un punto indicador (por ejemplo, con cambios pendientes).
    var markedNames: Set<String> = []
    /// Con `false` la lista va sin bloque propio, para quien ya la mete en uno (pestaña Fotos del Slideshow).
    var framed = true
    @State private var previewURL: URL?

    var body: some View {
        @Bindable var state = appState
        VStack(spacing: 6) {
            // Si la cabecera no cabe en una fila, los selectores bajan a una segunda.
            ViewThatFits(in: .horizontal) {
                HStack(spacing: 10) {
                    checkAllControls
                    Spacer()
                    sortControls
                }
                VStack(alignment: .leading, spacing: 6) {
                    HStack { checkAllControls; Spacer() }
                    HStack { sortControls; Spacer() }
                }
            }
            List {
                ForEach(Array(appState.files.enumerated()), id: \.element.id) { index, file in
                    FileRow(index: index, file: file, isChecked: !appState.excludedNames.contains(file.name),
                            isSelected: selection?.wrappedValue == file.url, isMarked: markedNames.contains(file.name)) {
                        appState.toggle(file)
                    } onPreview: {
                        previewURL = file.url
                    }
                    .contentShape(Rectangle())
                    .onTapGesture { selection?.wrappedValue = file.url }
                }
                .onMove { from, to in
                    if allowsReorder { appState.moveFiles(from: from, to: to) }
                }
            }
            .listStyle(.inset)
            // Sin el fondo propio de la lista: así se ve el del bloque y no queda un recuadro dentro de otro.
            .scrollContentBackground(.hidden)
            .overlay {
                if appState.sourceFolder == nil {
                    ContentUnavailableView("Sin carpeta", systemImage: "folder", description: Text("Elige una carpeta de fotos arriba."))
                } else if appState.files.isEmpty && !appState.isScanning {
                    ContentUnavailableView("Carpeta vacía", systemImage: "photo.on.rectangle", description: Text("No hay imágenes compatibles en esta carpeta."))
                }
            }
        }
        .modifier(OptionalPanel(enabled: framed))
        .sheet(item: $previewURL) { url in PhotoPreviewSheet(url: url) }
    }

    /// Casilla general (marcada = todas; desmarcada = ninguna) y contador.
    private var checkAllControls: some View {
        HStack(spacing: 8) {
            Toggle("", isOn: Binding(
                get: { appState.checkedCount == appState.files.count && !appState.files.isEmpty },
                set: { appState.setAllChecked($0) }
            ))
            .toggleStyle(.checkbox).labelsHidden()
            .help("Marcar o desmarcar todas las fotos")
            .disabled(appState.files.isEmpty)
            Text("\(appState.checkedCount) de \(appState.files.count)")
                .font(.callout).foregroundStyle(.secondary)
        }
    }

    /// Orden y filtro de orientación.
    private var sortControls: some View {
        @Bindable var state = appState
        return HStack(spacing: 10) {
            Picker("Orden", selection: $state.sortMode) {
                Text("Nombre").tag(SortMode.name)
                Text("Fecha").tag(SortMode.date)
            }
            .fixedSize()
            Picker("Orientación", selection: $state.orientationFilter) {
                Text("Todas").tag(OrientationFilter.all)
                Text("Horizontales").tag(OrientationFilter.horizontal)
                Text("Verticales").tag(OrientationFilter.vertical)
            }
            .fixedSize()
        }
    }
}

/// Bloque común solo si se pide (la lista puede ir dentro de otro bloque).
private struct OptionalPanel: ViewModifier {
    let enabled: Bool
    func body(content: Content) -> some View {
        if enabled { content.caobaPanel(padding: 8) } else { content }
    }
}

private struct FileRow: View {
    let index: Int
    let file: ScannedFile
    let isChecked: Bool
    var isSelected = false
    var isMarked = false
    let onToggle: () -> Void
    let onPreview: () -> Void

    var body: some View {
        HStack(spacing: 8) {
            Toggle("", isOn: Binding(get: { isChecked }, set: { _ in onToggle() }))
                .toggleStyle(.checkbox).labelsHidden()
            Text("\(index + 1)").font(.caption.monospacedDigit()).foregroundStyle(.secondary).frame(width: 32, alignment: .trailing)
            ThumbnailView(url: file.url).onTapGesture(perform: onPreview)
            VStack(alignment: .leading) {
                Text(file.name).lineLimit(1)
                if let size = file.size {
                    Text("\(size.width) × \(size.height)").font(.caption).foregroundStyle(.secondary)
                }
            }
            Spacer()
            if isMarked {
                Circle().fill(Color.accentColor).frame(width: 8, height: 8).help("Con cambios pendientes")
            }
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 2)
        .background(isSelected ? Color.accentColor.opacity(0.2) : .clear, in: RoundedRectangle(cornerRadius: 6))
        .opacity(isChecked ? 1 : 0.4)
    }
}

extension URL: @retroactive Identifiable {
    public var id: String { absoluteString }
}

/// Vista previa de una foto a tamaño de ventana.
struct PhotoPreviewSheet: View {
    @Environment(\.dismiss) private var dismiss
    let url: URL
    @State private var image: CGImage?

    var body: some View {
        VStack {
            CGImageView(image: image)
            HStack {
                Text(url.lastPathComponent).font(.callout).foregroundStyle(.secondary)
                Spacer()
                Button("Cerrar") { dismiss() }.keyboardShortcut(.cancelAction)
            }
        }
        .padding()
        .frame(minWidth: 700, minHeight: 500)
        .task { image = await Task.detached { ThumbnailProvider.makeThumbnail(url: url, maxPixelSize: 2000) }.value }
    }
}
