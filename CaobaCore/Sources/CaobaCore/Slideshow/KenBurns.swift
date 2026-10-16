import Foundation
import CoreGraphics

/// Efectos Ken Burns. Los `rawValue` coinciden con la app antigua.
public enum KenBurnsEffect: String, Sendable, Codable, CaseIterable {
    case zoomIn = "zoom_in", zoomOut = "zoom_out"
    case panLeft = "pan_left", panRight = "pan_right", panUp = "pan_up", panDown = "pan_down"
    case panUpLeft = "pan_up_left", panUpRight = "pan_up_right", panDownLeft = "pan_down_left", panDownRight = "pan_down_right"
    /// Puntos de inicio y fin definidos por el usuario.
    case custom

    /// Los que se eligen al azar (sin diagonales ni custom, como antes).
    public static let randomPool: [KenBurnsEffect] = [.zoomIn, .zoomOut, .panLeft, .panRight, .panUp, .panDown]
}

public enum KenBurnsEasing: String, Sendable, Codable, CaseIterable {
    case linear, easeIn = "ease_in", easeOut = "ease_out", easeInOut = "ease_in_out"

    public func apply(_ t: Double) -> Double {
        switch self {
        case .linear: return t
        case .easeIn: return t * t
        case .easeOut: return t * (2 - t)
        case .easeInOut: return t < 0.5 ? 2 * t * t : -1 + (4 - 2 * t) * t
        }
    }
}

public enum KenBurnsIntensity: String, Sendable, Codable, CaseIterable {
    case slow, normal, fast

    /// Margen de movimiento como fracción del recorte base.
    public var margin: Double {
        switch self {
        case .slow: return 0.04
        case .normal: return 0.07
        case .fast: return 0.12
        }
    }
}

/// Ajustes globales de Ken Burns.
public struct KenBurnsSettings: Sendable, Equatable, Codable {
    public var intensity: KenBurnsIntensity
    public var easing: KenBurnsEasing
    /// Porcentaje del tiempo de la foto durante el que se mueve (20-100); el resto queda quieta al final.
    public var durationPercent: Double

    public init(intensity: KenBurnsIntensity = .normal, easing: KenBurnsEasing = .easeInOut, durationPercent: Double = 50) {
        self.intensity = intensity
        self.easing = easing
        self.durationPercent = min(100, max(20, durationPercent))
    }
}

/// Puntos de inicio y fin de un efecto personalizado (foco normalizado + zoom 1-2),
/// o solo el foco para los efectos automáticos.
public struct KenBurnsPoints: Sendable, Equatable, Codable {
    public enum Fit: String, Sendable, Codable { case cover, contain }

    public var startFocus: CGPoint
    public var startZoom: Double
    public var endFocus: CGPoint
    public var endZoom: Double
    public var fit: Fit
    /// Porcentaje del tiempo que la foto espera quieta antes de moverse (0-80).
    public var delayPercent: Double

    public init(startFocus: CGPoint = CGPoint(x: 0.5, y: 0.5), startZoom: Double = 1, endFocus: CGPoint = CGPoint(x: 0.5, y: 0.5),
                endZoom: Double = 1, fit: Fit = .cover, delayPercent: Double = 0) {
        self.startFocus = startFocus
        self.startZoom = min(2, max(1, startZoom))
        self.endFocus = endFocus
        self.endZoom = min(2, max(1, endZoom))
        self.fit = fit
        self.delayPercent = min(80, max(0, delayPercent))
    }

    /// Si los puntos difieren del centro sin zoom (es decir, si hay algo que animar).
    public var isCustomized: Bool {
        startFocus != CGPoint(x: 0.5, y: 0.5) || endFocus != CGPoint(x: 0.5, y: 0.5) || startZoom != 1 || endZoom != 1
    }
}

/// Geometría Ken Burns: dado el instante, qué trozo de la foto se muestra.
/// Es la misma matemática de la app antigua (`kenburns.js`), en coordenadas de
/// píxel con origen arriba-izquierda.
public enum KenBurns {

    /// Progreso 0-1 del efecto en el instante `t` de una foto de `duration`
    /// segundos, con retardo inicial, porcentaje de duración y easing.
    public static func progress(time t: Double, duration: Double, durationPercent: Double, delayPercent: Double, easing: KenBurnsEasing) -> Double {
        guard duration > 0 else { return 1 }
        let delay = duration * min(80, max(0, delayPercent)) / 100
        let effectDuration = (duration - delay) * min(100, max(20, durationPercent)) / 100
        guard t > delay else { return easing.apply(0) }
        guard effectDuration > 0 else { return easing.apply(1) }
        return easing.apply(min(1, (t - delay) / effectDuration))
    }

    /// Recorte para un efecto automático en el progreso `t` (0-1).
    public static func cropRect(imageSize: PixelSize, targetSize: PixelSize, effect: KenBurnsEffect, t: Double,
                                intensity: KenBurnsIntensity, focus: CGPoint, zoom: Double = 1) -> CGRect {
        let imgW = Double(imageSize.width), imgH = Double(imageSize.height)
        let pct = intensity.margin
        let targetAspect = Double(targetSize.width) / Double(targetSize.height)

        // Recorte base: el mayor rectángulo con la proporción del vídeo que cabe en la foto.
        var baseW: Double, baseH: Double
        if imgW / imgH > targetAspect { baseH = imgH; baseW = (imgH * targetAspect).rounded() }
        else { baseW = imgW; baseH = (imgW / targetAspect).rounded() }

        // Margen de movimiento y recorte interior (más pequeño para poder moverse).
        let marginX = (baseW * pct).rounded(), marginY = (baseH * pct).rounded()
        var cropW = baseW - marginX * 2, cropH = baseH - marginY * 2
        if zoom > 1 { cropW = (cropW / zoom).rounded(); cropH = (cropH / zoom).rounded() }

        let fx = focus.x * imgW, fy = focus.y * imgH
        let centerX = min(max(0, (fx - cropW / 2).rounded(.down)), imgW - cropW)
        let centerY = min(max(0, (fy - cropH / 2).rounded(.down)), imgH - cropH)

        var left = centerX, top = centerY, width = cropW, height = cropH
        switch effect {
        case .zoomIn, .zoomOut:
            let big = (cropW + marginX * 2, cropH + marginY * 2)
            let (fromW, fromH, toW, toH) = effect == .zoomIn ? (big.0, big.1, cropW, cropH) : (cropW, cropH, big.0, big.1)
            width = (fromW + (toW - fromW) * t).rounded(.down)
            height = (fromH + (toH - fromH) * t).rounded(.down)
            if width.truncatingRemainder(dividingBy: 2) != 0 { width -= 1 }
            if height.truncatingRemainder(dividingBy: 2) != 0 { height -= 1 }
            left = min(max(0, (fx - width / 2).rounded(.down)), imgW - width)
            top = min(max(0, (fy - height / 2).rounded(.down)), imgH - height)
        case .panLeft: left = centerX + marginX * (1 - t)
        case .panRight: left = centerX - marginX + marginX * t
        case .panUp: top = centerY + marginY * (1 - t)
        case .panDown: top = centerY - marginY + marginY * t
        case .panUpLeft: left = centerX + marginX * (1 - t); top = centerY + marginY * (1 - t)
        case .panUpRight: left = centerX - marginX + marginX * t; top = centerY + marginY * (1 - t)
        case .panDownLeft: left = centerX + marginX * (1 - t); top = centerY - marginY + marginY * t
        case .panDownRight: left = centerX - marginX + marginX * t; top = centerY - marginY + marginY * t
        case .custom: break
        }

        left = min(max(0, left.rounded(.down)), imgW - width)
        top = min(max(0, top.rounded(.down)), imgH - height)
        width = min(width, imgW - left)
        height = min(height, imgH - top)
        return CGRect(x: left, y: top, width: width, height: height)
    }

    /// Recorte en el progreso `t` para un efecto personalizado: interpola foco y zoom.
    public static func customCropRect(imageSize: PixelSize, targetSize: PixelSize, points: KenBurnsPoints, t: Double) -> CGRect {
        let focus = CGPoint(x: points.startFocus.x + (points.endFocus.x - points.startFocus.x) * t,
                            y: points.startFocus.y + (points.endFocus.y - points.startFocus.y) * t)
        let zoom = points.startZoom + (points.endZoom - points.startZoom) * t
        // Con zoom 1 se ve el máximo encuadre; sin margen de movimiento extra.
        let imgW = Double(imageSize.width), imgH = Double(imageSize.height)
        let targetAspect = Double(targetSize.width) / Double(targetSize.height)
        var w: Double, h: Double
        if imgW / imgH > targetAspect { h = imgH; w = (imgH * targetAspect).rounded() } else { w = imgW; h = (imgW / targetAspect).rounded() }
        w = (w / zoom).rounded(); h = (h / zoom).rounded()
        let left = min(max(0, (focus.x * imgW - w / 2).rounded()), imgW - w)
        let top = min(max(0, (focus.y * imgH - h / 2).rounded()), imgH - h)
        return CGRect(x: left, y: top, width: w, height: h)
    }

    /// Recorte definitivo para una foto del slideshow en el instante `t` de su segmento.
    public static func cropRect(for photo: SlideshowPhoto, imageSize: PixelSize, targetSize: PixelSize, time t: Double,
                                segmentDuration: Double, settings: KenBurnsSettings) -> CGRect? {
        guard let effect = photo.kenBurns else { return nil }
        let easing = photo.easing ?? settings.easing
        let delay = photo.points?.delayPercent ?? 0
        let p = progress(time: t, duration: segmentDuration, durationPercent: settings.durationPercent, delayPercent: delay, easing: easing)
        if effect == .custom, let points = photo.points {
            return customCropRect(imageSize: imageSize, targetSize: targetSize, points: points, t: p)
        }
        let focus = photo.points?.startFocus ?? CGPoint(x: 0.5, y: 0.5)
        return cropRect(imageSize: imageSize, targetSize: targetSize, effect: effect, t: p, intensity: settings.intensity, focus: focus)
    }

    /// Elige un efecto que encaje con la proporción de la foto frente a la del
    /// vídeo: si sobra ancho, barrido horizontal; si sobra alto, vertical; si
    /// coinciden, zoom. Es lo que hacía "Asignar → foco automático".
    public static func suggestedEffect(imageAspect: Double, videoAspect: Double, generator: inout some RandomNumberGenerator) -> KenBurnsEffect {
        let ratio = imageAspect / videoAspect
        if ratio > 1.15 { return Bool.random(using: &generator) ? .panLeft : .panRight }
        if ratio < 0.87 { return Bool.random(using: &generator) ? .panUp : .panDown }
        return Bool.random(using: &generator) ? .zoomIn : .zoomOut
    }
}
