import Foundation
import CoreGraphics

/// Modo "collage slideshow": cada collage aparece foto a foto. Genera los
/// fotogramas intermedios como JPEG en una carpeta temporal y los convierte en
/// fotos del slideshow con sus duraciones.
public enum CollageSlideshow {
    /// Tiempo que se ve el lienzo vacío antes de la primera foto.
    public static let emptyFrameSeconds = 0.5

    public struct Options: Sendable, Equatable {
        public var reveal: Double
        public var hold: Double
        public var collage: CollageOptions

        public init(reveal: Double = 1.5, hold: Double = 3, collage: CollageOptions = CollageOptions(longestSide: 1920)) {
            self.reveal = max(0.2, reveal)
            self.hold = max(0, hold)
            self.collage = collage
        }
    }

    /// Duraciones de los fotogramas de un collage de `photos` fotos:
    /// vacío (0,5 s), una aparición por foto y la última foto mantiene además el `hold`.
    public static func durations(photos: Int, options: Options, hold: Double? = nil) -> [Double] {
        guard photos > 0 else { return [] }
        var result = [emptyFrameSeconds]
        result.append(contentsOf: Array(repeating: options.reveal, count: photos))
        result[result.count - 1] += max(0, hold ?? options.hold)
        return result
    }

    /// Duración de un collage concreto (respeta su `hold` propio si lo tiene).
    public static func duration(of row: CollageRow, options: Options) -> Double {
        durations(photos: row.template.photos, options: options, hold: row.hold).reduce(0, +)
    }

    /// Duración total del vídeo de collage (sin portada ni créditos ni transiciones).
    public static func totalDuration(rows: [CollageRow], options: Options) -> Double {
        rows.reduce(0) { $0 + duration(of: $1, options: options) }
    }

    /// Renderiza los fotogramas en `directory` y devuelve las fotos del slideshow.
    public static func makePhotos(rows: [CollageRow], options: Options, directory: URL, progress: ProgressHandler? = nil) async throws -> [SlideshowPhoto] {
        guard !rows.isEmpty else { throw CaobaError.noFiles }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let total = rows.reduce(0) { $0 + $1.template.photos + 1 }
        var done = 0
        var photos: [SlideshowPhoto] = []
        for (r, row) in rows.enumerated() {
            let durations = durations(photos: row.template.photos, options: options, hold: row.hold)
            for visible in 0...row.template.photos {
                try Task.checkCaobaCancellation()
                progress?(.step(done, of: total, phase: .generatingFrames, file: row.template.name))
                let image = try CollageRenderer.render(row, options: options.collage, visibleCells: visible)
                let url = directory.appendingPathComponent(String(format: "page%03d_frame%02d.jpg", r, visible))
                try ImageWriter.write(image, to: url, encoding: ImageEncoding(format: .jpeg, quality: 95))
                photos.append(SlideshowPhoto(url: url, duration: durations[visible]))
                done += 1
            }
        }
        progress?(.step(total, of: total, phase: .generatingFrames))
        return photos
    }
}
