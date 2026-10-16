import Foundation
import ImageIO
import CoreGraphics
import UniformTypeIdentifiers

/// Errores del motor que llegan a la interfaz. Los textos los pone la app con
/// sus traducciones; aquí solo viaja el caso.
public enum CaobaError: Error, Sendable, Equatable {
    case cancelled
    case cannotReadImage(String)
    case cannotWriteImage(String)
    case noFiles
    case invalidParameters(String)
    case metadataWriteFailed(String)
    case fileOperationFailed(String)
}

/// Tamaño en píxeles ya girado según la orientación EXIF, es decir, tal como
/// lo ve el usuario.
public struct PixelSize: Sendable, Equatable {
    public var width: Int
    public var height: Int

    public init(width: Int, height: Int) {
        self.width = width
        self.height = height
    }

    public var aspectRatio: Double { height > 0 ? Double(width) / Double(height) : 1 }
    public var isLandscape: Bool { width >= height }
    public var isPortrait: Bool { height > width }
}

/// Atajos sobre ImageIO que usamos por todo el motor. Leer propiedades no
/// decodifica la imagen, así que es barato aunque el fichero sea enorme.
public enum ImageIOHelpers {

    /// Abre la fuente de imagen sin cachear nada en memoria.
    public static func source(for url: URL) -> CGImageSource? {
        let options = [kCGImageSourceShouldCache: false] as CFDictionary
        return CGImageSourceCreateWithURL(url as CFURL, options)
    }

    /// Propiedades (EXIF, TIFF, GPS, dimensiones...) de la primera imagen del fichero.
    public static func properties(of url: URL) -> [CFString: Any]? {
        guard let src = source(for: url) else { return nil }
        return properties(of: src)
    }

    public static func properties(of source: CGImageSource) -> [CFString: Any]? {
        let options = [kCGImageSourceShouldCache: false] as CFDictionary
        return CGImageSourceCopyPropertiesAtIndex(source, 0, options) as? [CFString: Any]
    }

    /// Orientación EXIF (1-8) leída de las propiedades; 1 si no hay.
    public static func orientation(from properties: [CFString: Any]?) -> CGImagePropertyOrientation {
        guard let raw = properties?[kCGImagePropertyOrientation] as? UInt32,
              let orientation = CGImagePropertyOrientation(rawValue: raw) else { return .up }
        return orientation
    }

    /// Tamaño visible de la imagen: intercambia ancho y alto si la orientación
    /// EXIF es de 90 o 270 grados (valores 5 a 8).
    public static func displaySize(of url: URL) -> PixelSize? {
        guard let props = properties(of: url) else { return nil }
        return displaySize(from: props)
    }

    public static func displaySize(from properties: [CFString: Any]) -> PixelSize? {
        guard let w = properties[kCGImagePropertyPixelWidth] as? Int,
              let h = properties[kCGImagePropertyPixelHeight] as? Int else { return nil }
        let orientation = orientation(from: properties)
        if orientation.rawValue >= 5 {
            return PixelSize(width: h, height: w)
        }
        return PixelSize(width: w, height: h)
    }

    /// Fecha de captura (`DateTimeOriginal`, o `DateTimeDigitized` si no hay).
    /// Devuelve `nil` si la imagen no trae fecha EXIF.
    public static func captureDate(from properties: [CFString: Any]?) -> Date? {
        guard let exif = properties?[kCGImagePropertyExifDictionary] as? [CFString: Any] else { return nil }
        let raw = (exif[kCGImagePropertyExifDateTimeOriginal] as? String)
            ?? (exif[kCGImagePropertyExifDateTimeDigitized] as? String)
        guard let raw else { return nil }
        return ExifDate.parse(raw)
    }

    /// Fecha de captura o, si no la hay, fecha de creación del fichero.
    public static func captureOrFileDate(of url: URL) -> Date {
        if let date = captureDate(from: properties(of: url)) { return date }
        let attrs = try? FileManager.default.attributesOfItem(atPath: url.path)
        return (attrs?[.creationDate] as? Date) ?? (attrs?[.modificationDate] as? Date) ?? .distantPast
    }

    /// Decodifica la imagen completa y, si se pide, la deja ya girada según su
    /// orientación EXIF para que el resto del motor trabaje con píxeles "rectos".
    public static func loadImage(from url: URL, applyingOrientation: Bool = true) throws -> CGImage {
        guard let src = source(for: url) else { throw CaobaError.cannotReadImage(url.lastPathComponent) }
        let options = [kCGImageSourceShouldCache: false] as CFDictionary
        guard let image = CGImageSourceCreateImageAtIndex(src, 0, options) else {
            throw CaobaError.cannotReadImage(url.lastPathComponent)
        }
        guard applyingOrientation else { return image }
        let orientation = orientation(from: properties(of: src))
        guard orientation != .up else { return image }
        // Pedimos a ImageIO un "thumbnail" del tamaño completo con la
        // transformación aplicada: es la forma más fiable de obtener la imagen
        // ya girada sin reimplementar las ocho orientaciones.
        let fullOptions: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: max(image.width, image.height),
            kCGImageSourceShouldCache: false,
        ]
        if let rotated = CGImageSourceCreateThumbnailAtIndex(src, 0, fullOptions as CFDictionary) {
            return rotated
        }
        return image.oriented(orientation)
    }
}

/// Las fechas EXIF vienen como "2024:05:31 14:22:10". Este tipo las convierte
/// en ambos sentidos sin depender de la zona horaria del Mac.
public enum ExifDate {
    private static let formatter: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = TimeZone.current
        f.dateFormat = "yyyy:MM:dd HH:mm:ss"
        return f
    }()

    public static func parse(_ raw: String) -> Date? {
        // Algunas cámaras rellenan con espacios o ceros cuando no hay fecha.
        let trimmed = raw.trimmingCharacters(in: .whitespaces)
        guard trimmed.count >= 19, !trimmed.hasPrefix("0000") else { return nil }
        return formatter.date(from: String(trimmed.prefix(19)))
    }

    public static func format(_ date: Date) -> String {
        formatter.string(from: date)
    }
}

public extension CGImage {
    /// Devuelve una copia de la imagen girada/volteada según una orientación EXIF.
    /// Si la orientación es `.up` devuelve la misma imagen sin copiar nada.
    func oriented(_ orientation: CGImagePropertyOrientation) -> CGImage {
        guard orientation != .up else { return self }

        let swapsAxes = orientation.rawValue >= 5
        let outW = swapsAxes ? height : width
        let outH = swapsAxes ? width : height

        guard let ctx = CGContext.rgba(width: outW, height: outH, colorSpace: colorSpace) else { return self }

        // Matriz que lleva cada píxel de la imagen almacenada a su sitio en la
        // salida, en coordenadas de Core Graphics (origen abajo-izquierda).
        // x' = a*x + c*y + tx ; y' = b*x + d*y + ty
        let w = CGFloat(width), h = CGFloat(height)
        let transform: CGAffineTransform
        switch orientation {
        case .up:            transform = .identity
        case .upMirrored:    transform = CGAffineTransform(a: -1, b: 0, c: 0, d: 1, tx: w, ty: 0)
        case .down:          transform = CGAffineTransform(a: -1, b: 0, c: 0, d: -1, tx: w, ty: h)
        case .downMirrored:  transform = CGAffineTransform(a: 1, b: 0, c: 0, d: -1, tx: 0, ty: h)
        case .leftMirrored:  transform = CGAffineTransform(a: 0, b: -1, c: -1, d: 0, tx: h, ty: w)
        case .right:         transform = CGAffineTransform(a: 0, b: -1, c: 1, d: 0, tx: 0, ty: w)
        case .rightMirrored: transform = CGAffineTransform(a: 0, b: 1, c: 1, d: 0, tx: 0, ty: 0)
        case .left:          transform = CGAffineTransform(a: 0, b: 1, c: -1, d: 0, tx: h, ty: 0)
        }
        ctx.concatenate(transform)
        ctx.draw(self, in: CGRect(x: 0, y: 0, width: width, height: height))
        return ctx.makeImage() ?? self
    }

    /// Escala la imagen al tamaño indicado con interpolación de alta calidad.
    func resized(to size: PixelSize) -> CGImage? {
        guard size.width > 0, size.height > 0 else { return nil }
        guard let ctx = CGContext.rgba(width: size.width, height: size.height, colorSpace: colorSpace) else { return nil }
        ctx.interpolationQuality = .high
        ctx.draw(self, in: CGRect(x: 0, y: 0, width: size.width, height: size.height))
        return ctx.makeImage()
    }

    /// Tamaño que cabe dentro de `maxDimension` manteniendo la proporción y sin ampliar.
    func sizeFitting(maxDimension: Int) -> PixelSize {
        let longest = max(width, height)
        guard longest > maxDimension else { return PixelSize(width: width, height: height) }
        let scale = Double(maxDimension) / Double(longest)
        return PixelSize(width: max(1, Int((Double(width) * scale).rounded())),
                         height: max(1, Int((Double(height) * scale).rounded())))
    }

    var pixelSize: PixelSize { PixelSize(width: width, height: height) }
}

public extension CGContext {
    /// Contexto RGBA de 8 bits con alfa premultiplicado, que es lo que mejor
    /// trata Core Graphics para dibujar y componer.
    static func rgba(width: Int, height: Int, colorSpace: CGColorSpace? = nil) -> CGContext? {
        let space = colorSpace.flatMap { $0.model == .rgb ? $0 : nil } ?? CGColorSpace(name: CGColorSpace.sRGB)!
        return CGContext(
            data: nil,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: space,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        )
    }
}
