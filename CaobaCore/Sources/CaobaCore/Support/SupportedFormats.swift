import Foundation
import UniformTypeIdentifiers

/// Qué extensiones entiende CAOBA y cómo se escriben los formatos de salida.
public enum SupportedFormats {
    /// Imágenes "normales" que entran en todos los módulos (sin RAW).
    public static let imageExtensions: Set<String> = [
        "jpg", "jpeg", "png", "tiff", "tif", "heic", "heif", "webp", "avif",
    ]

    /// Ficheros RAW de cámara. ImageIO los decodifica, pero son lentos y pesados,
    /// así que solo se ofrecen donde tiene sentido (por ejemplo, Shutter Count).
    public static let rawExtensions: Set<String> = [
        "nef", "cr2", "cr3", "arw", "orf", "rw2", "raf", "dng", "pef",
    ]

    /// Pistas de audio aceptadas en el slideshow.
    public static let audioExtensions: Set<String> = ["mp3", "m4a", "aac", "wav", "aiff"]

    /// Comprueba si una URL apunta a una imagen soportada (con o sin RAW).
    public static func isImage(_ url: URL, includingRaw: Bool = false) -> Bool {
        let ext = url.pathExtension.lowercased()
        if imageExtensions.contains(ext) { return true }
        return includingRaw && rawExtensions.contains(ext)
    }
}

/// Formatos en los que el motor sabe escribir. Solo los que ImageIO soporta de
/// serie: WebP y AVIF se leen pero no se escriben (decisión P9).
public enum OutputFormat: String, CaseIterable, Sendable, Codable {
    case jpeg, png, heic, tiff

    /// Tipo uniforme que espera `CGImageDestination`.
    public var utType: UTType {
        switch self {
        case .jpeg: return .jpeg
        case .png: return .png
        case .heic: return .heic
        case .tiff: return .tiff
        }
    }

    /// Extensión que se pone al fichero de salida.
    public var fileExtension: String {
        switch self {
        case .jpeg: return "jpg"
        case .png: return "png"
        case .heic: return "heic"
        case .tiff: return "tiff"
        }
    }

    /// Si el formato tiene compresión con pérdida y, por tanto, admite "calidad".
    public var supportsQuality: Bool {
        switch self {
        case .jpeg, .heic: return true
        case .png, .tiff: return false
        }
    }

    /// Formato que corresponde a la extensión de un fichero existente. Si el
    /// fichero es de un formato que no sabemos escribir (WebP, AVIF, RAW),
    /// devolvemos JPEG, que es lo que hace también la app antigua.
    public static func matching(extensionOf url: URL) -> OutputFormat {
        switch url.pathExtension.lowercased() {
        case "png": return .png
        case "heic", "heif": return .heic
        case "tiff", "tif": return .tiff
        default: return .jpeg
        }
    }
}
