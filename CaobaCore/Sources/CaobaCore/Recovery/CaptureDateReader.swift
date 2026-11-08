import Foundation
import ImageIO
import AVFoundation

/// Fecha en la que se hizo una foto o un vídeo, sacada de sus metadatos. No mira la
/// fecha del fichero: en lo recuperado por PhotoRec no significa nada.
public enum CaptureDateReader {
    /// Fotos (JPG, HEIC, RAW…): `DateTimeOriginal` con ImageIO. Vídeos: la fecha de
    /// creación con AVFoundation. `nil` si no hay o no se puede leer.
    public static func captureDate(of url: URL) async -> Date? {
        if RecoveryFileGroup.group(of: url) == .video {
            return await videoDate(of: url)
        }
        return ImageIOHelpers.captureDate(from: ImageIOHelpers.properties(of: url))
    }

    /// Fecha de creación del vídeo (`creationDate` de AVFoundation, que lee la de QuickTime
    /// o la de MP4). Algunas cámaras la guardan como texto ISO 8601 en vez de como fecha.
    static func videoDate(of url: URL) async -> Date? {
        guard let item = try? await AVURLAsset(url: url).load(.creationDate) else { return nil }
        if let date = try? await item.load(.dateValue) { return date }
        guard let text = try? await item.load(.stringValue) else { return nil }
        return ISO8601DateFormatter().date(from: text)
    }
}
