import Foundation
import CoreGraphics
import CoreText

/// Colores de fondo que ofrecen collage y contact sheet, con el color de texto
/// y de borde que mejor contrasta con cada uno (igual que la app antigua).
public enum CanvasBackground: String, Sendable, Codable, CaseIterable {
    case white, black, gray

    public var fill: CGColor {
        switch self {
        case .white: return CGColor(red: 1, green: 1, blue: 1, alpha: 1)
        // Negro puro: con un gris oscuro las tarjetas del pase no se funden con el negro de la pantalla.
        case .black: return CGColor(red: 0, green: 0, blue: 0, alpha: 1)
        case .gray: return CGColor(red: 0.5, green: 0.5, blue: 0.5, alpha: 1)
        }
    }

    public var text: CGColor {
        switch self {
        case .white: return CGColor(red: 0.2, green: 0.2, blue: 0.2, alpha: 1)
        case .black: return CGColor(red: 0.93, green: 0.93, blue: 0.93, alpha: 1)
        case .gray: return CGColor(red: 1, green: 1, blue: 1, alpha: 1)
        }
    }

    var border: CGColor {
        switch self {
        case .white: return CGColor(red: 0.8, green: 0.8, blue: 0.8, alpha: 1)
        case .black: return CGColor(red: 0.4, green: 0.4, blue: 0.4, alpha: 1)
        case .gray: return CGColor(red: 1, green: 1, blue: 1, alpha: 1)
        }
    }
}

/// Fondo de collage y contact sheet: uno de los tres de siempre o un color propio.
/// El texto y el borde se eligen según lo claro u oscuro que sea el fondo. Se guarda como
/// antes para los tres de siempre («white») y como «#RRGGBB» para un color propio, así los
/// presets y proyectos antiguos se siguen leyendo.
public enum CanvasColor: Sendable, Equatable, Hashable, Codable {
    case preset(CanvasBackground)
    case custom(RGBColor)

    public static let white = CanvasColor.preset(.white)
    public static let black = CanvasColor.preset(.black)
    public static let gray = CanvasColor.preset(.gray)

    public var fill: CGColor {
        switch self {
        case .preset(let p): return p.fill
        // En sRGB, el espacio del selector de color: así sale el mismo color que se eligió
        // (con `CGColor(red:green:blue:)`, RGB genérico, saldría más claro al dibujarlo).
        case .custom(let c): return CGColor(srgbRed: c.red, green: c.green, blue: c.blue, alpha: 1)
        }
    }

    public var text: CGColor {
        switch self {
        case .preset(let p): return p.text
        case .custom: return isDark ? CGColor(red: 0.93, green: 0.93, blue: 0.93, alpha: 1) : CGColor(red: 0.2, green: 0.2, blue: 0.2, alpha: 1)
        }
    }

    var border: CGColor {
        switch self {
        case .preset(let p): return p.border
        case .custom: return isDark ? CGColor(red: 0.4, green: 0.4, blue: 0.4, alpha: 1) : CGColor(red: 0.8, green: 0.8, blue: 0.8, alpha: 1)
        }
    }

    /// Fondo oscuro (luminancia relativa por debajo de la mitad): pide texto claro.
    public var isDark: Bool {
        guard case .custom(let c) = self else { return self == .black }
        return 0.2126 * c.red + 0.7152 * c.green + 0.0722 * c.blue < 0.5
    }

    /// Texto que se guarda: «white», «black», «gray» o «#RRGGBB».
    public var rawValue: String {
        switch self {
        case .preset(let p): return p.rawValue
        case .custom(let c):
            func byte(_ v: Double) -> Int { Int((min(1, max(0, v)) * 255).rounded()) }
            return String(format: "#%02X%02X%02X", byte(c.red), byte(c.green), byte(c.blue))
        }
    }

    public init?(rawValue: String) {
        if let p = CanvasBackground(rawValue: rawValue) { self = .preset(p); return }
        let hex = rawValue.trimmingCharacters(in: .whitespaces)
        guard hex.hasPrefix("#"), hex.count == 7, let v = Int(hex.dropFirst(), radix: 16) else { return nil }
        self = .custom(RGBColor(red: Double((v >> 16) & 0xFF) / 255, green: Double((v >> 8) & 0xFF) / 255, blue: Double(v & 0xFF) / 255))
    }

    public init(from decoder: Decoder) throws {
        let raw = try decoder.singleValueContainer().decode(String.self)
        guard let value = CanvasColor(rawValue: raw) else {
            throw DecodingError.dataCorrupted(.init(codingPath: decoder.codingPath, debugDescription: "Fondo no válido: \(raw)"))
        }
        self = value
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.singleValueContainer()
        try c.encode(rawValue)
    }
}

/// Logo superpuesto al resultado (collage y contact sheet).
public struct LogoOptions: Sendable, Equatable {
    public var url: URL
    public var position: OverlayPosition
    /// Ancho del logo como porcentaje del ancho del lienzo.
    public var sizePercent: Double
    /// Opacidad 0-100.
    public var opacity: Double

    public init(url: URL, position: OverlayPosition = .bottomRight, sizePercent: Double = 20, opacity: Double = 80) {
        self.url = url
        self.position = position
        self.sizePercent = sizePercent
        self.opacity = opacity
    }
}

/// Utilidades de dibujo en Core Graphics con coordenadas "de usuario"
/// (origen arriba-izquierda). Cada función convierte a las de CG (abajo).
public enum Drawing {

    /// Rectángulo en coordenadas arriba-izquierda → Core Graphics.
    public static func cgRect(_ rect: CGRect, canvasHeight: Int) -> CGRect {
        CGRect(x: rect.minX, y: Double(canvasHeight) - rect.maxY, width: rect.width, height: rect.height)
    }

    /// Dibuja una imagen recortada por `crop` (en píxeles de la imagen, origen
    /// arriba-izquierda) para que llene `rect` del lienzo, con esquinas
    /// redondeadas opcionales.
    public static func drawImage(_ image: CGImage, crop: CGRect, into rect: CGRect, cornerRadius: Double, in ctx: CGContext, canvasHeight: Int) {
        guard let cropped = image.croppedTopLeft(crop) else { return }
        let target = cgRect(rect, canvasHeight: canvasHeight)
        ctx.saveGState()
        if cornerRadius > 0 {
            let r = min(cornerRadius, rect.width / 2, rect.height / 2)
            ctx.addPath(CGPath(roundedRect: target, cornerWidth: r, cornerHeight: r, transform: nil))
            ctx.clip()
        }
        ctx.interpolationQuality = .high
        ctx.draw(cropped, in: target)
        ctx.restoreGState()
    }

    /// Rectángulo relleno (opcionalmente redondeado) con sombra.
    public static func fillRect(_ rect: CGRect, color: CGColor, cornerRadius: Double = 0, shadow: (offset: CGSize, blur: Double, color: CGColor)? = nil,
                                in ctx: CGContext, canvasHeight: Int) {
        let target = cgRect(rect, canvasHeight: canvasHeight)
        ctx.saveGState()
        if let shadow {
            // La sombra en CG va con Y hacia arriba: invertimos el desplazamiento vertical.
            ctx.setShadow(offset: CGSize(width: shadow.offset.width, height: -shadow.offset.height), blur: shadow.blur, color: shadow.color)
        }
        ctx.setFillColor(color)
        if cornerRadius > 0 {
            ctx.addPath(CGPath(roundedRect: target, cornerWidth: cornerRadius, cornerHeight: cornerRadius, transform: nil))
            ctx.fillPath()
        } else {
            ctx.fill(target)
        }
        ctx.restoreGState()
    }

    /// Borde rectangular.
    public static func strokeRect(_ rect: CGRect, color: CGColor, width: Double, in ctx: CGContext, canvasHeight: Int) {
        let target = cgRect(rect, canvasHeight: canvasHeight).insetBy(dx: width / 2, dy: width / 2)
        ctx.saveGState()
        ctx.setStrokeColor(color)
        ctx.setLineWidth(width)
        ctx.stroke(target)
        ctx.restoreGState()
    }

    /// Texto centrado horizontalmente en `center` (coordenadas arriba-izquierda,
    /// `center.y` es la línea base). Devuelve el ancho dibujado.
    @discardableResult
    public static func drawText(_ text: String, centeredAt center: CGPoint, fontSize: Double, bold: Bool, color: CGColor,
                                maxWidth: Double? = nil, in ctx: CGContext, canvasHeight: Int) -> Double {
        let font = CTFontCreateUIFontForLanguage(bold ? .emphasizedSystem : .system, fontSize, nil)
            ?? CTFontCreateWithName("Helvetica" as CFString, fontSize, nil)
        let attributes: [CFString: Any] = [kCTFontAttributeName: font, kCTForegroundColorAttributeName: color]
        var line = CTLineCreateWithAttributedString(NSAttributedString(string: text, attributes: attributes as [NSAttributedString.Key: Any]))
        if let maxWidth, CTLineGetTypographicBounds(line, nil, nil, nil) > maxWidth {
            // Acortamos con puntos suspensivos si no cabe.
            let token = CTLineCreateWithAttributedString(NSAttributedString(string: "…", attributes: attributes as [NSAttributedString.Key: Any]))
            line = CTLineCreateTruncatedLine(line, maxWidth, .end, token) ?? line
        }
        let width = CTLineGetTypographicBounds(line, nil, nil, nil)
        ctx.saveGState()
        ctx.textMatrix = .identity
        ctx.textPosition = CGPoint(x: center.x - width / 2, y: Double(canvasHeight) - center.y)
        CTLineDraw(line, ctx)
        ctx.restoreGState()
        return width
    }

    /// Logo con opacidad y posición, escalado al porcentaje del ancho del lienzo.
    public static func drawLogo(_ options: LogoOptions, in ctx: CGContext, canvas: PixelSize) throws {
        let logo = try ImageIOHelpers.loadImage(from: options.url)
        let targetW = Int((Double(canvas.width) * options.sizePercent / 100).rounded())
        guard targetW >= 1, logo.width > 0 else { return }
        let targetH = max(1, Int((Double(targetW) / Double(logo.width) * Double(logo.height)).rounded()))
        let size = PixelSize(width: targetW, height: targetH)
        let origin = options.position.origin(for: size, in: canvas)
        let rect = CGRect(x: max(0, origin.x), y: max(0, origin.y), width: Double(targetW), height: Double(targetH))
        ctx.saveGState()
        ctx.setAlpha(min(100, max(0, options.opacity)) / 100)
        ctx.interpolationQuality = .high
        ctx.draw(logo, in: cgRect(rect, canvasHeight: canvas.height))
        ctx.restoreGState()
    }

    /// Lienzo nuevo relleno con un color.
    public static func makeCanvas(_ size: PixelSize, background: CGColor) throws -> CGContext {
        guard let ctx = CGContext.rgba(width: size.width, height: size.height) else {
            throw CaobaError.invalidParameters("canvas")
        }
        ctx.setFillColor(background)
        ctx.fill(CGRect(x: 0, y: 0, width: size.width, height: size.height))
        return ctx
    }
}

/// Carga una foto ya reducida al tamaño que hace falta para una celda, con la
/// orientación aplicada. Decodificar por debajo del tamaño original ahorra
/// mucha memoria en collages con fotos de 50 MP.
public enum PhotoLoader {
    public static func load(_ url: URL, fittingAtLeast size: PixelSize) throws -> CGImage {
        // Pedimos un poco más de lo necesario para que el recorte por foco no pierda nitidez.
        let needed = Int(Double(max(size.width, size.height)) * 1.5)
        if let display = ImageIOHelpers.displaySize(of: url), max(display.width, display.height) <= needed {
            return try ImageIOHelpers.loadImage(from: url)
        }
        if let reduced = ThumbnailProvider.makeThumbnail(url: url, maxPixelSize: needed) { return reduced }
        return try ImageIOHelpers.loadImage(from: url)
    }
}
