import SwiftUI
import CaobaCore

/// Miniatura cargada en segundo plano desde el proveedor compartido.
struct ThumbnailView: View {
    @Environment(AppState.self) private var appState
    let url: URL
    var maxPixelSize: Int = 160
    var displaySize: CGFloat = 40

    @State private var image: CGImage?

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 4).fill(.quaternary)
            if let image {
                Image(decorative: image, scale: 1)
                    .resizable()
                    .scaledToFit()
                    .clipShape(RoundedRectangle(cornerRadius: 4))
            } else {
                Image(systemName: "photo").foregroundStyle(.secondary)
            }
        }
        .frame(width: displaySize, height: displaySize)
        .task(id: url) {
            image = await appState.thumbnails.thumbnail(for: url, maxPixelSize: maxPixelSize)
        }
    }
}

/// Imagen grande a partir de un CGImage, encajada en su contenedor.
struct CGImageView: View {
    let image: CGImage?
    var body: some View {
        if let image {
            Image(decorative: image, scale: 1).resizable().scaledToFit()
        } else {
            ContentUnavailableView("Sin vista previa", systemImage: "photo")
        }
    }
}
