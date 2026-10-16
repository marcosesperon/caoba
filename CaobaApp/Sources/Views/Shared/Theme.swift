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

/// Bloque de opciones con cabecera.
struct OptionGroup<Content: View>: View {
    let title: LocalizedStringKey
    @ViewBuilder var content: Content

    var body: some View {
        GroupBox(label: Text(title).font(.headline)) {
            VStack(alignment: .leading, spacing: 10) { content }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.vertical, 4)
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
