import Foundation
import CoreGraphics

/// Opciones comunes a todos los collages de una tanda.
public struct CollageOptions: Sendable, Equatable {
    /// Lado mayor del resultado en píxeles.
    public var longestSide: Int
    /// Separación entre fotos en píxeles.
    public var gap: Double
    public var background: CanvasColor
    public var cornerRadius: Double
    /// Intensidad de la sombra (0-100) en plantillas overlap.
    public var shadowIntensity: Double
    public var title: String
    public var quality: Int
    public var logo: LogoOptions?

    public static let maxDimension = 15_000

    public init(longestSide: Int = 3000, gap: Double = 10, background: CanvasColor = .white, cornerRadius: Double = 0,
                shadowIntensity: Double = 100, title: String = "", quality: Int = 90, logo: LogoOptions? = nil) {
        self.longestSide = min(CollageOptions.maxDimension, max(100, longestSide))
        self.gap = max(0, gap)
        self.background = background
        self.cornerRadius = max(0, cornerRadius)
        self.shadowIntensity = min(100, max(0, shadowIntensity))
        self.title = title
        self.quality = quality
        self.logo = logo
    }
}

/// Un collage concreto: plantilla, fotos en orden de celda y foco por celda.
public struct CollageRow: Sendable, Equatable, Identifiable {
    public var id: UUID
    public var template: CollageTemplate
    public var files: [URL]
    /// Punto de foco normalizado por celda; `nil` = centro.
    public var focusPoints: [CGPoint?]
    /// Segundos que se mantiene el collage completo en el slideshow; `nil` = valor global.
    public var hold: Double?

    public init(id: UUID = UUID(), template: CollageTemplate, files: [URL], focusPoints: [CGPoint?]? = nil, hold: Double? = nil) {
        self.id = id
        self.template = template
        self.files = files
        self.focusPoints = focusPoints ?? Array(repeating: nil, count: template.photos)
        self.hold = hold
    }
}

/// Cómo se eligen las plantillas al agrupar fotos.
public enum TemplateSelectionMode: String, Sendable, Codable, CaseIterable {
    case sequential, random
}

/// Compone collages a partir de plantillas y fotos.
public enum CollageRenderer {

    // MARK: Agrupación

    /// Reparte las fotos en grupos consumiéndolas en orden; la plantilla de cada
    /// grupo se elige en ciclo o al azar. Las fotos que no completen un grupo se
    /// quedan fuera (se informa en `leftover`).
    public static func group(files: [URL], templates: [CollageTemplate], mode: TemplateSelectionMode,
                             generator: inout some RandomNumberGenerator) -> (rows: [CollageRow], leftover: Int) {
        guard !templates.isEmpty else { return ([], files.count) }
        var rows: [CollageRow] = []
        var index = 0
        var cycle = 0
        while index < files.count {
            let remaining = files.count - index
            let chosen: CollageTemplate?
            switch mode {
            case .sequential:
                chosen = templates[cycle % templates.count]
                cycle += 1
            case .random:
                // Preferimos plantillas que quepan en lo que queda, para no dejar fotos fuera.
                let fitting = templates.filter { $0.photos <= remaining }
                chosen = (fitting.isEmpty ? templates : fitting).randomElement(using: &generator)
            }
            guard let template = chosen, template.photos <= remaining else { break }
            let slice = Array(files[index..<(index + template.photos)])
            rows.append(CollageRow(template: template, files: slice))
            index += template.photos
        }
        return (rows, files.count - index)
    }

    public static func group(files: [URL], templates: [CollageTemplate], mode: TemplateSelectionMode) -> (rows: [CollageRow], leftover: Int) {
        var generator = SystemRandomNumberGenerator()
        return group(files: files, templates: templates, mode: mode, generator: &generator)
    }

    /// Asigna fotos a celdas por parecido de proporción: primero las celdas más
    /// "extremas" (muy apaisadas o muy verticales), cada una con la foto cuya
    /// proporción esté más cerca. Devuelve, por celda, el índice de foto.
    public static func assignByAspect(photoAspects: [Double], cellAspects: [Double]) -> [Int] {
        let n = cellAspects.count
        guard photoAspects.count == n, n > 0 else { return Array(0..<photoAspects.count) }
        var available = Set(0..<n)
        var assignment = Array(repeating: 0, count: n)
        let order = cellAspects.indices.sorted { abs(log(cellAspects[$0])) > abs(log(cellAspects[$1])) }
        for cell in order {
            let best = available.min { abs(log(photoAspects[$0] / cellAspects[cell])) < abs(log(photoAspects[$1] / cellAspects[cell])) }!
            assignment[cell] = best
            available.remove(best)
        }
        return assignment
    }

    /// Reordena las fotos de una fila por proporción.
    public static func reorderByAspect(_ row: CollageRow) -> CollageRow {
        let aspects = row.files.map { ImageIOHelpers.displaySize(of: $0)?.aspectRatio ?? 1 }
        let assignment = assignByAspect(photoAspects: aspects, cellAspects: row.template.cells.map(\.aspectRatio))
        var result = row
        result.files = assignment.map { row.files[$0] }
        result.focusPoints = assignment.map { row.focusPoints.indices.contains($0) ? row.focusPoints[$0] : nil }
        return result
    }

    // MARK: Geometría

    /// Rectángulo de una celda en píxeles, con el hueco repartido: medio gap
    /// entre celdas vecinas y gap entero contra el borde del lienzo.
    public static func cellRect(_ cell: CollageCell, canvas: PixelSize, imageAreaTop: Double, gap: Double, edgePadding: Double? = nil) -> CGRect {
        let areaHeight = Double(canvas.height) - imageAreaTop
        let half = gap / 2
        let edge = edgePadding ?? gap
        let isLeft = cell.x < 0.01, isTop = cell.y < 0.01
        let isRight = cell.x + cell.w > 0.99, isBottom = cell.y + cell.h > 0.99
        let x0 = (cell.x * Double(canvas.width)).rounded() + (isLeft ? edge : half)
        let y0 = imageAreaTop + (cell.y * areaHeight).rounded() + (isTop ? edge : half)
        let x1 = ((cell.x + cell.w) * Double(canvas.width)).rounded() - (isRight ? edge : half)
        let y1 = imageAreaTop + ((cell.y + cell.h) * areaHeight).rounded() - (isBottom ? edge : half)
        return CGRect(x: x0, y: y0, width: max(0, x1 - x0), height: max(0, y1 - y0))
    }

    /// Altura reservada al título, proporcional al lienzo (mínimo 50 px).
    public static func titleHeight(for canvas: PixelSize, title: String) -> Double {
        guard !title.trimmingCharacters(in: .whitespaces).isEmpty else { return 0 }
        return max(50, (Double(canvas.width) * 0.05).rounded())
    }

    // MARK: Renderizado

    /// Compone un collage y lo devuelve como imagen. Con `visibleCells` se
    /// pintan solo las primeras celdas (para la aparición progresiva del slideshow).
    public static func render(_ row: CollageRow, options: CollageOptions, visibleCells: Int? = nil) throws -> CGImage {
        try Task.checkCaobaCancellation()
        let template = row.template
        guard row.files.count >= template.photos else { throw CaobaError.invalidParameters("collage.files") }

        // Lienzo: lado mayor = longestSide; el título se añade encima del área de fotos.
        let base = template.canvasSize(longestSide: options.longestSide)
        let titleH = titleHeight(for: base, title: options.title)
        let canvas = PixelSize(width: base.width, height: base.height + Int(titleH))
        guard canvas.width <= CollageOptions.maxDimension, canvas.height <= CollageOptions.maxDimension else {
            throw CaobaError.invalidParameters("collage.size")
        }

        let ctx = try Drawing.makeCanvas(canvas, background: options.background.fill)

        // Las overlap necesitan sitio en los bordes para el marco y la sombra.
        let edgePadding: Double? = template.overlap ? max(options.gap, overlapMargin(canvas: canvas, options: options)) : nil

        for (i, cell) in template.cells.enumerated() {
            try Task.checkCaobaCancellation()
            if let visibleCells, i >= visibleCells { break }
            let rect = cellRect(cell, canvas: canvas, imageAreaTop: titleH, gap: options.gap, edgePadding: edgePadding)
            guard rect.width >= 1, rect.height >= 1 else { continue }
            let photo = try PhotoLoader.load(row.files[i], fittingAtLeast: PixelSize(width: Int(rect.width), height: Int(rect.height)))
            let focus = row.focusPoints.indices.contains(i) ? (row.focusPoints[i] ?? CGPoint(x: 0.5, y: 0.5)) : CGPoint(x: 0.5, y: 0.5)
            let crop = CropGeometry.rect(in: photo.pixelSize, ratio: rect.width / rect.height, focus: focus)

            if template.overlap {
                drawFramedPhoto(photo, crop: crop, in: rect, options: options, ctx: ctx, canvas: canvas)
            } else {
                Drawing.drawImage(photo, crop: crop, into: rect, cornerRadius: options.cornerRadius, in: ctx, canvasHeight: canvas.height)
            }
        }

        if titleH > 0 {
            Drawing.drawText(options.title.trimmingCharacters(in: .whitespaces),
                             centeredAt: CGPoint(x: Double(canvas.width) / 2, y: titleH * 0.68),
                             fontSize: titleH * 0.48, bold: true, color: options.background.text,
                             maxWidth: Double(canvas.width) - 40, in: ctx, canvasHeight: canvas.height)
        }

        if let logo = options.logo {
            try Drawing.drawLogo(logo, in: ctx, canvas: canvas)
        }

        guard let image = ctx.makeImage() else { throw CaobaError.invalidParameters("collage.render") }
        return image
    }

    /// Marco blanco + sombra para plantillas overlap.
    private static func overlapMargin(canvas: PixelSize, options: CollageOptions) -> Double {
        let border = max(3, (Double(min(canvas.width, canvas.height)) * 0.012).rounded())
        let shadow = options.shadowIntensity > 0 ? max(6, border * 3) : 0
        return border + shadow + options.gap / 2
    }

    private static func drawFramedPhoto(_ photo: CGImage, crop: CGRect, in rect: CGRect, options: CollageOptions, ctx: CGContext, canvas: PixelSize) {
        let border = max(3, (min(rect.width, rect.height) * 0.02).rounded())
        let frame = rect.insetBy(dx: -border, dy: -border)
        let radius = options.cornerRadius > 0 ? options.cornerRadius + border : 2
        let shadowAlpha = options.shadowIntensity / 100 * 0.3
        let shadow: (CGSize, Double, CGColor)? = shadowAlpha > 0
            ? (CGSize(width: border, height: border), border * 2, CGColor(red: 0, green: 0, blue: 0, alpha: shadowAlpha))
            : nil
        Drawing.fillRect(frame, color: CGColor(red: 1, green: 1, blue: 1, alpha: 1), cornerRadius: radius,
                         shadow: shadow.map { (offset: $0.0, blur: $0.1, color: $0.2) }, in: ctx, canvasHeight: canvas.height)
        Drawing.drawImage(photo, crop: crop, into: rect, cornerRadius: options.cornerRadius, in: ctx, canvasHeight: canvas.height)
    }

    // MARK: Lote

    /// Genera todos los collages en la carpeta de salida: `collage.jpg` si hay
    /// uno, `collage_01.jpg`, `collage_02.jpg`… si hay varios.
    public static func generate(rows: [CollageRow], options: CollageOptions, outputFolder: URL,
                                baseName: String = "collage", progress: ProgressHandler? = nil) async throws -> (summary: BatchSummary, outputs: [URL]) {
        guard !rows.isEmpty else { throw CaobaError.noFiles }
        try FileManager.default.createDirectory(at: outputFolder, withIntermediateDirectories: true)
        var summary = BatchSummary()
        var outputs: [URL] = []
        let digits = String(rows.count).count
        for (index, row) in rows.enumerated() {
            try Task.checkCaobaCancellation()
            progress?(.step(index, of: rows.count, phase: .generatingCollage, file: row.template.name))
            let name = rows.count == 1 ? baseName : "\(baseName)_\(Renamer.pad(index + 1, digits: max(2, digits)))"
            let url = outputFolder.appendingPathComponent(name).appendingPathExtension("jpg")
            do {
                let image = try render(row, options: options)
                try ImageWriter.write(image, to: url, encoding: ImageEncoding(format: .jpeg, quality: options.quality))
                outputs.append(url)
                summary.processed += 1
            } catch let error as CaobaError where error == .cancelled {
                throw error
            } catch {
                summary.failures.append("\(name): \(error)")
            }
        }
        progress?(.step(rows.count, of: rows.count, phase: .generatingCollage))
        return (summary, outputs)
    }
}
