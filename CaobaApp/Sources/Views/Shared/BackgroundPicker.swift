import SwiftUI
import AppKit
import CaobaCore

/// Fondo de collage y contact sheet: Blanco, Negro, Gris o «Personalizado», que enseña al
/// lado el selector de color de macOS (sin transparencia). El texto y el borde del resultado
/// se ajustan solos a lo claro u oscuro que sea el fondo.
struct BackgroundPicker: View {
    @Binding var selection: CanvasColor

    /// Opciones del desplegable; el color propio va aparte, en el selector de color.
    private enum Choice: Hashable { case white, black, gray, custom }

    private var choice: Binding<Choice> {
        Binding(get: {
            switch selection {
            case .preset(.white): return .white
            case .preset(.black): return .black
            case .preset(.gray): return .gray
            case .custom: return .custom
            }
        }, set: { new in
            switch new {
            case .white: selection = .white
            case .black: selection = .black
            case .gray: selection = .gray
            // Al pasar a «Personalizado» se parte del color que hubiera, para no dar un salto.
            case .custom: if case .preset(let p) = selection { selection = .custom(Self.rgb(p.fill)) }
            }
        })
    }

    /// El color del selector, en sRGB (el mismo espacio en que se dibuja el fondo).
    private var color: Binding<Color> {
        Binding(get: {
            guard case .custom(let c) = selection else { return .white }
            return Color(.sRGB, red: c.red, green: c.green, blue: c.blue)
        }, set: { new in
            guard let c = NSColor(new).usingColorSpace(.sRGB) else { return }
            selection = .custom(RGBColor(red: Double(c.redComponent), green: Double(c.greenComponent), blue: Double(c.blueComponent)))
        })
    }

    var body: some View {
        HStack(spacing: 8) {
            Picker("", selection: choice) {
                Text("Blanco").tag(Choice.white)
                Text("Negro").tag(Choice.black)
                Text("Gris").tag(Choice.gray)
                Text("Personalizado").tag(Choice.custom)
            }
            .labelsHidden()
            .fixedSize()
            if case .custom = selection {
                ColorPicker("", selection: color, supportsOpacity: false).labelsHidden()
            }
        }
    }

    /// Componentes sRGB de un color de los de siempre.
    private static func rgb(_ color: CGColor) -> CaobaCore.RGBColor {
        let c = color.converted(to: CGColorSpace(name: CGColorSpace.sRGB)!, intent: .defaultIntent, options: nil)?.components ?? [1, 1, 1]
        return RGBColor(red: Double(c[0]), green: Double(c[min(1, c.count - 1)]), blue: Double(c[min(2, c.count - 1)]))
    }
}
