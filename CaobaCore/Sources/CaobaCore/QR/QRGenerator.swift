import Foundation
import CoreGraphics
import CoreImage
import CoreImage.CIFilterBuiltins

/// Color RGB sencillo para no depender de AppKit/UIKit en el motor.
public struct RGBColor: Sendable, Equatable, Codable {
    public var red: Double
    public var green: Double
    public var blue: Double

    public init(red: Double, green: Double, blue: Double) {
        self.red = red
        self.green = green
        self.blue = blue
    }

    public static let black = RGBColor(red: 0, green: 0, blue: 0)
    public static let white = RGBColor(red: 1, green: 1, blue: 1)

    /// Desde "#RRGGBB". Devuelve `nil` si el texto no es válido.
    public init?(hex: String) {
        var s = hex.trimmingCharacters(in: .whitespaces)
        if s.hasPrefix("#") { s.removeFirst() }
        guard s.count == 6, let v = UInt32(s, radix: 16) else { return nil }
        self.init(red: Double((v >> 16) & 0xFF) / 255, green: Double((v >> 8) & 0xFF) / 255, blue: Double(v & 0xFF) / 255)
    }

    public var hex: String {
        String(format: "#%02X%02X%02X", Int((red * 255).rounded()), Int((green * 255).rounded()), Int((blue * 255).rounded()))
    }

    var cgColor: CGColor { CGColor(red: red, green: green, blue: blue, alpha: 1) }
}

/// Opciones del QR.
public struct QROptions: Sendable, Equatable {
    public enum ErrorCorrection: String, Sendable, Codable, CaseIterable { case low = "L", medium = "M", quartile = "Q", high = "H" }

    /// Lado del PNG resultante en píxeles.
    public var size: Int
    public var foreground: RGBColor
    public var background: RGBColor
    public var correction: ErrorCorrection
    /// Margen (zona tranquila) en módulos.
    public var marginModules: Int
    /// Tamaño del logo como porcentaje del lado.
    public var logoPercent: Int

    public init(size: Int = 512, foreground: RGBColor = .black, background: RGBColor = .white,
                correction: ErrorCorrection = .medium, marginModules: Int = 2, logoPercent: Int = 20) {
        self.size = min(4096, max(64, size))
        self.foreground = foreground
        self.background = background
        self.correction = correction
        self.marginModules = max(0, marginModules)
        self.logoPercent = min(50, max(5, logoPercent))
    }
}

/// Generador de QR con Core Image. Produce una imagen nítida (sin suavizado)
/// con colores, margen y logo opcional en el centro.
public enum QRGenerator {

    /// Matriz de módulos (true = oscuro) del QR, sin margen.
    public static func modules(for text: String, correction: QROptions.ErrorCorrection) throws -> [[Bool]] {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { throw CaobaError.invalidParameters("qr.empty") }
        let filter = CIFilter.qrCodeGenerator()
        filter.message = Data(trimmed.utf8)
        filter.correctionLevel = correction.rawValue
        guard let output = filter.outputImage else { throw CaobaError.invalidParameters("qr.generate") }

        // Core Image devuelve un módulo por píxel con 1 módulo de margen alrededor.
        let context = CIContext(options: [.useSoftwareRenderer: false])
        guard let raw = context.createCGImage(output, from: output.extent) else { throw CaobaError.invalidParameters("qr.render") }
        let w = raw.width, h = raw.height
        guard let ctx = CGContext.rgba(width: w, height: h) else { throw CaobaError.invalidParameters("qr.render") }
        ctx.draw(raw, in: CGRect(x: 0, y: 0, width: w, height: h))
        guard let data = ctx.data?.assumingMemoryBound(to: UInt8.self) else { throw CaobaError.invalidParameters("qr.render") }

        var dark = [[Bool]](repeating: [Bool](repeating: false, count: w), count: h)
        for y in 0..<h {
            for x in 0..<w {
                dark[y][x] = data[y * ctx.bytesPerRow + x * 4] < 128
            }
        }
        // Recortamos al rectángulo de módulos oscuros para controlar el margen nosotros.
        var minX = w, minY = h, maxX = -1, maxY = -1
        for y in 0..<h { for x in 0..<w where dark[y][x] { minX = min(minX, x); maxX = max(maxX, x); minY = min(minY, y); maxY = max(maxY, y) } }
        guard maxX >= minX, maxY >= minY else { throw CaobaError.invalidParameters("qr.render") }
        return (minY...maxY).map { y in Array(dark[y][minX...maxX]) }
    }

    /// Imagen final del QR.
    public static func make(text: String, options: QROptions, logo: CGImage? = nil) throws -> CGImage {
        let grid = try modules(for: text, correction: options.correction)
        let n = grid.count
        let total = n + options.marginModules * 2
        // Dibujamos a tamaño de módulo y luego escalamos sin interpolar para que quede nítido.
        guard let small = CGContext.rgba(width: total, height: total) else { throw CaobaError.invalidParameters("qr.render") }
        small.setFillColor(options.background.cgColor)
        small.fill(CGRect(x: 0, y: 0, width: total, height: total))
        small.setFillColor(options.foreground.cgColor)
        for (y, row) in grid.enumerated() {
            for (x, isDark) in row.enumerated() where isDark {
                // Core Graphics tiene el origen abajo: invertimos la fila.
                small.fill(CGRect(x: x + options.marginModules, y: total - 1 - (y + options.marginModules), width: 1, height: 1))
            }
        }
        guard let smallImage = small.makeImage(), let big = CGContext.rgba(width: options.size, height: options.size) else {
            throw CaobaError.invalidParameters("qr.render")
        }
        big.interpolationQuality = .none
        big.draw(smallImage, in: CGRect(x: 0, y: 0, width: options.size, height: options.size))

        if let logo {
            // Logo centrado, encajado en un cuadrado del porcentaje pedido, sobre un
            // fondo del color claro para que no toque los módulos.
            let box = Double(options.size) * Double(options.logoPercent) / 100
            let scale = min(box / Double(logo.width), box / Double(logo.height))
            let lw = Double(logo.width) * scale, lh = Double(logo.height) * scale
            let origin = CGPoint(x: (Double(options.size) - lw) / 2, y: (Double(options.size) - lh) / 2)
            big.interpolationQuality = .high
            big.setFillColor(options.background.cgColor)
            let pad = max(2.0, box * 0.04)
            big.fill(CGRect(x: origin.x - pad, y: origin.y - pad, width: lw + pad * 2, height: lh + pad * 2))
            big.draw(logo, in: CGRect(x: origin.x, y: origin.y, width: lw, height: lh))
        }
        guard let result = big.makeImage() else { throw CaobaError.invalidParameters("qr.render") }
        return result
    }

    /// PNG listo para guardar.
    public static func png(text: String, options: QROptions, logo: CGImage? = nil) throws -> Data {
        try ImageWriter.encode(try make(text: text, options: options, logo: logo), encoding: ImageEncoding(format: .png))
    }
}
