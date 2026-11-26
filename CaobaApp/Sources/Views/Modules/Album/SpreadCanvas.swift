import SwiftUI
import CaobaCore

/// De mm del pliego (origen arriba-izquierda del corte) a puntos de una vista y al revés, con el
/// pliego entero (sangrado incluido) encajado y centrado en `size`.
struct SpreadGeometry {
    let spec: AlbumSpec
    let size: CGSize

    var bleed: Double { spec.bleedMM }
    /// El pliego con su sangrado, en mm.
    var full: CGSize { CGSize(width: spec.spreadSize.width + bleed * 2, height: spec.spreadSize.height + bleed * 2) }
    var scale: Double { min(size.width / max(full.width, 1), size.height / max(full.height, 1)) }
    var origin: CGPoint { CGPoint(x: (size.width - full.width * scale) / 2, y: (size.height - full.height * scale) / 2) }

    func rect(_ r: CGRect) -> CGRect {
        CGRect(x: origin.x + (r.minX + bleed) * scale, y: origin.y + (r.minY + bleed) * scale,
               width: r.width * scale, height: r.height * scale)
    }

    func x(_ mm: Double) -> Double { origin.x + (mm + bleed) * scale }
    func y(_ mm: Double) -> Double { origin.y + (mm + bleed) * scale }
    /// Puntos de la vista → mm (para lo que se arrastra).
    func mm(_ points: Double) -> Double { points / max(scale, 0.0001) }

    var trim: CGRect { rect(CGRect(origin: .zero, size: spec.spreadSize)) }
    var bleedRect: CGRect { CGRect(x: origin.x, y: origin.y, width: full.width * scale, height: full.height * scale) }
}

/// Un pliego dibujado a escala: el sangrado por fuera, el corte, las fotos en sus casillas y,
/// si se piden, las guías (margen de seguridad discontinuo y franja del lomo sombreada).
/// Lo usan las miniaturas de la fila de pliegos; el pliego grande es `SpreadEditorCanvas`.
struct SpreadCanvas: View {
    let spec: AlbumSpec
    let layout: AlbumSpreadLayout
    let info: [String: AlbumPhotoInfo]
    /// Carpeta de las fotos (el origen de la ventana).
    let folder: URL?
    var showGuides = true
    /// Tamaño de las miniaturas que se cargan: más pequeño en la fila de pliegos.
    var thumbnailSize = 900
    /// En un pliego de una página, la que va pegada a la tapa.
    var glued: AlbumPageSide? = nil

    var body: some View {
        GeometryReader { geo in
            let g = SpreadGeometry(spec: spec, size: geo.size)
            ZStack(alignment: .topLeading) {
                SpreadBackground(geometry: g, showGuides: showGuides)
                ForEach(layout.drawRects(spec), id: \.cell.id) { entry in
                    let rect = g.rect(entry.rect)
                    AlbumCellImage(url: entry.cell.photo.flatMap { folder?.appendingPathComponent($0) },
                                   focus: Self.focus(of: entry.cell, info: info), zoom: entry.cell.scale,
                                   size: rect.size, maxPixelSize: thumbnailSize)
                        .frame(width: rect.width, height: rect.height)
                        .offset(x: rect.minX, y: rect.minY)
                }
                if showGuides { SpreadGuidesOverlay(geometry: g) }
                SpineLine(geometry: g)
                if let glued { GluedPageOverlay(geometry: g, side: glued, showsText: showGuides) }
            }
        }
    }

    /// Punto de encuadre de una casilla: el que se puso a mano o el del análisis (las caras).
    static func focus(of cell: AlbumCell, info: [String: AlbumPhotoInfo]) -> CGPoint {
        cell.focus ?? cell.photo.flatMap { info[$0]?.focus } ?? CGPoint(x: 0.5, y: 0.5)
    }
}

/// Fondo del pliego: el sangrado (se imprime pero se corta) y el blanco del corte.
struct SpreadBackground: View {
    let geometry: SpreadGeometry
    var showGuides = true

    var body: some View {
        let trim = geometry.trim
        let bleed = geometry.bleedRect
        ZStack(alignment: .topLeading) {
            Rectangle().fill(Color.orange.opacity(showGuides ? 0.18 : 0))
                .frame(width: bleed.width, height: bleed.height)
                .offset(x: bleed.minX, y: bleed.minY)
            Rectangle().fill(Color.white)
                .frame(width: trim.width, height: trim.height)
                .offset(x: trim.minX, y: trim.minY)
                .shadow(color: .black.opacity(showGuides ? 0.15 : 0.1), radius: showGuides ? 4 : 1)
        }
        .allowsHitTesting(false)
    }
}

/// Margen de seguridad (discontinuo) y franja del lomo (sombreada).
struct SpreadGuidesOverlay: View {
    let geometry: SpreadGeometry

    var body: some View {
        let spec = geometry.spec
        let strip = geometry.rect(spec.spineStrip)
        ZStack(alignment: .topLeading) {
            Rectangle().fill(Color.red.opacity(0.10))
                .frame(width: strip.width, height: strip.height)
                .offset(x: strip.minX, y: strip.minY)
            ForEach([AlbumPageSide.left, .right], id: \.self) { side in
                let content = geometry.rect(spec.pageContent(side))
                Rectangle().stroke(Color.accentColor.opacity(0.8), style: StrokeStyle(lineWidth: 1, dash: [5, 3]))
                    .frame(width: content.width, height: content.height)
                    .offset(x: content.minX, y: content.minY)
            }
        }
        .allowsHitTesting(false)
    }
}

/// La página que va pegada a la tapa en el primer y el último pliego: rayada y sin fotos.
struct GluedPageOverlay: View {
    let geometry: SpreadGeometry
    let side: AlbumPageSide
    var showsText = true

    var body: some View {
        let rect = geometry.rect(geometry.spec.pageRect(side))
        ZStack {
            Stripes(color: .gray, fillOpacity: 0.12, strokeOpacity: 0.5)
            if showsText {
                Label("Pegada a la tapa", systemImage: "book.closed")
                    .font(.caption)
                    .padding(.horizontal, 8).padding(.vertical, 4)
                    .background(.ultraThinMaterial, in: Capsule())
            }
        }
        .frame(width: rect.width, height: rect.height)
        .offset(x: rect.minX, y: rect.minY)
        .allowsHitTesting(false)
    }
}

/// El lomo, siempre: es donde se dobla.
struct SpineLine: View {
    let geometry: SpreadGeometry

    var body: some View {
        let spec = geometry.spec
        let trim = geometry.trim
        // En la portada el lomo tiene ancho: dos líneas; en un pliego, una.
        ZStack(alignment: .topLeading) {
            ForEach(Array(Set([spec.spineStart, spec.spineEnd])).sorted(), id: \.self) { x in
                Rectangle().fill(Color.black.opacity(0.25))
                    .frame(width: 1, height: trim.height)
                    .offset(x: geometry.x(x), y: trim.minY)
            }
        }
        .allowsHitTesting(false)
    }
}

/// Una foto recortada para su casilla, centrada en su punto de encuadre y con su ampliación.
struct AlbumCellImage: View {
    @Environment(AppState.self) private var appState
    let url: URL?
    let focus: CGPoint
    var zoom = 1.0
    let size: CGSize
    var maxPixelSize = 900

    @State private var image: CGImage?

    var body: some View {
        ZStack {
            Rectangle().fill(Color.gray.opacity(0.25))
            if let cropped {
                Image(decorative: cropped, scale: 1).resizable()
            } else if url == nil {
                Image(systemName: "photo").foregroundStyle(.tertiary)
            }
        }
        .clipped()
        .task(id: url) {
            guard let url else { image = nil; return }
            image = await appState.thumbnails.thumbnail(for: url, maxPixelSize: maxPixelSize)
        }
    }

    /// El trozo de la miniatura que entra en la casilla (la misma cuenta que en el reparto).
    private var cropped: CGImage? {
        guard let image, size.width > 0, size.height > 0 else { return nil }
        let region = AlbumAutoLayout.visibleRegion(photoAspect: Double(image.width) / Double(max(image.height, 1)),
                                                   cellAspect: size.width / size.height, focus: focus, zoom: zoom)
        let rect = CGRect(x: region.minX * Double(image.width), y: region.minY * Double(image.height),
                          width: region.width * Double(image.width), height: region.height * Double(image.height))
        return image.croppedTopLeft(rect)
    }
}
