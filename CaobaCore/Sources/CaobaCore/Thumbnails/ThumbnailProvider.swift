import Foundation
import ImageIO
import CoreGraphics

/// Miniaturas rápidas con caché. Si el JPEG trae thumbnail EXIF, ImageIO lo
/// usa sin decodificar la foto entera; si no, la decodifica reducida.
public actor ThumbnailProvider {
    private let cache = NSCache<NSString, CGImage>()
    private let semaphore: AsyncSemaphore

    public init(concurrency: Int = ProcessInfo.processInfo.activeProcessorCount, cacheLimit: Int = 2000) {
        semaphore = AsyncSemaphore(limit: concurrency)
        cache.countLimit = cacheLimit
    }

    /// Miniatura con el lado mayor como máximo `maxPixelSize`, ya girada según EXIF.
    public func thumbnail(for url: URL, maxPixelSize: Int) async -> CGImage? {
        let key = "\(url.path)|\(maxPixelSize)" as NSString
        if let cached = cache.object(forKey: key) { return cached }

        let image = await semaphore.run { Self.makeThumbnail(url: url, maxPixelSize: maxPixelSize) }
        if let image { cache.setObject(image, forKey: key) }
        return image
    }

    public func clear() {
        cache.removeAllObjects()
    }

    /// Generación sin caché, útil para tests y para previews grandes.
    ///
    /// ImageIO devuelve la miniatura EXIF embebida (unos 160 px) si existe, por
    /// pequeña que sea. Eso va bien para la lista, pero para el editor o para
    /// componer un collage hace falta decodificar la foto de verdad: si lo que
    /// devuelve es más pequeño de lo pedido (y la foto es mayor), repetimos
    /// forzando la decodificación.
    public static func makeThumbnail(url: URL, maxPixelSize: Int) -> CGImage? {
        guard let src = ImageIOHelpers.source(for: url) else { return nil }
        var options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageIfAbsent: true,
            kCGImageSourceCreateThumbnailWithTransform: true, // aplica la orientación EXIF
            kCGImageSourceThumbnailMaxPixelSize: maxPixelSize,
            kCGImageSourceShouldCache: false,
        ]
        guard var thumb = CGImageSourceCreateThumbnailAtIndex(src, 0, options as CFDictionary) else { return nil }

        let display = ImageIOHelpers.properties(of: src).flatMap { ImageIOHelpers.displaySize(from: $0) }
        let sourceMax = display.map { max($0.width, $0.height) } ?? maxPixelSize
        let wanted = min(maxPixelSize, sourceMax)
        if max(thumb.width, thumb.height) < wanted {
            options[kCGImageSourceCreateThumbnailFromImageIfAbsent] = nil
            options[kCGImageSourceCreateThumbnailFromImageAlways] = true
            if let full = CGImageSourceCreateThumbnailAtIndex(src, 0, options as CFDictionary) { thumb = full }
        }
        // La miniatura embebida puede ser mayor que lo pedido: la ajustamos.
        if max(thumb.width, thumb.height) > maxPixelSize {
            return thumb.resized(to: thumb.sizeFitting(maxDimension: maxPixelSize))
        }
        return thumb
    }
}
