import Foundation
import CoreGraphics
import Vision

/// Cómo decidir dónde está "lo importante" de una foto para recortarla.
public enum FocusMode: String, Sendable, Codable, CaseIterable {
    /// Centro de la imagen.
    case center
    /// Saliencia por atención de Vision (equivale al `attention` de libvips).
    case saliency
    /// Caras: centro del rectángulo que engloba todas las caras; si no hay, saliencia.
    case faces
}

/// Resultado de la detección: punto normalizado (0-1, origen arriba-izquierda),
/// si se encontraron caras y, cuando se sabe, la caja que engloba al sujeto
/// (todas las caras o todos los objetos salientes).
public struct FocusResult: Sendable, Equatable {
    public var point: CGPoint
    public var hasFaces: Bool
    public var faceCount: Int
    public var subject: CGRect?

    public init(point: CGPoint, hasFaces: Bool, faceCount: Int, subject: CGRect? = nil) {
        self.point = point
        self.hasFaces = hasFaces
        self.faceCount = faceCount
        self.subject = subject
    }

    public static let center = FocusResult(point: CGPoint(x: 0.5, y: 0.5), hasFaces: false, faceCount: 0)
}

/// Detección de puntos de foco con Vision, con caché por fichero y modo.
/// Trabaja sobre una versión reducida (1024 px) de la foto: suficiente para
/// saliencia y caras, y mucho más rápido que decodificar el original.
public actor FocusDetector {
    private var cache: [String: FocusResult] = [:]
    private let semaphore = AsyncSemaphore(limit: max(2, ProcessInfo.processInfo.activeProcessorCount / 2))

    public init() {}

    public func focus(for url: URL, mode: FocusMode) async -> FocusResult {
        guard mode != .center else { return .center }
        let key = "\(url.path)|\(mode.rawValue)"
        if let cached = cache[key] { return cached }
        let result = await semaphore.run { Self.detect(url: url, mode: mode) }
        cache[key] = result
        return result
    }

    public func clear() { cache = [:] }

    /// Detección sin caché (estática para poder testearla).
    public static func detect(url: URL, mode: FocusMode) -> FocusResult {
        guard mode != .center, let image = ThumbnailProvider.makeThumbnail(url: url, maxPixelSize: 1024) else { return .center }
        return detect(image: image, mode: mode)
    }

    public static func detect(image: CGImage, mode: FocusMode) -> FocusResult {
        switch mode {
        case .center:
            return .center
        case .saliency:
            return saliency(image) ?? .center
        case .faces:
            if let faces = faces(image) { return faces }
            return saliency(image) ?? .center
        }
    }

    /// Vision devuelve rectángulos normalizados con origen abajo-izquierda;
    /// nosotros trabajamos con origen arriba-izquierda, así que invertimos la Y.
    /// Devuelve la caja que engloba todas las cajas, ya volteada.
    private static func union(of boxes: [CGRect]) -> CGRect? {
        guard let first = boxes.first else { return nil }
        let union = boxes.dropFirst().reduce(first) { $0.union($1) }
        return CGRect(x: union.minX, y: 1 - union.maxY, width: union.width, height: union.height)
    }

    private static func faces(_ image: CGImage) -> FocusResult? {
        let request = VNDetectFaceRectanglesRequest()
        let handler = VNImageRequestHandler(cgImage: image, orientation: .up)
        guard (try? handler.perform([request])) != nil, let faces = request.results, !faces.isEmpty,
              let box = union(of: faces.map(\.boundingBox)) else { return nil }
        return FocusResult(point: CGPoint(x: box.midX, y: box.midY), hasFaces: true, faceCount: faces.count, subject: box)
    }

    /// Saliencia: primero "objectness" (dónde está el sujeto), que localiza
    /// mejor para recortar; si no encuentra objetos, el centroide del mapa de
    /// atención (sesgado al centro pero siempre devuelve algo).
    private static func saliency(_ image: CGImage) -> FocusResult? {
        let objectness = VNGenerateObjectnessBasedSaliencyImageRequest()
        let handler = VNImageRequestHandler(cgImage: image, orientation: .up)
        if (try? handler.perform([objectness])) != nil,
           let observation = objectness.results?.first,
           let objects = observation.salientObjects, !objects.isEmpty {
            // Centro ponderado por confianza de los objetos detectados.
            let total = objects.reduce(0.0) { $0 + Double($1.confidence) }
            if total > 0 {
                let x = objects.reduce(0.0) { $0 + Double($1.confidence) * $1.boundingBox.midX } / total
                let y = objects.reduce(0.0) { $0 + Double($1.confidence) * $1.boundingBox.midY } / total
                return FocusResult(point: CGPoint(x: x, y: 1 - y), hasFaces: false, faceCount: 0,
                                   subject: union(of: objects.map(\.boundingBox)))
            }
        }
        let attention = VNGenerateAttentionBasedSaliencyImageRequest()
        guard (try? handler.perform([attention])) != nil,
              let observation = attention.results?.first,
              let point = heatmapCentroid(observation.pixelBuffer) else { return nil }
        return FocusResult(point: point, hasFaces: false, faceCount: 0)
    }

    /// Centroide del mapa de calor (filas de arriba abajo, como la imagen).
    private static func heatmapCentroid(_ buffer: CVPixelBuffer) -> CGPoint? {
        CVPixelBufferLockBaseAddress(buffer, .readOnly)
        defer { CVPixelBufferUnlockBaseAddress(buffer, .readOnly) }
        guard let base = CVPixelBufferGetBaseAddress(buffer) else { return nil }
        let width = CVPixelBufferGetWidth(buffer), height = CVPixelBufferGetHeight(buffer)
        let stride = CVPixelBufferGetBytesPerRow(buffer) / MemoryLayout<Float>.size
        let values = base.assumingMemoryBound(to: Float.self)
        var sum = 0.0, sx = 0.0, sy = 0.0
        for y in 0..<height {
            for x in 0..<width {
                let v = Double(max(0, values[y * stride + x]))
                sum += v; sx += v * Double(x); sy += v * Double(y)
            }
        }
        guard sum > 0 else { return nil }
        return CGPoint(x: (sx / sum + 0.5) / Double(width), y: (sy / sum + 0.5) / Double(height))
    }
}
