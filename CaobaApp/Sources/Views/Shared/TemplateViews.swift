import SwiftUI
import CaobaCore

/// Dibuja la plantilla como rectángulos (y círculos), opcionalmente con las fotos de
/// cada celda recortadas según su punto de foco. Sirve para el selector, la
/// secuencia y el editor de enfoque.
struct TemplateView: View {
    let template: CollageTemplate
    var files: [URL] = []
    var focusPoints: [CGPoint?] = []
    var gap: CGFloat = 2
    var highlightIndex: Int? = nil
    /// Si se pasa, cada celda permite arrastrar su foto para mover el foco.
    var onFocusChange: ((Int, CGPoint) -> Void)? = nil
    /// Color del aro de las celdas redondas: el de lo que hay detrás (el resultado usa el del fondo del collage).
    var ringColor = Color(nsColor: .controlBackgroundColor)

    var body: some View {
        GeometryReader { geo in
            let size = geo.size
            ZStack(alignment: .topLeading) {
                ForEach(Array(template.cells.enumerated()), id: \.offset) { index, cell in
                    let full = CGRect(x: cell.x * size.width + gap / 2, y: cell.y * size.height + gap / 2,
                                      width: max(1, cell.w * size.width - gap), height: max(1, cell.h * size.height - gap))
                    // Pieza en polígono: encogida para dejar la separación; la foto va en su caja y se recorta con su forma.
                    let polygon = cell.polygon.map { pts in
                        CollageRenderer.insetPolygon(pts.map { CGPoint(x: $0.x * size.width, y: $0.y * size.height) },
                                                     offsets: Array(repeating: Double(gap) / 2, count: pts.count))
                    }
                    // Círculo perfecto: el cuadrado centrado en la celda, con un aro que lo separa de lo de debajo.
                    let rect = polygon.map(CollageRenderer.boundingBox) ?? (cell.isCircle ? CollageRenderer.squareInside(full) : full)
                    if cell.isCircle {
                        let ring = max(1.5, gap)
                        Circle().fill(ringColor)
                            .frame(width: rect.width + 2 * ring, height: rect.height + 2 * ring)
                            .offset(x: rect.minX - ring, y: rect.minY - ring)
                    }
                    // Girada alrededor de su centro, como en el resultado (el arrastre del encuadre
                    // se pasa a los ejes de la foto en `CellPhotoView`).
                    cellView(index: index, rect: rect, isCircle: cell.isCircle, rotation: cell.angle)
                        .frame(width: rect.width, height: rect.height)
                        .clipShape(PolygonShape(points: polygon?.map { CGPoint(x: $0.x - rect.minX, y: $0.y - rect.minY) }))
                        .rotationEffect(.degrees(cell.angle))
                        .offset(x: rect.minX, y: rect.minY)
                }
            }
        }
        .aspectRatio(template.aspectRatio, contentMode: .fit)
    }

    @ViewBuilder
    private func cellView(index: Int, rect: CGRect, isCircle: Bool, rotation: Double = 0) -> some View {
        let url = files.indices.contains(index) ? files[index] : nil
        let focus = focusPoints.indices.contains(index) ? (focusPoints[index] ?? CGPoint(x: 0.5, y: 0.5)) : CGPoint(x: 0.5, y: 0.5)
        ZStack(alignment: .topLeading) {
            Rectangle().fill(template.overlap ? Color.white.opacity(0.9) : Color.secondary.opacity(0.25))
            if let url {
                CellPhotoView(url: url, focus: focus, size: rect.size, onFocusChange: onFocusChange.map { handler in { handler(index, $0) } },
                              rotation: rotation)
            }
            if highlightIndex == index {
                if isCircle { Circle().strokeBorder(Color.accentColor, lineWidth: 2) } else { Rectangle().strokeBorder(Color.accentColor, lineWidth: 2) }
            }
        }
        .clipShape(isCircle ? AnyShape(Circle()) : AnyShape(Rectangle()))
        .shadow(color: template.overlap ? .black.opacity(0.25) : .clear, radius: template.overlap ? 3 : 0, x: 1, y: 1)
    }
}

/// «N elegidas» y, si hay plantillas marcadas que los filtros esconden, cuántas son y un botón
/// para desmarcarlas. Componer usa todas las marcadas, también las que no se ven: así no hay sorpresas.
struct HiddenSelectionNotice: View {
    @Binding var selection: Set<String>
    let visible: [CollageTemplate]

    private var hidden: Set<String> { selection.subtracting(visible.map(\.id)) }

    var body: some View {
        HStack(spacing: 6) {
            Text("\(selection.count) elegidas").foregroundStyle(.secondary)
            if !hidden.isEmpty {
                Text("· \(hidden.count) ocultas por los filtros").foregroundStyle(Color.accentColor)
                    .help("Están marcadas pero no se ven con los filtros actuales; Componer también las usa")
                Button("Desmarcar las ocultas") { selection.subtract(hidden) }
                    .controlSize(.small)
            }
        }
        .font(.caption)
    }
}

/// Forma de una pieza en polígono (puntos relativos a su caja); sin puntos, el rectángulo entero.
struct PolygonShape: Shape {
    let points: [CGPoint]?
    func path(in rect: CGRect) -> Path {
        guard let points, points.count >= 3 else { return Path(rect) }
        var path = Path()
        path.addLines(points)
        path.closeSubpath()
        return path
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
    /// Giro de la celda en grados: el arrastre se pasa a los ejes de la foto girada.
    var rotation: Double = 0

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
        // Medido en la ventana (sin giros) y girado aquí al revés que la celda, para que la foto
        // se mueva en la dirección en que se arrastra aunque la celda esté girada.
        DragGesture(minimumDistance: 1, coordinateSpace: .global)
            .onChanged { value in
                guard let onFocusChange, let scaled = scaledSize else { return }
                if dragStartFocus == nil { dragStartFocus = focus }
                guard let start = dragStartFocus else { return }
                let r = -rotation * .pi / 180
                let t = CGSize(width: value.translation.width * cos(r) - value.translation.height * sin(r),
                               height: value.translation.width * sin(r) + value.translation.height * cos(r))
                // Arrastrar la foto a la derecha significa mirar más a la izquierda.
                let fx = scaled.width > size.width ? start.x - t.width / scaled.width : 0.5
                let fy = scaled.height > size.height ? start.y - t.height / scaled.height : 0.5
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
    @Binding var filters: TemplateFilterState
    /// Si se ofrecen las superpuestas (solo en el Slideshow); el selector «Tipo» sale siempre,
    /// porque las redondas van en todas partes.
    var showType = false

    var body: some View {
        // En dos filas: con el texto de uso ("9:16 · Reels, Shorts…") no caben las dos en una.
        VStack(alignment: .leading, spacing: 8) {
            LabeledRow("Fotos") {
                Picker("", selection: $filters.photos) {
                    Text("Todas").tag(Int?.none)
                    ForEach(1...9, id: \.self) { Text("\($0)").tag(Int?.some($0)) }
                }
                .fixedSize()
                .labelsHidden()
            }
            LabeledRow("Proporción") {
                Picker("", selection: $filters.aspect) {
                    Text("Todas").tag(String?.none)
                    ForEach(CollageTemplates.aspectLabels, id: \.self) { AspectUsage.text(for: $0).tag(String?.some($0)) }
                }
                .frame(maxWidth: 320, alignment: .leading)
                .labelsHidden()
            }
            LabeledRow("Tipo") {
                Picker("", selection: $filters.type) {
                    Text("Todas").tag(CollageTemplates.TemplateType?.none)
                    Text("Básicas").tag(CollageTemplates.TemplateType?.some(.basic))
                    if showType { Text("Superpuestas").tag(CollageTemplates.TemplateType?.some(.overlap)) }
                    Text("Redondas").tag(CollageTemplates.TemplateType?.some(.round))
                    Text("Giradas").tag(CollageTemplates.TemplateType?.some(.rotated))
                    Text("Diagonales").tag(CollageTemplates.TemplateType?.some(.polygon))
                }
                // Desplegable, como «Fotos» y «Proporción»: con seis tipos los botones no caben en la hoja.
                .frame(maxWidth: 220, alignment: .leading)
                .labelsHidden()
            }
        }
    }
}
