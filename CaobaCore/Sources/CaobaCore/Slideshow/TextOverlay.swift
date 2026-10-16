import Foundation
import CoreGraphics
import CoreText

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

    public init(fontName: String? = nil, bold: Bool = false, sizePercent: Double = 4, color: RGBColor = RGBColor(red: 1, green: 1, blue: 1),
                anchor: TextAnchor = .bottomLeft, backdrop: TextBackdrop = .shadow) {
        self.fontName = fontName
        self.bold = bold
        self.sizePercent = sizePercent
        self.color = color
        self.anchor = anchor
        self.backdrop = backdrop
    }

    public static let title = TextStyle(fontName: "Doto", bold: true, sizePercent: 9, anchor: .center, backdrop: .shadow)
    public static let caption = TextStyle(fontName: nil, bold: false, sizePercent: 3, anchor: .bottomLeft, backdrop: .band)
}

/// Texto que se superpone a una foto durante unos segundos, con fundido.
public struct TextOverlay: Sendable, Equatable {
    public var lines: [String]
    public var style: TextStyle
    public var duration: Double
    public var fade: Double
    /// Segundos del título ya transcurridos antes de esta foto (cuando el título
    /// abarca varios pasos de un collage, cada paso lleva su desfase).
    public var offset: Double

    public init(lines: [String], style: TextStyle, duration: Double, fade: Double = 0.6, offset: Double = 0) {
        self.lines = lines.filter { !$0.isEmpty }
        self.style = style
        self.duration = duration
        self.fade = fade
        self.offset = offset
    }

    /// Opacidad en el segundo `t` desde que empieza la foto.
    public func opacity(at local: Double) -> Double {
        let t = local + offset
        guard t >= 0, t <= duration else { return 0 }
        guard fade > 0 else { return 1 }
        return min(1, max(0, min(t / fade, (duration - t) / fade)))
    }
}

/// Dibuja textos con Core Text: una capa transparente del tamaño del vídeo o
/// una tarjeta con fondo de color.
public enum TextRenderer {
    /// Capa transparente con las líneas colocadas según el estilo; `nil` sin texto.
    public static func layer(lines: [String], style: TextStyle, canvas: PixelSize) -> CGImage? {
        let clean = lines.filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
        guard !clean.isEmpty, let ctx = CGContext.rgba(width: canvas.width, height: canvas.height) else { return nil }
        draw(lines: clean, style: style, canvas: canvas, in: ctx)
        return ctx.makeImage()
    }

    /// Tarjeta de título: fondo de color y el texto centrado (o donde diga el estilo).
    public static func card(lines: [String], style: TextStyle, background: CGColor, canvas: PixelSize) throws -> CGImage {
        let ctx = try Drawing.makeCanvas(canvas, background: background)
        let clean = lines.filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
        if !clean.isEmpty { draw(lines: clean, style: style, canvas: canvas, in: ctx) }
        guard let image = ctx.makeImage() else { throw CaobaError.invalidParameters("title card") }
        return image
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

    private static func draw(lines: [String], style: TextStyle, canvas: PixelSize, in ctx: CGContext) {
        let width = Double(canvas.width), height = Double(canvas.height)
        let firstSize = max(4, height * style.sizePercent / 100)
        let marginX = width * 0.05, marginY = height * 0.06
        let maxWidth = width - 2 * marginX
        let color = CGColor(red: style.color.red, green: style.color.green, blue: style.color.blue, alpha: 1)

        // Líneas ya medidas y truncadas si no caben.
        struct Measured { var line: CTLine; var width: Double; var ascent: Double; var descent: Double; var size: Double }
        var measured: [Measured] = []
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
            var ascent: CGFloat = 0, descent: CGFloat = 0
            let w = CTLineGetTypographicBounds(line, &ascent, &descent, nil)
            measured.append(Measured(line: line, width: w, ascent: Double(ascent), descent: Double(descent), size: size))
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
            CTLineDraw(m.line, ctx)
            top -= m.ascent + m.descent + gap
        }
        ctx.restoreGState()
    }
}
