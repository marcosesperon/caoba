import Foundation
import ImageIO
import CoreGraphics
import UniformTypeIdentifiers

/// Cómo codificar la imagen de salida.
public struct ImageEncoding: Sendable, Equatable {
    public var format: OutputFormat
    /// Calidad de 0 a 100 (como en la app antigua). Solo cuenta en JPEG y HEIC.
    public var quality: Int

    public init(format: OutputFormat, quality: Int = 90) {
        self.format = format
        self.quality = min(100, max(1, quality))
    }
}

/// Escritura de imágenes con ImageIO. Se encarga de llevarse los metadatos del
/// original (EXIF, GPS, perfil...) salvo los que dejan de ser válidos tras
/// procesar: orientación y dimensiones.
public enum ImageWriter {

    /// Propiedades del original que se copian a la salida. Quita la
    /// orientación (la imagen ya va "recta") y las dimensiones (cambian).
    public static func carriedMetadata(from source: [CFString: Any]?) -> [CFString: Any] {
        guard var props = source else { return [:] }
        props.removeValue(forKey: kCGImagePropertyOrientation)
        props.removeValue(forKey: kCGImagePropertyPixelWidth)
        props.removeValue(forKey: kCGImagePropertyPixelHeight)
        if var tiff = props[kCGImagePropertyTIFFDictionary] as? [CFString: Any] {
            tiff[kCGImagePropertyTIFFOrientation] = 1
            props[kCGImagePropertyTIFFDictionary] = tiff
        }
        if var exif = props[kCGImagePropertyExifDictionary] as? [CFString: Any] {
            exif.removeValue(forKey: kCGImagePropertyExifPixelXDimension)
            exif.removeValue(forKey: kCGImagePropertyExifPixelYDimension)
            props[kCGImagePropertyExifDictionary] = exif
        }
        return props
    }

    /// Codifica la imagen en memoria.
    public static func encode(_ image: CGImage, encoding: ImageEncoding, metadata: [CFString: Any] = [:]) throws -> Data {
        let data = NSMutableData()
        guard let dest = CGImageDestinationCreateWithData(data, encoding.format.utType.identifier as CFString, 1, nil) else {
            throw CaobaError.cannotWriteImage("destination")
        }
        try add(image, to: dest, encoding: encoding, metadata: metadata)
        return data as Data
    }

    /// Escribe la imagen en `url` pasando por un fichero temporal, de modo que
    /// nunca se queda un fichero a medias en la carpeta del usuario.
    public static func write(_ image: CGImage, to url: URL, encoding: ImageEncoding, metadata: [CFString: Any] = [:]) throws {
        let temp = try TempFiles.makeFileURL(extension: encoding.format.fileExtension)
        defer { TempFiles.remove(temp) }
        guard let dest = CGImageDestinationCreateWithURL(temp as CFURL, encoding.format.utType.identifier as CFString, 1, nil) else {
            throw CaobaError.cannotWriteImage(url.lastPathComponent)
        }
        try add(image, to: dest, encoding: encoding, metadata: metadata)
        try FileOperations.commit(temporary: temp, to: url)
    }

    private static func add(_ image: CGImage, to dest: CGImageDestination, encoding: ImageEncoding, metadata: [CFString: Any]) throws {
        var props = metadata
        if encoding.format.supportsQuality {
            props[kCGImageDestinationLossyCompressionQuality] = Double(encoding.quality) / 100.0
        }
        CGImageDestinationAddImage(dest, image, props as CFDictionary)
        guard CGImageDestinationFinalize(dest) else { throw CaobaError.cannotWriteImage("finalize") }
    }
}
