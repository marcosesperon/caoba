import Foundation
import CoreGraphics
import CoreText
import CoreImage

/// Dónde se coloca un texto sobre el vídeo (nueve posiciones).
public enum TextAnchor: String, Sendable, Codable, CaseIterable {
    case topLeft, top, topRight, left, center, right, bottomLeft, bottom, bottomRight

    var horizontal: Int { // 0 izquierda, 1 centro, 2 derecha
        switch self {
        case .topLeft, .left, .bottomLeft: return 0
        case .top, .center, .bottom: return 1
        case .topRight, .right, .bottomRight: return 2
        }
    }

    var vertical: Int { // 0 arriba, 1 centro, 2 abajo
        switch self {
        case .topLeft, .top, .topRight: return 0
        case .left, .center, .right: return 1
        case .bottomLeft, .bottom, .bottomRight: return 2
        }
    }
}

/// Qué hay detrás del texto para que se lea sobre cualquier foto.
public enum TextBackdrop: String, Sendable, Codable, CaseIterable {
    case none, shadow, band
}

/// Cómo entra (y sale, al revés) un texto.
public enum TextAnimation: String, Sendable, Codable, CaseIterable {
    case none, fade, slideUp, slideDown, slideLeft, slideRight, zoom, typewriter
    /// Solo en la app: se resuelve a una concreta al generar.
    case random
    /// Solo para la salida: la inversa de la entrada.
    case mirror

    /// Candidatas para «Aleatorio».
    public static let randomPool: [TextAnimation] = [.fade, .slideUp, .slideDown, .slideLeft, .slideRight, .zoom, .typewriter]
}

/// Estilo de un texto del vídeo.
public struct TextStyle: Sendable, Equatable, Codable {
    /// Familia tipográfica; `nil` = la del sistema.
    public var fontName: String?
    public var bold: Bool
    /// Tamaño de la primera línea en % del alto del vídeo; las siguientes van al 55 %.
    public var sizePercent: Double
    public var color: RGBColor
    public var anchor: TextAnchor
    public var backdrop: TextBackdrop
    /// Entrada: animación y lo que dura.
    public var animation: TextAnimation
    public var animationDuration: Double
    /// Salida: animación (`mirror` = la inversa de la entrada; `none` = el texto se queda) y lo que dura.
    public var exitAnimation: TextAnimation
    public var exitDuration: Double
    /// Segundos mostrándose entre entrada y salida; `nil` = hasta el final de la foto o la tarjeta.
    public var holdSeconds: Double?

    public init(fontName: String? = nil, bold: Bool = false, sizePercent: Double = 4, color: RGBColor = RGBColor(red: 1, green: 1, blue: 1),
                anchor: TextAnchor = .bottomLeft, backdrop: TextBackdrop = .shadow, animation: TextAnimation = .none, animationDuration: Double = 0.6,
                exitAnimation: TextAnimation = .mirror, exitDuration: Double = 0.6, holdSeconds: Double? = nil) {
        self.fontName = fontName
        self.bold = bold
        self.sizePercent = sizePercent
        self.color = color
        self.anchor = anchor
        self.backdrop = backdrop
        self.animation = animation
        self.animationDuration = animationDuration
        self.exitAnimation = exitAnimation
        self.exitDuration = exitDuration
        self.holdSeconds = holdSeconds
    }

    /// Animación de salida ya resuelta (sin `mirror`).
    public var resolvedExit: TextAnimation { exitAnimation == .mirror ? animation : exitAnimation }

    private enum CodingKeys: String, CodingKey { case fontName, bold, sizePercent, color, anchor, backdrop, animation, animationDuration, exitAnimation, exitDuration, holdSeconds }

    /// Los campos de animación pueden faltar en estilos guardados antes de existir.
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        fontName = try c.decodeIfPresent(String.self, forKey: .fontName)
        bold = try c.decodeIfPresent(Bool.self, forKey: .bold) ?? false
        sizePercent = try c.decodeIfPresent(Double.self, forKey: .sizePercent) ?? 4
        color = try c.decodeIfPresent(RGBColor.self, forKey: .color) ?? RGBColor(red: 1, green: 1, blue: 1)
        anchor = try c.decodeIfPresent(TextAnchor.self, forKey: .anchor) ?? .bottomLeft
        backdrop = try c.decodeIfPresent(TextBackdrop.self, forKey: .backdrop) ?? .shadow
        animation = try c.decodeIfPresent(TextAnimation.self, forKey: .animation) ?? .none
        animationDuration = try c.decodeIfPresent(Double.self, forKey: .animationDuration) ?? 0.6
        exitAnimation = try c.decodeIfPresent(TextAnimation.self, forKey: .exitAnimation) ?? .mirror
        exitDuration = try c.decodeIfPresent(Double.self, forKey: .exitDuration) ?? animationDuration
        holdSeconds = try c.decodeIfPresent(Double.self, forKey: .holdSeconds)
    }

    public static let title = TextStyle(fontName: "Doto", bold: true, sizePercent: 9, anchor: .center, backdrop: .shadow, animation: .fade)
    public static let caption = TextStyle(fontName: nil, bold: false, sizePercent: 3, anchor: .bottomLeft, backdrop: .band)
}

/// Punto de una animación de texto: `progress` 1 = texto asentado; menor, entrando o saliendo.
public struct TextPhase: Sendable, Equatable {
    public var progress: Double
    public var exiting: Bool

    /// Fase en el segundo `t` de un texto que dura `total`, con la entrada y la salida del estilo.
    /// `nil` si no se ve. `entry` y `exit` permiten saltarse una de las dos (un pie que continúa
    /// en el paso siguiente de un collage). Si no caben las dos, se acortan a partes iguales.
    public static func at(_ t: Double, total: Double, style: TextStyle, entry: Bool = true, exit: Bool = true) -> TextPhase? {
        guard t >= 0, t <= total else { return nil }
        var entryTime = (entry && style.animation != .none) ? max(0, style.animationDuration) : 0
        var exitTime = (exit && style.resolvedExit != .none) ? max(0, style.exitDuration) : 0
        if entryTime + exitTime > total {
            let scale = total / (entryTime + exitTime)
            entryTime *= scale
            exitTime *= scale
        }
        if entryTime > 0, t < entryTime { return TextPhase(progress: t / entryTime, exiting: false) }
        if exitTime > 0, t > total - exitTime { return TextPhase(progress: (total - t) / exitTime, exiting: true) }
        return TextPhase(progress: 1, exiting: false)
    }

    /// Compatibilidad: una sola animación y duración para entrada y salida.
    public static func at(_ t: Double, total: Double, animation: TextAnimation, duration: Double, entry: Bool = true, exit: Bool = true) -> TextPhase? {
        at(t, total: total, style: TextStyle(animation: animation, animationDuration: duration, exitAnimation: .mirror, exitDuration: duration), entry: entry, exit: exit)
    }

    /// Cuánto se ve en total un texto con `hold` segundos mostrándose (más entrada y salida).
    public static func totalDuration(style: TextStyle, hold: Double) -> Double {
        (style.animation != .none ? style.animationDuration : 0) + hold + (style.resolvedExit != .none ? style.exitDuration : 0)
    }
}

/// Texto que se superpone a una foto durante unos segundos, con la animación de su estilo.
public struct TextOverlay: Sendable, Equatable {
    public var lines: [String]
    public var style: TextStyle
    public var duration: Double
    /// Segundos del texto ya transcurridos antes de esta foto (cuando el título
    /// abarca varios pasos de un collage, cada paso lleva su desfase).
    public var offset: Double
    /// Segundos de espera desde que empieza la foto hasta que entra el texto
    /// (en una tarjeta, lo que dura su transición de entrada).
    public var delay: Double

    public init(lines: [String], style: TextStyle, duration: Double, offset: Double = 0, delay: Double = 0) {
        self.lines = lines.filter { !$0.isEmpty }
        self.style = style
        self.duration = duration
        self.offset = offset
        self.delay = delay
    }

    /// Fase de la animación en el segundo `local` desde que empieza la foto.
    public func phase(at local: Double) -> TextPhase? {
        TextPhase.at(local + offset - delay, total: duration, style: style)
    }

    /// Opacidad equivalente (para quien solo quiera un fundido).
    public func opacity(at local: Double) -> Double { phase(at: local)?.progress ?? 0 }
}

/// Capa de texto ya dibujada, con el rectángulo del bloque (origen abajo-izquierda) y cuántos caracteres tiene.
public struct TextLayer: Sendable {
    public var image: CGImage
    public var block: CGRect
    public var characters: Int
}

/// Dibuja textos con Core Text: una capa transparente del tamaño del vídeo o
/// una tarjeta con fondo de color.
public enum TextRenderer {
    /// Capa transparente con las líneas colocadas según el estilo; `nil` sin texto.
    public static func layer(lines: [String], style: TextStyle, canvas: PixelSize) -> CGImage? {
        render(lines: lines, style: style, canvas: canvas)?.image
    }

    /// Como `layer`, con el rectángulo del bloque. Con `visibleCharacters` dibuja solo los
    /// primeros caracteres (máquina de escribir) manteniendo la posición del bloque completo.
    public static func render(lines: [String], style: TextStyle, canvas: PixelSize, visibleCharacters: Int? = nil) -> TextLayer? {
        let clean = lines.filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
        guard !clean.isEmpty, let ctx = CGContext.rgba(width: canvas.width, height: canvas.height) else { return nil }
        let block = draw(lines: clean, style: style, canvas: canvas, visibleCharacters: visibleCharacters, in: ctx)
        guard let image = ctx.makeImage() else { return nil }
        return TextLayer(image: image, block: block, characters: clean.reduce(0) { $0 + $1.count })
    }

    /// Tarjeta de título: fondo de color y el texto centrado (o donde diga el estilo).
    public static func card(lines: [String], style: TextStyle, background: CGColor, canvas: PixelSize) throws -> CGImage {
        let ctx = try Drawing.makeCanvas(canvas, background: background)
        let clean = lines.filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
        if !clean.isEmpty { _ = draw(lines: clean, style: style, canvas: canvas, visibleCharacters: nil, in: ctx) }
        guard let image = ctx.makeImage() else { throw CaobaError.invalidParameters("title card") }
        return image
    }

    /// Capa de texto como `CIImage` en un punto de su animación: desplazada, escalada o
    /// atenuada según el tipo. La máquina de escribir la resuelve quien llama, con `render(visibleCharacters:)`.
    public static func animated(_ layer: TextLayer, animation: TextAnimation, phase: TextPhase, canvas: PixelSize) -> CIImage {
        let image = CIImage(cgImage: layer.image)
        let p = min(1, max(0, phase.progress))
        guard p < 0.999 else { return image }
        let e = Transitions.ease(p)
        let w = Double(canvas.width), h = Double(canvas.height)
        var result = image
        switch animation {
        case .none, .random, .mirror, .typewriter:
            return image
        case .fade:
            break
        case .slideUp:
            result = image.transformed(by: CGAffineTransform(translationX: 0, y: -(1 - e) * h * 0.2))
        case .slideDown:
            result = image.transformed(by: CGAffineTransform(translationX: 0, y: (1 - e) * h * 0.2))
        case .slideLeft:
            result = image.transformed(by: CGAffineTransform(translationX: (1 - e) * w * 0.2, y: 0))
        case .slideRight:
            result = image.transformed(by: CGAffineTransform(translationX: -(1 - e) * w * 0.2, y: 0))
        case .zoom:
            let s = 0.3 + 0.7 * e
            let cx = layer.block.midX, cy = layer.block.midY
            result = image.transformed(by: CGAffineTransform(translationX: cx, y: cy).scaledBy(x: s, y: s).translatedBy(x: -cx, y: -cy))
        }
        return result.applyingFilter("CIColorMatrix", parameters: ["inputAVector": CIVector(x: 0, y: 0, z: 0, w: CGFloat(p))])
            .cropped(to: CGRect(x: 0, y: 0, width: w, height: h))
    }

    /// Fuente pedida (con negrita si se puede) o la del sistema.
    static func font(for style: TextStyle, size: Double) -> CTFont {
        if let name = style.fontName, !name.isEmpty {
            let attributes: [CFString: Any] = [kCTFontFamilyNameAttribute: name]
            let descriptor = CTFontDescriptorCreateWithAttributes(attributes as CFDictionary)
            // Solo si la familia existe de verdad; si no, Core Text daría otra a escondidas.
            let mandatory = Set([kCTFontFamilyNameAttribute as String]) as NSSet
            if CTFontDescriptorCreateMatchingFontDescriptor(descriptor, mandatory) != nil {
                let base = CTFontCreateWithFontDescriptor(descriptor, size, nil)
                if style.bold, let bold = CTFontCreateCopyWithSymbolicTraits(base, size, nil, .boldTrait, .boldTrait) { return bold }
                return base
            }
        }
        return CTFontCreateUIFontForLanguage(style.bold ? .emphasizedSystem : .system, size, nil)
            ?? CTFontCreateWithName("Helvetica" as CFString, size, nil)
    }

    /// Dibuja las líneas y devuelve el rectángulo del bloque de texto.
    @discardableResult
    private static func draw(lines: [String], style: TextStyle, canvas: PixelSize, visibleCharacters: Int?, in ctx: CGContext) -> CGRect {
        let width = Double(canvas.width), height = Double(canvas.height)
        let firstSize = max(4, height * style.sizePercent / 100)
        let marginX = width * 0.05, marginY = height * 0.06
        let maxWidth = width - 2 * marginX
        let color = CGColor(red: style.color.red, green: style.color.green, blue: style.color.blue, alpha: 1)

        // Líneas ya medidas y truncadas si no caben.
        struct Measured { var line: CTLine; var partial: CTLine?; var width: Double; var ascent: Double; var descent: Double; var size: Double }
        var measured: [Measured] = []
        var remaining = visibleCharacters
        for (i, text) in lines.enumerated() {
            let size = i == 0 ? firstSize : firstSize * 0.55
            let font = font(for: style, size: size)
            let attributes: [NSAttributedString.Key: Any] = [kCTFontAttributeName as NSAttributedString.Key: font,
                                                             kCTForegroundColorAttributeName as NSAttributedString.Key: color]
            var line = CTLineCreateWithAttributedString(NSAttributedString(string: text, attributes: attributes))
            if CTLineGetTypographicBounds(line, nil, nil, nil) > maxWidth {
                let token = CTLineCreateWithAttributedString(NSAttributedString(string: "…", attributes: attributes))
                line = CTLineCreateTruncatedLine(line, maxWidth, .end, token) ?? line
            }
            // Máquina de escribir: solo los primeros caracteres, pero medidos sobre la línea completa.
            var partial: CTLine?
            if let left = remaining {
                let shown = String(text.prefix(max(0, left)))
                partial = CTLineCreateWithAttributedString(NSAttributedString(string: shown, attributes: attributes))
                remaining = max(0, left - text.count)
            }
            var ascent: CGFloat = 0, descent: CGFloat = 0
            let w = CTLineGetTypographicBounds(line, &ascent, &descent, nil)
            measured.append(Measured(line: line, partial: partial, width: w, ascent: Double(ascent), descent: Double(descent), size: size))
        }
        let gap = firstSize * 0.25
        let blockWidth = measured.map(\.width).max() ?? 0
        let blockHeight = measured.reduce(0) { $0 + $1.ascent + $1.descent } + gap * Double(max(0, measured.count - 1))

        // Origen del bloque (coordenadas Core Graphics: Y hacia arriba).
        let x: Double
        switch style.anchor.horizontal {
        case 0: x = marginX
        case 1: x = (width - blockWidth) / 2
        default: x = width - marginX - blockWidth
        }
        let y: Double
        switch style.anchor.vertical {
        case 0: y = height - marginY - blockHeight
        case 1: y = (height - blockHeight) / 2
        default: y = marginY
        }

        ctx.saveGState()
        if style.backdrop == .band {
            let pad = firstSize * 0.4
            let band = CGRect(x: x - pad, y: y - pad, width: blockWidth + 2 * pad, height: blockHeight + 2 * pad)
            let path = CGPath(roundedRect: band, cornerWidth: firstSize * 0.2, cornerHeight: firstSize * 0.2, transform: nil)
            ctx.setFillColor(CGColor(red: 0, green: 0, blue: 0, alpha: 0.45))
            ctx.addPath(path)
            ctx.fillPath()
        } else if style.backdrop == .shadow {
            ctx.setShadow(offset: CGSize(width: 0, height: -firstSize * 0.04), blur: firstSize * 0.12, color: CGColor(red: 0, green: 0, blue: 0, alpha: 0.85))
        }
        ctx.textMatrix = .identity
        // De arriba abajo: la primera línea en lo alto del bloque.
        var top = y + blockHeight
        for m in measured {
            let lineX: Double
            switch style.anchor.horizontal {
            case 0: lineX = x
            case 1: lineX = x + (blockWidth - m.width) / 2
            default: lineX = x + blockWidth - m.width
            }
            ctx.textPosition = CGPoint(x: lineX, y: top - m.ascent)
            CTLineDraw(m.partial ?? m.line, ctx)
            top -= m.ascent + m.descent + gap
        }
        ctx.restoreGState()
        return CGRect(x: x, y: y, width: blockWidth, height: blockHeight)
    }
}
