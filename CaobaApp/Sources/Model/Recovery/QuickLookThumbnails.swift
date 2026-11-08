import Foundation
import CoreGraphics
import QuickLookThumbnailing
import CaobaCore

/// Miniaturas de lo recuperado con QuickLook, que sabe hacerlas de RAW, HEIC y vídeo (el
/// `ThumbnailProvider` del motor usa ImageIO y no saca fotogramas de vídeo). Con caché y
/// un máximo de peticiones a la vez, para que miles de ficheros no saturen el Mac.
actor QuickLookThumbnails {
    private let cache = NSCache<NSURL, CGImage>()
    private let semaphore = AsyncSemaphore(limit: max(2, ProcessInfo.processInfo.activeProcessorCount / 2))

    init() {
        cache.countLimit = 1500
    }

    /// Miniatura de `size` puntos (a la escala de la pantalla). `nil` si QuickLook no sabe
    /// hacerla (fichero dañado o de un tipo sin vista previa). Si la tarea se cancela
    /// (la celda sale de la pantalla), se cancela también la petición a QuickLook.
    func thumbnail(for url: URL, size: CGFloat, scale: CGFloat) async -> CGImage? {
        if let cached = cache.object(forKey: url as NSURL) { return cached }
        let image: CGImage? = await semaphore.run {
            Task.isCancelled ? nil : await Self.generate(url: url, size: size, scale: scale)
        }
        if let image { cache.setObject(image, forKey: url as NSURL) }
        return image
    }

    /// Pide la miniatura a QuickLook y la cancela si se cancela la tarea.
    nonisolated private static func generate(url: URL, size: CGFloat, scale: CGFloat) async -> CGImage? {
        // La petición no es `Sendable`, pero QuickLook permite cancelarla desde cualquier hilo.
        nonisolated(unsafe) let request = QLThumbnailGenerator.Request(fileAt: url, size: CGSize(width: size, height: size),
                                                                       scale: scale, representationTypes: .thumbnail)
        return await withTaskCancellationHandler {
            try? await QLThumbnailGenerator.shared.generateBestRepresentation(for: request).cgImage
        } onCancel: {
            QLThumbnailGenerator.shared.cancel(request)
        }
    }
}
