import SwiftUI
import CaobaCore

/// Dibuja la plantilla como rectángulos, opcionalmente con las fotos de cada
/// celda recortadas según su punto de foco. Sirve para el selector, la
/// secuencia y el editor de enfoque.
struct TemplateView: View {
    let template: CollageTemplate
    var files: [URL] = []
    var focusPoints: [CGPoint?] = []
    var gap: CGFloat = 2
    var highlightIndex: Int? = nil
    /// Si se pasa, cada celda permite arrastrar su foto para mover el foco.
    var onFocusChange: ((Int, CGPoint) -> Void)? = nil

    var body: some View {
        GeometryReader { geo in
            let size = geo.size
            ZStack(alignment: .topLeading) {
                ForEach(Array(template.cells.enumerated()), id: \.offset) { index, cell in
                    let rect = CGRect(x: cell.x * size.width + gap / 2, y: cell.y * size.height + gap / 2,
                                      width: max(1, cell.w * size.width - gap), height: max(1, cell.h * size.height - gap))
                    cellView(index: index, rect: rect)
                        .frame(width: rect.width, height: rect.height)
                        .offset(x: rect.minX, y: rect.minY)
                }
            }
        }
        .aspectRatio(template.aspectRatio, contentMode: .fit)
    }

    @ViewBuilder
    private func cellView(index: Int, rect: CGRect) -> some View {
        let url = files.indices.contains(index) ? files[index] : nil
        let focus = focusPoints.indices.contains(index) ? (focusPoints[index] ?? CGPoint(x: 0.5, y: 0.5)) : CGPoint(x: 0.5, y: 0.5)
        ZStack(alignment: .topLeading) {
            Rectangle().fill(template.overlap ? Color.white.opacity(0.9) : Color.secondary.opacity(0.25))
            if let url {
                CellPhotoView(url: url, focus: focus, size: rect.size, onFocusChange: onFocusChange.map { handler in { handler(index, $0) } })
            }
            if highlightIndex == index {
                Rectangle().strokeBorder(Color.accentColor, lineWidth: 2)
            }
        }
        .clipped()
        .shadow(color: template.overlap ? .black.opacity(0.25) : .clear, radius: template.overlap ? 3 : 0, x: 1, y: 1)
    }
}

/// Foto recortada "cover" dentro de una celda con el foco en `focus` (0-1).
/// Si `onFocusChange` existe, arrastrar mueve el encuadre.
struct CellPhotoView: View {
    @Environment(AppState.self) private var appState
    let url: URL
    let focus: CGPoint
    let size: CGSize
    /// Ampliación extra sobre el encuadre "cover" (1 = sin zoom).
    var zoom: Double = 1
    var onFocusChange: ((CGPoint) -> Void)?

    @State private var image: CGImage?
    @State private var dragStartFocus: CGPoint?

    var body: some View {
        // La imagen escalada desborda la celda: se recorta y, además, el área que
        // responde a clics y arrastres se limita al recuadro con `contentShape`,
        // porque `clipped` solo recorta el dibujo, no la zona interactiva.
        Group {
            if let image {
                let imageSize = CGSize(width: image.width, height: image.height)
                let scale = max(size.width / imageSize.width, size.height / imageSize.height) * max(1, zoom)
                let scaled = CGSize(width: imageSize.width * scale, height: imageSize.height * scale)
                let offset = Self.offset(for: focus, scaled: scaled, cell: size)
                Image(decorative: image, scale: 1)
                    .resizable()
                    .frame(width: scaled.width, height: scaled.height)
                    .offset(x: offset.x, y: offset.y)
                    .allowsHitTesting(false)
            } else {
                Color.secondary.opacity(0.2)
            }
        }
        .frame(width: size.width, height: size.height, alignment: .topLeading)
        .clipped()
        .contentShape(Rectangle())
        .gesture(onFocusChange == nil ? nil : dragGesture())
        .task(id: url) {
            image = await appState.thumbnails.thumbnail(for: url, maxPixelSize: max(256, Int(max(size.width, size.height) * 2)))
        }
    }

    /// Tamaño de la imagen escalada con el zoom actual (para convertir el arrastre en foco).
    private var scaledSize: CGSize? {
        guard let image else { return nil }
        let imageSize = CGSize(width: image.width, height: image.height)
        let scale = max(size.width / imageSize.width, size.height / imageSize.height) * max(1, zoom)
        return CGSize(width: imageSize.width * scale, height: imageSize.height * scale)
    }

    /// Desplazamiento de la imagen escalada para que el punto de foco quede
    /// centrado en la celda, sin dejar huecos.
    static func offset(for focus: CGPoint, scaled: CGSize, cell: CGSize) -> CGPoint {
        let x = min(0, max(cell.width - scaled.width, cell.width / 2 - focus.x * scaled.width))
        let y = min(0, max(cell.height - scaled.height, cell.height / 2 - focus.y * scaled.height))
        return CGPoint(x: x, y: y)
    }

    private func dragGesture() -> some Gesture {
        DragGesture(minimumDistance: 1)
            .onChanged { value in
                guard let onFocusChange, let scaled = scaledSize else { return }
                if dragStartFocus == nil { dragStartFocus = focus }
                guard let start = dragStartFocus else { return }
                // Arrastrar la foto a la derecha significa mirar más a la izquierda.
                let fx = scaled.width > size.width ? start.x - value.translation.width / scaled.width : 0.5
                let fy = scaled.height > size.height ? start.y - value.translation.height / scaled.height : 0.5
                onFocusChange(CGPoint(x: min(1, max(0, fx)), y: min(1, max(0, fy))))
            }
            .onEnded { _ in dragStartFocus = nil }
    }
}

/// Rejilla de plantillas para elegir, con filtros de fotos y proporción.
struct TemplatePicker: View {
    let templates: [CollageTemplate]
    var selected: Set<String> = []
    let onPick: (CollageTemplate) -> Void

    private let columns = [GridItem(.adaptive(minimum: 96), spacing: 10)]

    var body: some View {
        ScrollView {
            LazyVGrid(columns: columns, spacing: 10) {
                ForEach(templates) { template in
                    VStack(spacing: 4) {
                        TemplateView(template: template)
                            .frame(width: 90, height: 90)
                            .overlay(RoundedRectangle(cornerRadius: 4).strokeBorder(selected.contains(template.id) ? Color.accentColor : .clear, lineWidth: 2))
                        Text("\(template.photos) · \(template.aspectLabel)").font(.caption2).foregroundStyle(.secondary)
                    }
                    .contentShape(Rectangle())
                    .onTapGesture { onPick(template) }
                    // La tarjeta es pequeña: el uso de la proporción va en el tooltip.
                    .help(Text(template.name) + Text(" · ") + AspectUsage.text(for: template.aspectLabel))
                }
            }
            .padding(8)
        }
    }
}

/// Filtros comunes de plantillas.
struct TemplateFilters: View {
    @Binding var photos: Int?
    @Binding var aspect: String?

    var body: some View {
        // En dos filas: con el texto de uso ("9:16 · Reels, Shorts…") no caben las dos en una.
        VStack(alignment: .leading, spacing: 8) {
            LabeledRow("Fotos") {
                Picker("", selection: $photos) {
                    Text("Todas").tag(Int?.none)
                    ForEach(1...9, id: \.self) { Text("\($0)").tag(Int?.some($0)) }
                }
                .fixedSize()
                .labelsHidden()
            }
            LabeledRow("Proporción") {
                Picker("", selection: $aspect) {
                    Text("Todas").tag(String?.none)
                    ForEach(CollageTemplates.aspectLabels, id: \.self) { AspectUsage.text(for: $0).tag(String?.some($0)) }
                }
                .frame(maxWidth: 320, alignment: .leading)
                .labelsHidden()
            }
        }
    }
}
