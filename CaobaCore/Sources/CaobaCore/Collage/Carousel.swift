import Foundation
import CoreGraphics

/// Formato de cada diapositiva de un carrusel de Instagram (1080 px de ancho).
public enum CarouselFormat: String, Sendable, Codable, CaseIterable, Identifiable {
    case portrait4x5 = "4x5"
    case square = "1x1"
    case portrait3x4 = "3x4"

    public var id: String { rawValue }

    /// Proporción de una diapositiva (ancho : alto).
    public var aspect: (width: Int, height: Int) {
        switch self {
        case .portrait4x5: return (4, 5)
        case .square: return (1, 1)
        case .portrait3x4: return (3, 4)
        }
    }

    /// Tamaño en píxeles de una diapositiva.
    public var slideSize: PixelSize {
        PixelSize(width: Carousel.slideWidth, height: Carousel.slideWidth * aspect.height / aspect.width)
    }

    public var label: String { "\(aspect.width):\(aspect.height)" }
}

/// Tramo de carrusel tal como va en `carousel_templates.json`: cuántas diapositivas
/// ocupa y sus celdas, en coordenadas 0-1 sobre el tramo entero (vale para cualquier formato).
struct CarouselSegmentDefinition: Decodable {
    var id: String
    var name: String
    var slides: Int
    var cells: [CollageCell]
}

/// Catálogo de tramos de carrusel. Va aparte de las plantillas de collage para no
/// mezclarlos en los selectores; cada tramo se ofrece en los tres formatos.
public enum CarouselTemplates {
    static let definitions: [CarouselSegmentDefinition] = {
        guard let url = Bundle.module.url(forResource: "carousel_templates", withExtension: "json"),
              let data = try? Data(contentsOf: url),
              let list = try? JSONDecoder().decode([CarouselSegmentDefinition].self, from: data) else { return [] }
        return list
    }()

    /// Todos los tramos en todos los formatos.
    public static let all: [CollageTemplate] = CarouselFormat.allCases.flatMap { format in
        definitions.map { make($0, format: format) }
    }

    /// Tramos de un formato.
    public static func templates(for format: CarouselFormat) -> [CollageTemplate] {
        all.filter { $0.id.hasPrefix(prefix(format)) }
    }

    public static func template(id: String) -> CollageTemplate? {
        all.first { $0.id == id }
    }

    /// Identificador de un tramo en un formato: «carousel_4x5_bg_span_2_card».
    public static func id(base: String, format: CarouselFormat) -> String { prefix(format) + base }

    /// El tramo sin formato («bg_span_2_card»), para guardar qué tramos se eligieron.
    public static func baseID(of template: CollageTemplate) -> String {
        CarouselFormat.allCases.reduce(template.id) { id, f in id.hasPrefix(prefix(f)) ? String(id.dropFirst(prefix(f).count)) : id }
    }

    /// Formato de un tramo.
    public static func format(of template: CollageTemplate) -> CarouselFormat? {
        CarouselFormat.allCases.first { template.id.hasPrefix(prefix($0)) }
    }

    private static func prefix(_ format: CarouselFormat) -> String { "carousel_\(format.rawValue)_" }

    private static func make(_ d: CarouselSegmentDefinition, format: CarouselFormat) -> CollageTemplate {
        let a = format.aspect
        return CollageTemplate(id: id(base: d.id, format: format), name: d.name, photos: d.cells.count,
                               aspect: [a.width * d.slides, a.height], overlap: false, cells: d.cells, slides: d.slides)
    }
}

/// Carrusel de Instagram: tramos encadenados que forman una tira ancha, que se dibuja
/// con el motor de collage y se corta en diapositivas exactas.
public enum Carousel {
    public static let slideWidth = 1080
    /// Máximo de diapositivas de un carrusel de Instagram.
    public static let maxSlides = 10

    /// Diapositivas que ocupan unos tramos.
    public static func slideCount(_ rows: [CollageRow]) -> Int {
        rows.reduce(0) { $0 + ($1.template.slides ?? 1) }
    }

    /// Recorta unos tramos para no pasar de `maxSlides` diapositivas.
    public static func limited(_ rows: [CollageRow]) -> [CollageRow] {
        var total = 0
        return rows.prefix { row in
            total += row.template.slides ?? 1
            return total <= maxSlides
        }
    }

    /// Une los tramos en una sola fila: una plantilla de N diapositivas con las celdas de
    /// cada tramo colocadas en su sitio, las fotos en orden y el foco de cada celda.
    public static func combine(_ rows: [CollageRow], format: CarouselFormat) -> CollageRow? {
        let total = slideCount(rows)
        guard total > 0 else { return nil }
        var cells: [CollageCell] = []
        var files: [URL] = []
        var focus: [CGPoint?] = []
        var offset = 0
        for row in rows {
            let slides = row.template.slides ?? 1
            for cell in row.template.cells {
                var c = cell
                c.x = (Double(offset) + cell.x * Double(slides)) / Double(total)
                c.w = cell.w * Double(slides) / Double(total)
                cells.append(c)
            }
            files += row.files
            focus += row.focusPoints
            offset += slides
        }
        let a = format.aspect
        let template = CollageTemplate(id: "carousel", name: "Carrusel", photos: cells.count,
                                       aspect: [a.width * total, a.height], overlap: false, cells: cells, slides: total)
        return CollageRow(template: template, files: files, focusPoints: focus)
    }

    /// Panorámica completa: N diapositivas de ancho exacto. Ignora el lado mayor y el título
    /// de las opciones (cada diapositiva mide lo que pide Instagram).
    public static func renderPanorama(_ rows: [CollageRow], format: CarouselFormat, options: CollageOptions) throws -> CGImage {
        guard let combined = combine(rows, format: format) else { throw CaobaError.noFiles }
        var opts = options
        let slides = combined.template.slides ?? 1
        opts.longestSide = max(slideWidth * slides, format.slideSize.height)
        opts.title = ""
        return try CollageRenderer.render(combined, options: opts)
    }

    /// Corta la panorámica en diapositivas de `slideWidth` px.
    public static func slices(of panorama: CGImage, slides: Int) -> [CGImage] {
        (0..<slides).compactMap { i in
            panorama.cropping(to: CGRect(x: i * slideWidth, y: 0, width: slideWidth, height: panorama.height))
        }
    }

    /// Escribe el carrusel en una subcarpeta nueva de `outputFolder`: `01.jpg`, `02.jpg`…
    /// (en el orden de subida) y `panoramica.jpg`. Devuelve la subcarpeta.
    public static func generate(_ rows: [CollageRow], format: CarouselFormat, options: CollageOptions, outputFolder: URL,
                                progress: ProgressHandler? = nil) throws -> URL {
        let rows = limited(rows)
        guard !rows.isEmpty else { throw CaobaError.noFiles }
        let slides = slideCount(rows)
        progress?(.step(0, of: slides + 1, phase: .generatingCollage, file: "panoramica.jpg"))
        let panorama = try renderPanorama(rows, format: format, options: options)
        try Task.checkCaobaCancellation()
        let folder = uniqueFolder(in: outputFolder)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let encoding = ImageEncoding(format: .jpeg, quality: options.quality)
        for (i, slide) in slices(of: panorama, slides: slides).enumerated() {
            try Task.checkCaobaCancellation()
            let name = Renamer.pad(i + 1, digits: 2)
            progress?(.step(i + 1, of: slides + 1, phase: .generatingCollage, file: "\(name).jpg"))
            try ImageWriter.write(slide, to: folder.appendingPathComponent(name).appendingPathExtension("jpg"), encoding: encoding)
        }
        try ImageWriter.write(panorama, to: folder.appendingPathComponent("panoramica.jpg"), encoding: encoding)
        progress?(.step(slides + 1, of: slides + 1, phase: .generatingCollage))
        return folder
    }

    /// «carrusel», o «carrusel_2», «carrusel_3»… si ya existe.
    static func uniqueFolder(in parent: URL) -> URL {
        var candidate = parent.appendingPathComponent("carrusel", isDirectory: true)
        var n = 2
        while FileManager.default.fileExists(atPath: candidate.path) {
            candidate = parent.appendingPathComponent("carrusel_\(n)", isDirectory: true)
            n += 1
        }
        return candidate
    }
}
