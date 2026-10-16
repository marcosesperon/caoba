import Foundation
import CoreGraphics

/// Relación de aspecto como par de enteros (3:2, 16:9...).
public struct AspectRatio: Sendable, Equatable, Codable, Hashable {
    public var width: Int
    public var height: Int

    public init(_ width: Int, _ height: Int) {
        self.width = max(1, width)
        self.height = max(1, height)
    }

    public var value: Double { Double(width) / Double(height) }

    public static let square = AspectRatio(1, 1)
    public static let r4x5 = AspectRatio(4, 5)
    public static let r5x4 = AspectRatio(5, 4)
    public static let r3x2 = AspectRatio(3, 2)
    public static let r2x3 = AspectRatio(2, 3)
    public static let r16x9 = AspectRatio(16, 9)
    public static let r9x16 = AspectRatio(9, 16)
}

/// Desde dónde se recorta cuando la imagen no encaja en el ratio.
public enum CropAnchor: String, Sendable, Codable, CaseIterable {
    case center, top, bottom, left, right
}

/// Geometría de recorte, en coordenadas de píxel con origen arriba-izquierda
/// (como las piensa el usuario; la conversión a Core Graphics se hace al dibujar).
public enum CropGeometry {

    /// Rectángulo máximo con el ratio pedido dentro de la imagen, anclado.
    public static func rect(in size: PixelSize, ratio: AspectRatio, anchor: CropAnchor) -> CGRect? {
        let target = ratio.value
        let current = size.aspectRatio
        var cropW: Int
        var cropH: Int
        if current > target {
            cropH = size.height
            cropW = Int((Double(size.height) * target).rounded())
        } else {
            cropW = size.width
            cropH = Int((Double(size.width) / target).rounded())
        }
        cropW = min(cropW, size.width)
        cropH = min(cropH, size.height)
        guard cropW >= 1, cropH >= 1 else { return nil }

        let cx = (size.width - cropW) / 2
        let cy = (size.height - cropH) / 2
        let origin: (Int, Int)
        switch anchor {
        case .center: origin = (cx, cy)
        case .top: origin = (cx, 0)
        case .bottom: origin = (cx, size.height - cropH)
        case .left: origin = (0, cy)
        case .right: origin = (size.width - cropW, cy)
        }
        return CGRect(x: origin.0, y: origin.1, width: cropW, height: cropH)
    }

    /// Rectángulo del ratio pedido centrado en un punto de foco normalizado (0-1).
    /// Se usa en collage, Ken Burns y smart crop.
    public static func rect(in size: PixelSize, ratio: Double, focus: CGPoint) -> CGRect {
        var cropW: Double
        var cropH: Double
        if size.aspectRatio > ratio {
            cropH = Double(size.height)
            cropW = (cropH * ratio).rounded()
        } else {
            cropW = Double(size.width)
            cropH = (cropW / ratio).rounded()
        }
        let fx = focus.x * Double(size.width)
        let fy = focus.y * Double(size.height)
        let left = min(max(0, fx - cropW / 2), Double(size.width) - cropW)
        let top = min(max(0, fy - cropH / 2), Double(size.height) - cropH)
        return CGRect(x: left.rounded(), y: top.rounded(), width: cropW, height: cropH)
    }
}

public extension CGImage {
    /// Recorta con un rectángulo expresado con origen arriba-izquierda.
    /// `CGImage.cropping(to:)` ya usa ese mismo origen (coordenadas de píxel), así
    /// que no hace falta voltear nada.
    func croppedTopLeft(_ rect: CGRect) -> CGImage? {
        let clamped = rect.intersection(CGRect(x: 0, y: 0, width: width, height: height)).integral
        guard clamped.width >= 1, clamped.height >= 1 else { return nil }
        return cropping(to: clamped)
    }
}
