import Foundation
import CoreGraphics

/// Posición de una marca de agua o logo sobre la imagen.
public enum OverlayPosition: String, Sendable, Codable, CaseIterable {
    case topLeft = "top_left"
    case topRight = "top_right"
    case center
    case bottomLeft = "bottom_left"
    case bottomRight = "bottom_right"

    /// Origen (arriba-izquierda) para un elemento de `size` dentro de un lienzo de `canvas`.
    public func origin(for size: PixelSize, in canvas: PixelSize, padding: Int = 10) -> CGPoint {
        switch self {
        case .topLeft: return CGPoint(x: padding, y: padding)
        case .topRight: return CGPoint(x: canvas.width - size.width - padding, y: padding)
        case .center: return CGPoint(x: (canvas.width - size.width) / 2, y: (canvas.height - size.height) / 2)
        case .bottomLeft: return CGPoint(x: padding, y: canvas.height - size.height - padding)
        case .bottomRight: return CGPoint(x: canvas.width - size.width - padding, y: canvas.height - size.height - padding)
        }
    }
}

/// Opciones de marca de agua.
public struct WatermarkOptions: Sendable, Equatable {
    public enum Mode: String, Sendable, Codable, CaseIterable { case single, tiled }
    public enum SpacingUnit: String, Sendable, Codable, CaseIterable { case pixels = "px", percent }

    public var mode: Mode
    public var position: OverlayPosition
    /// Ancho de la marca como porcentaje del lado corto de la imagen.
    public var sizePercent: Double
    /// Opacidad 0-100.
    public var opacity: Double
    /// Separación entre repeticiones en modo mosaico.
    public var spacing: Double
    public var spacingUnit: SpacingUnit
    /// Giro en grados de cada repetición (modo mosaico).
    public var rotation: Double

    public init(mode: Mode = .single, position: OverlayPosition = .bottomRight, sizePercent: Double = 20,
                opacity: Double = 80, spacing: Double = 100, spacingUnit: SpacingUnit = .pixels, rotation: Double = 0) {
        self.mode = mode
        self.position = position
        self.sizePercent = sizePercent
        self.opacity = opacity
        self.spacing = spacing
        self.spacingUnit = spacingUnit
        self.rotation = rotation
    }
}

/// Aplica una marca de agua PNG a una imagen, suelta o en mosaico.
public struct Watermarker: Sendable {
    public init() {}

    /// Parte pura: compone la marca sobre la imagen y devuelve el resultado.
    public static func apply(_ watermark: CGImage, to image: CGImage, options: WatermarkOptions) -> CGImage {
        let canvas = image.pixelSize
        let shortSide = min(canvas.width, canvas.height)
        let targetW = Int((Double(shortSide) * options.sizePercent / 100).rounded())
        guard targetW >= 1, watermark.width > 0 else { return image }
        let targetH = max(1, Int((Double(targetW) / Double(watermark.width) * Double(watermark.height)).rounded()))
        let markSize = PixelSize(width: targetW, height: targetH)

        guard let ctx = CGContext.rgba(width: canvas.width, height: canvas.height, colorSpace: image.colorSpace) else { return image }
        ctx.interpolationQuality = .high
        ctx.draw(image, in: CGRect(x: 0, y: 0, width: canvas.width, height: canvas.height))
        ctx.setAlpha(CGFloat(min(100, max(0, options.opacity)) / 100))

        switch options.mode {
        case .single:
            let origin = options.position.origin(for: markSize, in: canvas)
            drawMark(watermark, in: ctx, topLeft: origin, size: markSize, canvasHeight: canvas.height, rotationDegrees: 0)
        case .tiled:
            let spacingPx: Double
            switch options.spacingUnit {
            case .pixels: spacingPx = options.spacing
            case .percent: spacingPx = Double(shortSide) * options.spacing / 100
            }
            // Rejilla centrada en la imagen, con una fila/columna extra por cada
            // lado para que los bordes no queden vacíos al girar.
            let stepX = Double(markSize.width) + spacingPx
            let stepY = Double(markSize.height) + spacingPx
            let cols = Int(ceil(Double(canvas.width) / stepX)) + 2
            let rows = Int(ceil(Double(canvas.height) / stepY)) + 2
            let gridW = Double(cols) * stepX - spacingPx
            let gridH = Double(rows) * stepY - spacingPx
            let offsetX = (Double(canvas.width) - gridW) / 2
            let offsetY = (Double(canvas.height) - gridH) / 2
            for row in 0..<rows {
                for col in 0..<cols {
                    let x = offsetX + Double(col) * stepX
                    let y = offsetY + Double(row) * stepY
                    drawMark(watermark, in: ctx, topLeft: CGPoint(x: x, y: y), size: markSize,
                             canvasHeight: canvas.height, rotationDegrees: options.rotation)
                }
            }
        }
        return ctx.makeImage() ?? image
    }

    /// Dibuja la marca con origen arriba-izquierda y giro sobre su centro.
    private static func drawMark(_ mark: CGImage, in ctx: CGContext, topLeft: CGPoint, size: PixelSize,
                                 canvasHeight: Int, rotationDegrees: Double) {
        // Core Graphics tiene el origen abajo-izquierda: convertimos la Y.
        let centerX = topLeft.x + Double(size.width) / 2
        let centerY = Double(canvasHeight) - (topLeft.y + Double(size.height) / 2)
        ctx.saveGState()
        ctx.translateBy(x: centerX, y: centerY)
        if rotationDegrees != 0 {
            ctx.rotate(by: CGFloat(rotationDegrees * .pi / 180))
        }
        ctx.draw(mark, in: CGRect(x: -Double(size.width) / 2, y: -Double(size.height) / 2,
                                  width: Double(size.width), height: Double(size.height)))
        ctx.restoreGState()
    }

    /// Procesa una lista de ficheros. El formato de salida es el del original
    /// (la app antigua forzaba JPEG aunque fuera PNG).
    public func process(files: [URL], watermark watermarkURL: URL, options: WatermarkOptions,
                        saveMode: SaveMode, quality: Int = 95, progress: ProgressHandler? = nil) async throws -> BatchSummary {
        guard !files.isEmpty else { throw CaobaError.noFiles }
        let mark = try ImageIOHelpers.loadImage(from: watermarkURL)
        var summary = BatchSummary()
        for (index, file) in files.enumerated() {
            try Task.checkCaobaCancellation()
            progress?(.step(index, of: files.count, phase: .watermarking, file: file.lastPathComponent))
            do {
                let image = try ImageIOHelpers.loadImage(from: file)
                let result = Self.apply(mark, to: image, options: options)
                let encoding = ImageEncoding(format: OutputFormat.matching(extensionOf: file), quality: quality)
                let metadata = ImageWriter.carriedMetadata(from: ImageIOHelpers.properties(of: file))
                let output = saveMode.outputURL(for: file, sameFolderSuffix: "_watermarked")
                try ImageWriter.write(result, to: output, encoding: encoding, metadata: metadata)
                summary.processed += 1
            } catch let error as CaobaError where error == .cancelled {
                throw error
            } catch {
                summary.failures.append("\(file.lastPathComponent): \(error)")
            }
        }
        progress?(.step(files.count, of: files.count, phase: .watermarking))
        return summary
    }

    /// Vista previa sobre un fichero, reducida para pantalla.
    public func preview(file: URL, watermark watermarkURL: URL, options: WatermarkOptions, maxDimension: Int = 1200) throws -> CGImage {
        let mark = try ImageIOHelpers.loadImage(from: watermarkURL)
        let image = try ImageIOHelpers.loadImage(from: file)
        let reduced = image.resized(to: image.sizeFitting(maxDimension: maxDimension)) ?? image
        return Self.apply(mark, to: reduced, options: options)
    }
}
