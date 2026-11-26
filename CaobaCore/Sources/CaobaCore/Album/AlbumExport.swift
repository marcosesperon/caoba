import Foundation
import CoreGraphics
import ImageIO

/// Exportación del álbum (fase 3): una imagen por pliego a la medida real, con el sangrado, a
/// los ppp del álbum, en JPEG sRGB a calidad máxima. Lo que se dibuja es exactamente lo que se
/// ve en el pliego: mismas casillas (`drawRects`), mismo encuadre (`visibleRegion`).
public enum AlbumExport {
    /// Por debajo de esto, aviso naranja; por debajo de `veryLowPPI`, rojo.
    public static let lowPPI = 200.0
    public static let veryLowPPI = 150.0

    public enum Level: Sendable, Equatable {
        case ok, low, veryLow
    }

    /// Índice con el que se nombra la portada en la exportación y en los avisos (va delante del 0).
    public static let coverIndex = -1

    /// Una foto que se amplía demasiado para su casilla.
    public struct Issue: Sendable, Equatable {
        /// Pliego (desde 0), o `coverIndex` si es la portada.
        public var spread: Int
        public var photo: String
        public var ppi: Double
        public var level: Level
    }

    public static func level(for ppi: Double) -> Level {
        ppi < veryLowPPI ? .veryLow : (ppi < lowPPI ? .low : .ok)
    }

    /// Ppp efectivos de una foto de `pixels` en una casilla de `rect` (mm): los píxeles de la
    /// parte que se ve divididos por lo que mide impresa, en pulgadas. Se mira el lado más justo.
    public static func effectivePPI(pixels: PixelSize, cell: AlbumCell, rect: CGRect, focus: CGPoint) -> Double {
        guard rect.width > 0, rect.height > 0, pixels.width > 0, pixels.height > 0 else { return 0 }
        let region = AlbumAutoLayout.visibleRegion(photoAspect: pixels.aspectRatio, cellAspect: rect.width / rect.height,
                                                   focus: focus, zoom: cell.scale)
        let across = region.width * Double(pixels.width) / (rect.width / 25.4)
        let down = region.height * Double(pixels.height) / (rect.height / 25.4)
        return min(across, down)
    }

    /// Las fotos por debajo de `lowPPI` en estos pliegos (todos si `spreads` es `nil`), de peor a mejor.
    public static func issues(in document: AlbumDocument, pixels: [String: PixelSize], spreads: [Int]? = nil) -> [Issue] {
        var result: [Issue] = []
        for index in spreads ?? pieces(of: document) {
            guard let piece = piece(index, of: document) else { continue }
            for entry in piece.spread.layout.drawRects(piece.spec, pageOnly: piece.pageOnly != nil) {
                guard let photo = entry.cell.photo, let size = pixels[photo] else { continue }
                let focus = entry.cell.focus ?? document.info[photo]?.focus ?? CGPoint(x: 0.5, y: 0.5)
                let ppi = effectivePPI(pixels: size, cell: entry.cell, rect: entry.rect, focus: focus)
                let level = level(for: ppi)
                if level != .ok { result.append(Issue(spread: index, photo: photo, ppi: ppi, level: level)) }
            }
        }
        return result.sorted { $0.ppi < $1.ppi }
    }

    // MARK: - Piezas del álbum

    /// Lo que se exporta: la portada (si la lleva) y los pliegos, en orden.
    public static func pieces(of document: AlbumDocument) -> [Int] {
        (document.spec.cover != nil && document.cover != nil ? [coverIndex] : []) + Array(document.spreads.indices)
    }

    /// Una pieza con sus medidas y, si es un pliego de una página que se exporta solo con su
    /// página, qué página es.
    public static func piece(_ index: Int, of document: AlbumDocument) -> (spread: AlbumSpread, spec: AlbumSpec, pageOnly: AlbumPageSide?)? {
        if index == coverIndex {
            guard let cover = document.cover, let spec = document.spec.coverSpec else { return nil }
            return (cover, spec, nil)
        }
        guard document.spreads.indices.contains(index) else { return nil }
        let side = document.singleSide(ofSpread: index)
        return (document.spreads[index], document.spec, document.spec.singlePageExport == .pageOnly ? side : nil)
    }

    // MARK: - Dibujo

    /// Dibuja un pliego a su medida de exportación. `folder` es la carpeta de las fotos. Con `spec`
    /// se dibuja con otras medidas (la portada); con `pageOnly`, solo esa página con su sangrado.
    public static func render(_ spread: AlbumSpread, document: AlbumDocument, folder: URL,
                              spec custom: AlbumSpec? = nil, pageOnly: AlbumPageSide? = nil) throws -> CGImage {
        let spec = custom ?? document.spec
        let size = spec.exportPixelSize
        guard let ctx = CGContext.rgba(width: size.width, height: size.height, colorSpace: CGColorSpace(name: CGColorSpace.sRGB)) else {
            throw CaobaError.cannotWriteImage("pliego")
        }
        // Píxeles por mm y paso de mm del corte (origen arriba-izquierda) a píxeles de Core Graphics
        // (origen abajo-izquierda, con el sangrado alrededor).
        let scale = Double(spec.ppi) / 25.4
        let bleed = spec.bleedMM
        func pixelRect(_ r: CGRect) -> CGRect {
            CGRect(x: (r.minX + bleed) * scale, y: Double(size.height) - (r.maxY + bleed) * scale,
                   width: r.width * scale, height: r.height * scale)
        }
        ctx.setFillColor(CGColor(srgbRed: 1, green: 1, blue: 1, alpha: 1))
        ctx.fill(CGRect(x: 0, y: 0, width: size.width, height: size.height))
        ctx.interpolationQuality = .high

        for entry in spread.layout.drawRects(spec, pageOnly: pageOnly != nil) {
            try Task.checkCancellation()
            guard let photo = entry.cell.photo else { continue }
            let target = pixelRect(entry.rect)
            let url = folder.appendingPathComponent(photo)
            let display = ImageIOHelpers.displaySize(of: url)
            let aspect = display?.aspectRatio ?? document.info[photo]?.aspect ?? 1.5
            let focus = entry.cell.focus ?? document.info[photo]?.focus ?? CGPoint(x: 0.5, y: 0.5)
            let region = AlbumAutoLayout.visibleRegion(photoAspect: aspect, cellAspect: entry.rect.width / entry.rect.height,
                                                       focus: focus, zoom: entry.cell.scale)
            // Solo los píxeles que hacen falta: la foto entera a la medida que pide la casilla
            // (nunca más que el original; ImageIO no amplía).
            let neededWidth = target.width / region.width
            let neededHeight = target.height / region.height
            let longest = Int((aspect >= 1 ? neededWidth : neededHeight).rounded(.up)) + 2
            guard let image = ThumbnailProvider.makeThumbnail(url: url, maxPixelSize: max(longest, 16)) else {
                throw CaobaError.cannotReadImage(photo)
            }
            let crop = CGRect(x: region.minX * Double(image.width), y: region.minY * Double(image.height),
                              width: region.width * Double(image.width), height: region.height * Double(image.height))
            guard let piece = image.croppedTopLeft(crop) else { throw CaobaError.cannotReadImage(photo) }
            ctx.draw(piece, in: target)
        }
        guard let result = ctx.makeImage() else { throw CaobaError.cannotWriteImage("pliego") }
        guard let pageOnly else { return result }
        // Solo la página útil, con su sangrado alrededor (también por el lado del lomo).
        let page = spec.pageRect(pageOnly)
        let pixels = spec.pagePixelSize
        // En el lienzo la página empieza en (minX + sangrado); con su propio sangrado, en minX.
        let originX = Int((page.minX * scale).rounded())
        let crop = CGRect(x: min(originX, result.width - pixels.width), y: 0, width: pixels.width, height: pixels.height)
        guard let cropped = result.cropping(to: crop) else { throw CaobaError.cannotWriteImage("pliego") }
        return cropped
    }

    // MARK: - Ficheros

    /// «01.jpg», «02.jpg»… (tres cifras si hay más de 99 pliegos). La portada es «00.jpg».
    public static func fileName(_ index: Int, of total: Int) -> String {
        let digits = total > 99 ? 3 : 2
        return String(format: "%0\(digits)d.jpg", index == coverIndex ? 0 : index + 1)
    }

    /// Los pliegos exportados antes que hay en la carpeta (solo los que se llaman con un número).
    public static func previousExports(in folder: URL) -> [URL] {
        let items = (try? FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles])) ?? []
        return items.filter { url in
            let name = url.deletingPathExtension().lastPathComponent
            return url.pathExtension.lowercased() == "jpg" && !name.isEmpty && name.allSatisfy(\.isNumber)
        }
    }

    /// Exporta el álbum a `destination` (la carpeta del álbum). Con `only`, solo ese pliego (sin
    /// tocar los demás; `coverIndex` es la portada); sin él, el álbum entero con su portada,
    /// mandando antes a la Papelera los números de la exportación anterior. `folder` es la carpeta
    /// de las fotos.
    public static func export(_ document: AlbumDocument, photos folder: URL, to destination: URL, only: Int? = nil,
                              trash: (URL) throws -> Void = { try FileManager.default.trashItem(at: $0, resultingItemURL: nil) },
                              progress: @escaping ProgressHandler = { _ in }) async throws -> BatchSummary {
        let indices = only.map { [$0] } ?? pieces(of: document)
        guard !indices.isEmpty, indices.allSatisfy({ piece($0, of: document) != nil }) else { throw CaobaError.noFiles }
        try FileManager.default.createDirectory(at: destination, withIntermediateDirectories: true)
        if only == nil {
            for old in previousExports(in: destination) { try trash(old) }
        }
        let ppi = document.spec.ppi
        // Los ppp van al fichero (para que el laboratorio sepa la medida) y la imagen ya es sRGB,
        // así que su perfil se incrusta con ella.
        let metadata: [CFString: Any] = [
            kCGImagePropertyDPIWidth: ppi,
            kCGImagePropertyDPIHeight: ppi,
            kCGImagePropertyJFIFDictionary: [kCGImagePropertyJFIFXDensity: ppi, kCGImagePropertyJFIFYDensity: ppi, kCGImagePropertyJFIFDensityUnit: 1],
        ]
        var summary = BatchSummary()
        for (step, index) in indices.enumerated() {
            try Task.checkCancellation()
            let name = fileName(index, of: document.spreads.count)
            progress(.step(step, of: indices.count, phase: .exportingAlbum, file: name))
            // Uno a uno: un pliego grande a 600 ppp ocupa cientos de MB en memoria.
            try autoreleasepool {
                guard let piece = piece(index, of: document) else { return }
                let image = try render(piece.spread, document: document, folder: folder, spec: piece.spec, pageOnly: piece.pageOnly)
                try ImageWriter.write(image, to: destination.appendingPathComponent(name),
                                      encoding: ImageEncoding(format: .jpeg, quality: 100), metadata: metadata)
            }
            summary.processed += 1
        }
        progress(.step(indices.count, of: indices.count, phase: .exportingAlbum))
        return summary
    }
}
