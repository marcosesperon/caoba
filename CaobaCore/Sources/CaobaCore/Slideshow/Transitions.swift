import Foundation
import CoreImage
import CoreImage.CIFilterBuiltins

/// Composición de una transición entre dos fotogramas del tamaño del lienzo.
public enum Transitions {
    /// Aceleración suave en los extremos.
    static func ease(_ p: Double) -> Double {
        let x = min(1, max(0, p))
        return x * x * (3 - 2 * x)
    }

    /// `from` es el fotograma que sale (`nil` = negro) y `to` el que entra;
    /// `progress` va de 0 (solo se ve `from`) a 1 (solo `to`).
    public static func compose(from: CIImage?, to: CIImage, kind: TransitionKind, progress: Double, size: PixelSize) -> CIImage {
        let canvas = CGRect(x: 0, y: 0, width: size.width, height: size.height)
        let black = CIImage(color: .black).cropped(to: canvas)
        let outgoing = from ?? black
        let p = min(1, max(0, progress))
        let e = ease(p)
        let w = Double(size.width), h = Double(size.height)

        switch kind {
        case .cut:
            return to
        case .crossfade:
            return dissolve(outgoing, to, p, canvas: canvas)
        case .fadeToBlack:
            // Primera mitad: la que sale se apaga; segunda: la que entra se enciende.
            if p < 0.5 { return alpha(outgoing, 1 - 2 * p).composited(over: black).cropped(to: canvas) }
            return alpha(to, 2 * p - 1).composited(over: black).cropped(to: canvas)
        case .slideLeft:
            return push(outgoing, to, dx: -w, dy: 0, e: e, black: black, canvas: canvas)
        case .slideRight:
            return push(outgoing, to, dx: w, dy: 0, e: e, black: black, canvas: canvas)
        case .slideUp:
            return push(outgoing, to, dx: 0, dy: h, e: e, black: black, canvas: canvas)
        case .slideDown:
            return push(outgoing, to, dx: 0, dy: -h, e: e, black: black, canvas: canvas)
        case .zoomCross:
            // La que sale se agranda mientras se disuelve en la que entra.
            let grown = scaled(outgoing, by: 1 + 0.25 * e, canvas: canvas).composited(over: black).cropped(to: canvas)
            return dissolve(grown, to, e, canvas: canvas)
        case .wipeLeft:
            // El borde avanza hacia la izquierda: la nueva se descubre desde la derecha.
            let rect = CGRect(x: w * (1 - e), y: 0, width: w * e, height: h)
            return to.cropped(to: rect).composited(over: outgoing).cropped(to: canvas)
        case .wipeRight:
            let rect = CGRect(x: 0, y: 0, width: w * e, height: h)
            return to.cropped(to: rect).composited(over: outgoing).cropped(to: canvas)
        }
    }

    private static func dissolve(_ a: CIImage, _ b: CIImage, _ t: Double, canvas: CGRect) -> CIImage {
        let filter = CIFilter.dissolveTransition()
        filter.inputImage = a
        filter.targetImage = b
        filter.time = Float(t)
        return (filter.outputImage ?? b).cropped(to: canvas)
    }

    private static func alpha(_ image: CIImage, _ a: Double) -> CIImage {
        image.applyingFilter("CIColorMatrix", parameters: ["inputAVector": CIVector(x: 0, y: 0, z: 0, w: CGFloat(min(1, max(0, a))))])
    }

    /// La nueva empuja a la anterior en la dirección (dx, dy) del lienzo.
    private static func push(_ outgoing: CIImage, _ incoming: CIImage, dx: Double, dy: Double, e: Double, black: CIImage, canvas: CGRect) -> CIImage {
        let old = outgoing.transformed(by: CGAffineTransform(translationX: dx * e, y: dy * e))
        let new = incoming.transformed(by: CGAffineTransform(translationX: -dx * (1 - e), y: -dy * (1 - e)))
        return new.composited(over: old.composited(over: black)).cropped(to: canvas)
    }

    private static func scaled(_ image: CIImage, by factor: Double, canvas: CGRect) -> CIImage {
        let cx = canvas.midX, cy = canvas.midY
        let transform = CGAffineTransform(translationX: cx, y: cy).scaledBy(x: factor, y: factor).translatedBy(x: -cx, y: -cy)
        return image.transformed(by: transform)
    }
}
