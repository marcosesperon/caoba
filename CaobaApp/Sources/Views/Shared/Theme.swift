import SwiftUI

/// Lo poco que conservamos del diseño Nothing: Doto en títulos y el acento rojo
/// (que viene del catálogo de assets como AccentColor).
extension Font {
    /// Título de sección en Doto. Si la fuente no cargase, cae a la del sistema.
    static func caobaTitle(_ size: CGFloat = 22) -> Font {
        .custom("Doto", size: size).weight(.bold)
    }
}

/// Título de módulo con la tipografía de la marca.
struct ModuleTitle: View {
    let title: LocalizedStringKey
    var body: some View {
        Text(title)
            .font(.caobaTitle())
            .textCase(.uppercase)
            .padding(.bottom, 4)
    }
}

/// Estilo de bloque de toda la app: fondo tenue, borde fino y esquinas redondeadas.
/// Sirve para que cada grupo de controles se vea como una pieza y la ventana no
/// parezca un montón de cosas sueltas.
struct CaobaPanel: ViewModifier {
    var padding: CGFloat = 10
    /// Color del fondo; las barras lo cambian para resaltar (p. ej. al soltar una carpeta).
    var fill: Color = Color(nsColor: .controlBackgroundColor)
    /// Color del borde; por defecto el separador del sistema (se adapta a claro y oscuro).
    var border: Color = Color(nsColor: .separatorColor)
    var borderWidth: CGFloat = 1

    func body(content: Content) -> some View {
        content
            .padding(padding)
            .background(fill, in: RoundedRectangle(cornerRadius: 8))
            .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(border, lineWidth: borderWidth))
            .clipShape(RoundedRectangle(cornerRadius: 8))
    }
}

extension View {
    /// Mete la vista en un bloque con el estilo común (ver `CaobaPanel`).
    func caobaPanel(padding: CGFloat = 10, fill: Color = Color(nsColor: .controlBackgroundColor),
                    border: Color = Color(nsColor: .separatorColor), borderWidth: CGFloat = 1) -> some View {
        modifier(CaobaPanel(padding: padding, fill: fill, border: border, borderWidth: borderWidth))
    }

    /// Bloque común para las barras donde se suelta algo (carpeta, foto): al arrastrar
    /// encima se tiñe de rojo y el borde se engorda, para que se vea que se puede soltar.
    /// Con `highlighted` (falta elegir la carpeta) lleva el borde rojo aunque no se arrastre nada.
    func caobaDropPanel(isTargeted: Bool, highlighted: Bool = false) -> some View {
        caobaPanel(fill: isTargeted ? Color.accentColor.opacity(0.15) : Color(nsColor: .controlBackgroundColor),
                   border: isTargeted || highlighted ? Color.accentColor : Color(nsColor: .separatorColor),
                   borderWidth: isTargeted || highlighted ? 2 : 1)
    }
}

/// Fondo rayado en diagonal de un color: base de las marcas de abajo.
struct Stripes: View {
    let color: Color
    var fillOpacity = 0.18
    var strokeOpacity = 0.45

    var body: some View {
        Canvas { context, size in
            context.fill(Path(CGRect(origin: .zero, size: size)), with: .color(color.opacity(fillOpacity)))
            var stripes = Path()
            var x: CGFloat = -size.height
            while x < size.width {
                stripes.move(to: CGPoint(x: x, y: size.height))
                stripes.addLine(to: CGPoint(x: x + size.height, y: 0))
                x += 10
            }
            context.stroke(stripes, with: .color(color.opacity(strokeOpacity)), lineWidth: 3)
        }
    }
}

/// Fondo rojo rayado de lo que no se encuentra (pistas, portada, créditos del timeline).
struct MissingStripes: View {
    var body: some View { Stripes(color: .red) }
}

/// Rayas oscuras del tramo de una pista que no suena (ya ha entrado otra). No rojas,
/// para no confundirlo con un fichero que no se encuentra.
struct SilentStripes: View {
    var body: some View { Stripes(color: .black, fillOpacity: 0.3, strokeOpacity: 0.35) }
}

/// Bloque de opciones con cabecera: el título encima y los controles en un bloque.
struct OptionGroup<Content: View>: View {
    let title: LocalizedStringKey
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title).font(.headline).padding(.leading, 4)
            VStack(alignment: .leading, spacing: 10) { content }
                .frame(maxWidth: .infinity, alignment: .leading)
                .caobaPanel()
        }
    }
}

/// Etiqueta, deslizador y valor en una fila, con separación y la etiqueta en
/// una columna de ancho fijo para que los sliders queden alineados.
struct LabeledSlider<Display: View>: View {
    let title: LocalizedStringKey
    @Binding var value: Double
    let range: ClosedRange<Double>
    let step: Double
    @ViewBuilder let display: Display

    init(title: LocalizedStringKey, value: Binding<Double>, in range: ClosedRange<Double>, step: Double, @ViewBuilder display: () -> Display) {
        self.title = title
        self._value = value
        self.range = range
        self.step = step
        self.display = display()
    }

    var body: some View {
        HStack(spacing: 12) {
            Text(title).frame(width: 130, alignment: .leading)
            Slider(value: $value, in: range, step: step)
            display.monospacedDigit().frame(width: 56, alignment: .trailing)
        }
    }
}

/// Deslizador para columnas estrechas (inspectores): la etiqueta arriba y, debajo,
/// el deslizador, el valor y, si se pasa `onReset`, el botón de volver al valor global.
/// En una columna de 300 puntos la fila de `LabeledSlider` dejaría el deslizador en nada.
struct StackedSlider<Display: View>: View {
    let title: LocalizedStringKey
    @Binding var value: Double
    let range: ClosedRange<Double>
    let step: Double
    /// Acción del botón «volver al valor global»; `nil` = no se enseña.
    var onReset: (() -> Void)?
    @ViewBuilder let display: Display

    init(title: LocalizedStringKey, value: Binding<Double>, in range: ClosedRange<Double>, step: Double,
         onReset: (() -> Void)? = nil, @ViewBuilder display: () -> Display) {
        self.title = title
        self._value = value
        self.range = range
        self.step = step
        self.onReset = onReset
        self.display = display()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title).foregroundStyle(.secondary)
            HStack(spacing: 8) {
                Slider(value: $value, in: range, step: step)
                display.monospacedDigit().frame(width: 52, alignment: .trailing)
                if let onReset {
                    Button(action: onReset) { Image(systemName: "arrow.uturn.backward") }
                        .buttonStyle(.borderless).help("Volver al valor global")
                }
            }
        }
    }
}

/// Etiqueta encima de su control, para columnas estrechas (inspectores), donde la
/// columna fija de `LabeledRow` no cabe.
struct StackedRow<Content: View>: View {
    let title: LocalizedStringKey
    @ViewBuilder let content: Content

    init(_ title: LocalizedStringKey, @ViewBuilder content: () -> Content) {
        self.title = title
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title).foregroundStyle(.secondary)
            content
        }
    }
}

/// Etiqueta y control en una fila, con la etiqueta en la misma columna fija
/// que usan los deslizadores, para que todos los controles empiecen alineados.
struct LabeledRow<Content: View>: View {
    let title: LocalizedStringKey
    @ViewBuilder let content: Content

    init(_ title: LocalizedStringKey, @ViewBuilder content: () -> Content) {
        self.title = title
        self.content = content()
    }

    var body: some View {
        HStack(spacing: 12) {
            Text(title).frame(width: 130, alignment: .leading)
            content
            Spacer(minLength: 0)
        }
    }
}
