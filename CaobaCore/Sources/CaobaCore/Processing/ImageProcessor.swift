import Foundation
import CoreGraphics
import ImageIO

/// Operaciones del Procesador. Se aplican en este orden: autorrotar, recortar,
/// redimensionar, y por último formato y calidad.
public struct ProcessingOperations: Sendable, Equatable {
    public var autorotate: Bool
    public var crop: (ratio: AspectRatio, anchor: CropAnchor)?
    /// Lado mayor máximo en píxeles. No amplía nunca.
    public var resizeMaxDimension: Int?
    /// Calidad 1-100 para formatos con pérdida.
    public var quality: Int
    /// Formato de salida. `nil` mantiene el del original.
    public var format: OutputFormat?

    public init(autorotate: Bool = true, crop: (ratio: AspectRatio, anchor: CropAnchor)? = nil,
                resizeMaxDimension: Int? = nil, quality: Int = 90, format: OutputFormat? = nil) {
        self.autorotate = autorotate
        self.crop = crop
        self.resizeMaxDimension = resizeMaxDimension
        self.quality = quality
        self.format = format
    }

    public static func == (lhs: ProcessingOperations, rhs: ProcessingOperations) -> Bool {
        lhs.autorotate == rhs.autorotate
            && lhs.crop?.ratio == rhs.crop?.ratio && lhs.crop?.anchor == rhs.crop?.anchor
            && lhs.resizeMaxDimension == rhs.resizeMaxDimension
            && lhs.quality == rhs.quality && lhs.format == rhs.format
    }

    /// Si no hay ninguna operación activa no tiene sentido procesar.
    public var isEmpty: Bool {
        !autorotate && crop == nil && resizeMaxDimension == nil && format == nil
    }
}

/// Procesador por lotes: rota, recorta, redimensiona y recodifica conservando
/// EXIF, GPS y perfil de color.
public struct ImageProcessor: Sendable {
    public init() {}

    /// Aplica las operaciones a una imagen ya cargada (sin la rotación, que
    /// depende del fichero). Es la parte pura y testeable.
    public static func apply(_ ops: ProcessingOperations, to image: CGImage) throws -> CGImage {
        var result = image
        if let crop = ops.crop {
            guard let rect = CropGeometry.rect(in: result.pixelSize, ratio: crop.ratio, anchor: crop.anchor),
                  let cropped = result.croppedTopLeft(rect) else {
                throw CaobaError.invalidParameters("crop")
            }
            result = cropped
        }
        if let maxDim = ops.resizeMaxDimension, maxDim > 0 {
            let target = result.sizeFitting(maxDimension: maxDim)
            if target != result.pixelSize {
                guard let resized = result.resized(to: target) else { throw CaobaError.invalidParameters("resize") }
                result = resized
            }
        }
        return result
    }

    /// Procesa un fichero y devuelve la imagen resultante y la codificación a usar.
    public static func render(file: URL, ops: ProcessingOperations) throws -> (image: CGImage, encoding: ImageEncoding, metadata: [CFString: Any]) {
        let image = try ImageIOHelpers.loadImage(from: file, applyingOrientation: ops.autorotate)
        let processed = try apply(ops, to: image)
        let format = ops.format ?? OutputFormat.matching(extensionOf: file)
        let sourceProps = ImageIOHelpers.properties(of: file)
        var metadata = ImageWriter.carriedMetadata(from: sourceProps)
        if !ops.autorotate {
            // Si no rotamos, la orientación original sigue siendo válida y hay que conservarla.
            if let orientation = sourceProps?[kCGImagePropertyOrientation] {
                metadata[kCGImagePropertyOrientation] = orientation
            }
        }
        return (processed, ImageEncoding(format: format, quality: ops.quality), metadata)
    }

    /// Procesa una lista de ficheros.
    public func process(files: [URL], ops: ProcessingOperations, saveMode: SaveMode,
                        progress: ProgressHandler? = nil) async throws -> BatchSummary {
        guard !files.isEmpty else { throw CaobaError.noFiles }
        var summary = BatchSummary()
        for (index, file) in files.enumerated() {
            try Task.checkCaobaCancellation()
            progress?(.step(index, of: files.count, phase: .processingImages, file: file.lastPathComponent))
            do {
                let (image, encoding, metadata) = try Self.render(file: file, ops: ops)
                let changesExtension = encoding.format.fileExtension.lowercased() != file.pathExtension.lowercased()
                let output = saveMode.outputURL(for: file, sameFolderSuffix: "_processed",
                                                newExtension: changesExtension ? encoding.format.fileExtension : nil)
                try ImageWriter.write(image, to: output, encoding: encoding, metadata: metadata)
                // Al sobrescribir con otro formato, el original con la extensión vieja sobra.
                if saveMode.isOverwrite, output.standardizedFileURL != file.standardizedFileURL {
                    try? FileManager.default.removeItem(at: file)
                }
                summary.processed += 1
            } catch let error as CaobaError where error == .cancelled {
                throw error
            } catch {
                summary.failures.append("\(file.lastPathComponent): \(error)")
            }
        }
        progress?(.step(files.count, of: files.count, phase: .processingImages))
        return summary
    }

    /// Antes y después de un fichero, reducidos para mostrar en pantalla.
    public func preview(file: URL, ops: ProcessingOperations, maxDimension: Int = 800) throws -> (before: CGImage, after: CGImage) {
        let original = try ImageIOHelpers.loadImage(from: file, applyingOrientation: true)
        let before = original.resized(to: original.sizeFitting(maxDimension: maxDimension)) ?? original
        let (processed, encoding, _) = try Self.render(file: file, ops: ops)
        // Pasamos por la codificación real para que la calidad JPEG se vea en la preview.
        let data = try ImageWriter.encode(processed, encoding: encoding)
        let decoded = try ImageIOHelpers.loadImage(fromData: data)
        let after = decoded.resized(to: decoded.sizeFitting(maxDimension: maxDimension)) ?? decoded
        return (before, after)
    }
}

public extension ImageIOHelpers {
    /// Decodifica una imagen desde datos en memoria.
    static func loadImage(fromData data: Data) throws -> CGImage {
        guard let src = CGImageSourceCreateWithData(data as CFData, nil),
              let image = CGImageSourceCreateImageAtIndex(src, 0, nil) else {
            throw CaobaError.cannotReadImage("data")
        }
        return image
    }
}
