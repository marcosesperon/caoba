import SwiftUI
import CaobaCore

/// Tira del bloque de abajo de Collage: toda la secuencia (o el reparto de «Aleatorias», o el
/// carrusel) dibujada con el motor real y las opciones de salida. Hace también de selección:
/// clic para editar, arrastrar para cambiar el orden y clic derecho para el menú.
/// Cada collage se dibuja por separado, así que al tocar uno solo se vuelve a dibujar ese.
struct CollagePreview<Menu: View>: View {
    /// Collages en orden; en el carrusel, los tramos.
    let rows: [CollageRow]
    let options: CollageOptions
    /// Si llega, `rows` son tramos de carrusel y se enseña la tira cortada en diapositivas.
    var carouselFormat: CarouselFormat?
    /// Qué decir cuando no hay nada que enseñar.
    let emptyMessage: LocalizedStringKey
    /// Clic en un collage (o tramo): abre su editor.
    let onSelect: (Int) -> Void
    /// Se ha soltado el collage `moved` encima de `target`.
    let onMove: (_ moved: UUID, _ target: UUID) -> Void
    /// Menú del clic derecho de cada collage.
    @ViewBuilder let menu: (Int) -> Menu

    /// Lado mayor de cada collage dibujado: de sobra para una tira de unos cientos de puntos.
    private static var collageSide: Int { 900 }
    /// Lo mismo por diapositiva en el carrusel.
    private static var slideSide: Int { 500 }

    var body: some View {
        if rows.isEmpty {
            Text(emptyMessage)
                .font(.callout).foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            // La altura disponible manda: cada collage se ajusta a ella y la tira se desplaza en horizontal.
            GeometryReader { geo in
                let height = max(60, geo.size.height - 24)
                ScrollView(.horizontal) {
                    if let carouselFormat {
                        carouselStrip(format: carouselFormat, height: height)
                    } else {
                        collageStrip(height: height)
                    }
                }
            }
        }
    }

    // MARK: Collages sueltos

    private func collageStrip(height: CGFloat) -> some View {
        LazyHStack(alignment: .top, spacing: 14) {
            ForEach(Array(rows.enumerated()), id: \.element.id) { index, row in
                VStack(spacing: 4) {
                    CollageResultView(row: row, options: options, framed: false, side: Self.collageSide)
                        .frame(width: height * aspect(of: row), height: height)
                        .shadow(color: .black.opacity(0.2), radius: 2, y: 1)
                    Text("\(index + 1)").font(.caption2.monospacedDigit()).foregroundStyle(.secondary)
                }
                .modifier(itemActions(index: index, row: row))
            }
        }
        .padding(.vertical, 4).padding(.horizontal, 2)
    }

    /// Ancho entre alto del collage tal como sale, título incluido.
    private func aspect(of row: CollageRow) -> CGFloat {
        let base = row.template.canvasSize(longestSide: 1000)
        let title = CollageRenderer.titleHeight(for: base, title: options.title)
        return CGFloat(base.width) / (CGFloat(base.height) + CGFloat(title))
    }

    // MARK: Carrusel

    /// El carrusel se dibuja de una pieza (para que los cortes sean exactos) y encima va una
    /// zona invisible por tramo que recoge el clic, el arrastre y el menú.
    @ViewBuilder
    private func carouselStrip(format: CarouselFormat, height: CGFloat) -> some View {
        if let combined = Carousel.combine(rows, format: format) {
            let total = combined.template.slides ?? 1
            let slideWidth = height * CGFloat(format.aspect.width) / CGFloat(format.aspect.height)
            ZStack(alignment: .topLeading) {
                CollageResultView(row: combined, options: CarouselPreviewOptions.make(options, format: format, slides: total),
                                  framed: false, side: Self.slideSide * total)
                CarouselCuts(slides: total, slideWidth: slideWidth, height: height)
                HStack(spacing: 0) {
                    ForEach(Array(rows.enumerated()), id: \.element.id) { index, row in
                        Color.clear
                            .frame(width: slideWidth * CGFloat(row.template.slides ?? 1), height: height)
                            .modifier(itemActions(index: index, row: row))
                    }
                }
            }
            .frame(width: slideWidth * CGFloat(total), height: height)
            .padding(.vertical, 4)
        }
    }

    // MARK: Acciones

    private func itemActions(index: Int, row: CollageRow) -> SequenceItemActions<Menu> {
        SequenceItemActions(id: row.id, template: row.template, onSelect: { onSelect(index) }, onMove: onMove, menu: menu(index))
    }
}

/// Clic, arrastrar para reordenar y menú de un collage (o tramo) de la tira.
struct SequenceItemActions<Menu: View>: ViewModifier {
    let id: UUID
    let template: CollageTemplate
    let onSelect: () -> Void
    let onMove: (UUID, UUID) -> Void
    let menu: Menu

    func body(content: Content) -> some View {
        content
            .contentShape(Rectangle())
            .onTapGesture { onSelect() }
            .contextMenu { menu }
            .help("Clic para editar el encuadre; arrastra para cambiar el orden; clic derecho para más opciones")
            // Al arrastrar se ve la plantilla en pequeño (en el carrusel, la zona es transparente).
            .draggable(id.uuidString) { TemplateView(template: template).frame(height: 60) }
            .dropDestination(for: String.self) { items, _ in
                guard let moved = items.first.flatMap(UUID.init), moved != id else { return false }
                onMove(moved, id)
                return true
            }
    }
}

/// Mueve el elemento `moved` a la posición de `target` (antes o después según venga de delante o de detrás).
/// Vale para cualquier lista con `id`: collages de la secuencia, tramos del carrusel, pistas de música…
func moveItem<Item: Identifiable>(_ items: inout [Item], moved: Item.ID, onto target: Item.ID) {
    guard let from = items.firstIndex(where: { $0.id == moved }),
          let to = items.firstIndex(where: { $0.id == target }) else { return }
    items.move(fromOffsets: IndexSet(integer: from), toOffset: to > from ? to + 1 : to)
}

/// Opciones con las que de verdad sale el carrusel (cada diapositiva a 1080 px, sin título).
enum CarouselPreviewOptions {
    static func make(_ options: CollageOptions, format: CarouselFormat, slides: Int) -> CollageOptions {
        var o = options
        o.title = ""
        o.longestSide = max(Carousel.slideWidth * slides, format.slideSize.height)
        return o
    }
}

/// Líneas de corte y número de cada diapositiva sobre la tira del carrusel (no estorban al arrastre).
struct CarouselCuts: View {
    let slides: Int
    let slideWidth: CGFloat
    let height: CGFloat
    /// Número de la primera diapositiva (en el editor de un tramo, la que le toca en el carrusel).
    var firstNumber = 1

    var body: some View {
        ZStack(alignment: .topLeading) {
            ForEach(0..<slides, id: \.self) { i in
                if i > 0 {
                    Rectangle().fill(Color.accentColor).frame(width: 2, height: height)
                        .offset(x: slideWidth * CGFloat(i) - 1)
                }
                Text("\(firstNumber + i)").font(.caption2.monospacedDigit().bold()).foregroundStyle(.white)
                    .padding(.horizontal, 4).padding(.vertical, 1)
                    .background(.black.opacity(0.55), in: RoundedRectangle(cornerRadius: 3))
                    .offset(x: slideWidth * CGFloat(i) + 4, y: 4)
            }
        }
        .allowsHitTesting(false)
    }
}

/// Bloque de abajo de Collage: título y cabecera (botones y recuento) y, debajo, la tira.
struct SequenceBlock<Header: View, Content: View>: View {
    let title: LocalizedStringKey
    @ViewBuilder var header: Header
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Text(title).font(.headline).padding(.trailing, 6)
                header
            }
            content.frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .caobaPanel()
    }
}

/// Reparto vertical con un divisor que se arrastra: arriba lo que sobre y abajo un bloque
/// de alto `bottomHeight`, que se guarda para la próxima vez. El divisor nativo (`VSplitView`)
/// no respeta la altura inicial, por eso va hecho a mano.
struct BottomSplit<Top: View, Bottom: View>: View {
    @Binding var bottomHeight: Double
    var minTop: CGFloat = 240
    var minBottom: CGFloat = 160
    @ViewBuilder var top: Top
    @ViewBuilder var bottom: Bottom

    /// Alto del bloque al empezar el arrastre.
    @State private var dragStart: Double?

    var body: some View {
        GeometryReader { geo in
            let maxBottom = max(minBottom, geo.size.height - minTop - 12)
            let height = min(max(CGFloat(bottomHeight), minBottom), maxBottom)
            VStack(spacing: 0) {
                top.frame(maxHeight: .infinity)
                handle(maxBottom: maxBottom)
                bottom.frame(height: height)
            }
        }
    }

    /// Franja de 12 pt con una rayita en medio; el cursor cambia al pasar por encima.
    private func handle(maxBottom: CGFloat) -> some View {
        ZStack {
            Color.clear
            Capsule().fill(Color.secondary.opacity(0.4)).frame(width: 40, height: 4)
        }
        .frame(height: 12)
        .contentShape(Rectangle())
        .onHover { inside in if inside { NSCursor.resizeUpDown.push() } else { NSCursor.pop() } }
        .gesture(DragGesture(minimumDistance: 1, coordinateSpace: .global)
            .onChanged { value in
                let start = dragStart ?? bottomHeight
                dragStart = start
                // Arrastrar hacia arriba agranda el bloque de abajo.
                bottomHeight = min(max(start - value.translation.height, Double(minBottom)), Double(maxBottom))
            }
            .onEnded { _ in dragStart = nil })
    }
}
