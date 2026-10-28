import SwiftUI
import AppKit
import CaobaCore

/// Foto que se abre en el visor: su posición en la lista y el tamaño que tendrá la hoja.
struct PhotoViewerTarget: Identifiable {
    let index: Int
    let size: CGSize
    var id: Int { index }

    /// Abre en `index` con la hoja del tamaño de la ventana de CAOBA, menos un margen.
    /// Se mide al abrir: si luego agrandas la ventana, la próxima vez sale más grande.
    init(index: Int) {
        self.index = index
        let window = NSApp.mainWindow?.contentLayoutRect.size ?? CGSize(width: 1100, height: 760)
        size = CGSize(width: max(700, window.width - Self.margin), height: max(500, window.height - Self.margin))
    }

    static let margin: CGFloat = 40
}

/// Visor de las fotos de la lista: la foto original lo más grande posible, Anterior y Siguiente
/// para recorrer toda la lista (también las desmarcadas) y la casilla para quitarla o ponerla
/// en la selección sin volver a la lista. Teclado: ← →, espacio y Esc.
struct PhotoViewerSheet: View {
    @Environment(AppState.self) private var appState
    @Environment(\.dismiss) private var dismiss
    let size: CGSize
    @State private var index: Int
    @State private var image: CGImage?

    /// Lado de la versión rápida que se enseña mientras carga la original.
    private static let quickPixelSize = 1600

    init(target: PhotoViewerTarget) {
        size = target.size
        _index = State(initialValue: target.index)
    }

    private var files: [ScannedFile] { appState.files }
    private var file: ScannedFile? { files.indices.contains(index) ? files[index] : nil }

    var body: some View {
        VStack(spacing: 10) {
            CGImageView(image: image)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            bottomBar
        }
        .padding()
        .frame(width: size.width, height: size.height)
        // Al cambiar de foto se cancela la carga anterior (si aún no había acabado) y empieza la nueva.
        .task(id: file?.url) { await load() }
    }

    private var bottomBar: some View {
        HStack(spacing: 12) {
            Button { index -= 1 } label: { Label("Anterior", systemImage: "chevron.left") }
                .keyboardShortcut(.leftArrow, modifiers: [])
                .disabled(index <= 0)
            Button { index += 1 } label: { Label("Siguiente", systemImage: "chevron.right") }
                .keyboardShortcut(.rightArrow, modifiers: [])
                .disabled(index >= files.count - 1)
            if let file {
                Toggle("Incluida en la selección", isOn: Binding(
                    get: { !appState.excludedNames.contains(file.name) },
                    set: { _ in appState.toggle(file) }
                ))
                .toggleStyle(.checkbox)
                .help("Marca o desmarca la foto, igual que la casilla de su fila (espacio)")
                // El espacio marca o desmarca aunque el foco no esté en la casilla.
                Button("") { appState.toggle(file) }
                    .keyboardShortcut(.space, modifiers: [])
                    .hidden()
                    .frame(width: 0)
            }
            Spacer()
            if let file {
                Text(file.name).font(.callout).lineLimit(1).truncationMode(.middle)
                Text("\(index + 1) de \(files.count)").font(.callout.monospacedDigit()).foregroundStyle(.secondary)
            }
            Button("Cerrar") { dismiss() }.keyboardShortcut(.cancelAction)
        }
    }

    /// Primero la versión rápida (para que al pasar de foto no se quede en blanco)
    /// y luego la original a su resolución real, con la orientación EXIF aplicada.
    private func load() async {
        guard let url = file?.url else { image = nil; return }
        let quickSize = Self.quickPixelSize
        let quick = await Task.detached { ThumbnailProvider.makeThumbnail(url: url, maxPixelSize: quickSize) }.value
        guard !Task.isCancelled else { return }
        image = quick
        let original = await Task.detached { ThumbnailProvider.makeThumbnail(url: url, maxPixelSize: Int(Int32.max)) }.value
        guard !Task.isCancelled, let original else { return }
        image = original
    }
}
