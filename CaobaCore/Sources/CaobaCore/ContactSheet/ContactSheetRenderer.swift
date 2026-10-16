import Foundation
import CoreGraphics

/// Opciones de la hoja de contactos.
public struct ContactSheetOptions: Sendable, Equatable {
    public enum Layout: String, Sendable, Codable, CaseIterable { case grid, masonry }
    public enum CropMode: String, Sendable, Codable, CaseIterable { case contain, cover }

    public var columns: Int
    /// Lado de la miniatura (grid) o ancho de columna (masonry), en píxeles.
    public var thumbSize: Int
    public var layout: Layout
    public var cropMode: CropMode
    public var showFilenames: Bool
    public var showNumbering: Bool
    public var title: String
    public var background: CanvasBackground
    public var showBorder: Bool
    public var borderWidth: Double
    public var logo: LogoOptions?
    public var quality: Int

    public static let maxDimension = 30_000
    static let cellPadding = 10.0
    static let labelHeight = 20.0
    static let titleHeight = 40.0

    public init(columns: Int = 5, thumbSize: Int = 200, layout: Layout = .grid, cropMode: CropMode = .contain,
                showFilenames: Bool = true, showNumbering: Bool = false, title: String = "", background: CanvasBackground = .white,
                showBorder: Bool = false, borderWidth: Double = 1, logo: LogoOptions? = nil, quality: Int = 90) {
        self.columns = max(1, columns)
        self.thumbSize = max(20, thumbSize)
        self.layout = layout
        self.cropMode = cropMode
        self.showFilenames = showFilenames
        self.showNumbering = showNumbering
        self.title = title
        self.background = background
        self.showBorder = showBorder
        self.borderWidth = max(1, borderWidth)
        self.logo = logo
        self.quality = quality
    }

    var showLabels: Bool { showFilenames || showNumbering }
    var titleOffset: Double { title.trimmingCharacters(in: .whitespaces).isEmpty ? 0 : Self.titleHeight }
}

/// Hoja de contactos en rejilla o en masonry.
public enum ContactSheetRenderer {

    /// Posiciones de cada miniatura y tamaño del lienzo.
    public struct LayoutResult: Sendable, Equatable {
        public var canvas: PixelSize
        public var frames: [CGRect]
    }

    /// Dimensiones estimadas sin leer ninguna foto (solo válido para grid; en
    /// masonry la altura depende de las fotos).
    public static func estimatedSize(fileCount: Int, options: ContactSheetOptions) -> PixelSize {
        let rows = Int(ceil(Double(fileCount) / Double(options.columns)))
        let cellW = Double(options.thumbSize) + ContactSheetOptions.cellPadding * 2
        let cellH = Double(options.thumbSize) + ContactSheetOptions.cellPadding * 2 + (options.showLabels ? ContactSheetOptions.labelHeight : 0)
        return PixelSize(width: Int(Double(options.columns) * cellW + ContactSheetOptions.cellPadding),
                         height: Int(Double(rows) * cellH + ContactSheetOptions.cellPadding + options.titleOffset))
    }

    /// Calcula la disposición. Para masonry necesita las proporciones de las fotos.
    public static func layout(fileCount: Int, aspects: [Double], options: ContactSheetOptions) throws -> LayoutResult {
        let pad = ContactSheetOptions.cellPadding
        let label = options.showLabels ? ContactSheetOptions.labelHeight : 0
        let thumb = Double(options.thumbSize)
        var frames: [CGRect] = []
        let canvas: PixelSize

        switch options.layout {
        case .grid:
            let size = estimatedSize(fileCount: fileCount, options: options)
            let cellW = thumb + pad * 2
            let cellH = thumb + pad * 2 + label
            for i in 0..<fileCount {
                let col = i % options.columns, row = i / options.columns
                frames.append(CGRect(x: pad + Double(col) * cellW + pad, y: options.titleOffset + pad + Double(row) * cellH + pad, width: thumb, height: thumb))
            }
            canvas = size
        case .masonry:
            // Ancho fijo por columna, altura proporcional, sin huecos: cada foto
            // va a la columna más corta.
            var heights = Array(repeating: options.titleOffset, count: options.columns)
            for i in 0..<fileCount {
                let aspect = aspects.indices.contains(i) ? max(0.05, aspects[i]) : 1
                let h = (thumb / aspect).rounded()
                let col = heights.indices.min { heights[$0] < heights[$1] }!
                frames.append(CGRect(x: Double(col) * thumb, y: heights[col], width: thumb, height: h))
                heights[col] += h + label
            }
            canvas = PixelSize(width: options.columns * options.thumbSize, height: Int((heights.max() ?? 0).rounded(.up)))
        }

        guard canvas.width <= ContactSheetOptions.maxDimension, canvas.height <= ContactSheetOptions.maxDimension else {
            throw CaobaError.invalidParameters("contactsheet.size")
        }
        return LayoutResult(canvas: canvas, frames: frames)
    }

    /// Etiqueta de una miniatura, acortada como hacía la app antigua.
    public static func label(for url: URL, index: Int, options: ContactSheetOptions) -> String? {
        let base = url.deletingPathExtension().lastPathComponent
        let number = "\(index + 1)"
        func truncate(_ s: String, _ max: Int) -> String { s.count > max ? String(s.prefix(max - 3)) + "..." : s }
        switch (options.showFilenames, options.showNumbering) {
        case (true, true): return "\(number). " + truncate(base, 20)
        case (false, true): return number
        case (true, false): return truncate(base, 25)
        case (false, false): return nil
        }
    }

    /// Genera la hoja y la devuelve como imagen.
    public static func render(files: [URL], options: ContactSheetOptions, progress: ProgressHandler? = nil) throws -> CGImage {
        guard !files.isEmpty else { throw CaobaError.noFiles }
        var aspects: [Double] = []
        if options.layout == .masonry {
            for (i, url) in files.enumerated() {
                try Task.checkCaobaCancellation()
                progress?(JobProgress(phase: .readingMetadata, fraction: Double(i) / Double(files.count) * 0.3, currentFile: url.lastPathComponent))
                aspects.append(ImageIOHelpers.displaySize(of: url)?.aspectRatio ?? 1)
            }
        }
        let layout = try layout(fileCount: files.count, aspects: aspects, options: options)
        let ctx = try Drawing.makeCanvas(layout.canvas, background: options.background.fill)
        let base = options.layout == .masonry ? 0.3 : 0.0

        for (i, url) in files.enumerated() {
            try Task.checkCaobaCancellation()
            progress?(JobProgress(phase: .generatingContactSheet, fraction: base + Double(i) / Double(files.count) * (1 - base), currentFile: url.lastPathComponent))
            let frame = layout.frames[i]
            let photo = try PhotoLoader.load(url, fittingAtLeast: PixelSize(width: Int(frame.width), height: Int(frame.height)))
            let target: CGRect
            let crop: CGRect
            if options.layout == .masonry || options.cropMode == .cover {
                target = frame
                crop = CropGeometry.rect(in: photo.pixelSize, ratio: frame.width / frame.height, focus: CGPoint(x: 0.5, y: 0.5))
            } else {
                // contain: la foto entera, centrada en la celda.
                let scale = min(frame.width / Double(photo.width), frame.height / Double(photo.height))
                let w = (Double(photo.width) * scale).rounded(), h = (Double(photo.height) * scale).rounded()
                target = CGRect(x: frame.midX - w / 2, y: frame.midY - h / 2, width: w, height: h)
                crop = CGRect(x: 0, y: 0, width: photo.width, height: photo.height)
            }
            Drawing.drawImage(photo, crop: crop, into: target, cornerRadius: 0, in: ctx, canvasHeight: layout.canvas.height)
            if options.showBorder {
                Drawing.strokeRect(target, color: options.background.border, width: options.borderWidth, in: ctx, canvasHeight: layout.canvas.height)
            }
            if let text = label(for: url, index: i, options: options) {
                Drawing.drawText(text, centeredAt: CGPoint(x: frame.midX, y: frame.maxY + 16), fontSize: 11, bold: false,
                                 color: options.background.text, maxWidth: frame.width, in: ctx, canvasHeight: layout.canvas.height)
            }
        }

        if options.titleOffset > 0 {
            Drawing.drawText(options.title.trimmingCharacters(in: .whitespaces),
                             centeredAt: CGPoint(x: Double(layout.canvas.width) / 2, y: ContactSheetOptions.titleHeight - 12),
                             fontSize: 18, bold: true, color: options.background.text,
                             maxWidth: Double(layout.canvas.width) - 20, in: ctx, canvasHeight: layout.canvas.height)
        }
        if let logo = options.logo {
            try Drawing.drawLogo(logo, in: ctx, canvas: layout.canvas)
        }
        guard let image = ctx.makeImage() else { throw CaobaError.invalidParameters("contactsheet.render") }
        return image
    }

    /// Genera y guarda la hoja en `output` (JPEG).
    public static func generate(files: [URL], options: ContactSheetOptions, output: URL, progress: ProgressHandler? = nil) async throws -> BatchSummary {
        let image = try render(files: files, options: options, progress: progress)
        try ImageWriter.write(image, to: output, encoding: ImageEncoding(format: .jpeg, quality: options.quality))
        progress?(.step(1, of: 1, phase: .generatingContactSheet))
        return BatchSummary(processed: files.count)
    }
}
