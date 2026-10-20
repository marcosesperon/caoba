import Foundation

/// Celda de una plantilla, en coordenadas normalizadas (0-1) sobre el lienzo.
public struct CollageCell: Codable, Sendable, Equatable, Hashable {
    public var x: Double
    public var y: Double
    public var w: Double
    public var h: Double
    /// Forma de la celda: `nil` = rectángulo; `.circle` = foto recortada en redondo (el círculo
    /// va en el cuadrado centrado dentro de la celda, con un aro del color del fondo).
    public var shape: Shape?

    public enum Shape: String, Codable, Sendable, Hashable {
        case circle
    }

    public init(x: Double, y: Double, w: Double, h: Double, shape: Shape? = nil) {
        self.x = x
        self.y = y
        self.w = w
        self.h = h
        self.shape = shape
    }

    public var isCircle: Bool { shape == .circle }
    public var aspectRatio: Double { isCircle ? 1 : (h > 0 ? w / h : 1) }
}

/// Plantilla de collage: cuántas fotos, qué proporción tiene el lienzo y dónde
/// va cada celda. Las `overlap` se superponen y se pintan con marco y sombra.
public struct CollageTemplate: Codable, Sendable, Equatable, Hashable, Identifiable {
    public var id: String
    public var name: String
    public var photos: Int
    public var aspect: [Int]
    public var overlap: Bool
    public var cells: [CollageCell]

    public init(id: String, name: String, photos: Int, aspect: [Int], overlap: Bool = false, cells: [CollageCell]) {
        self.id = id
        self.name = name
        self.photos = photos
        self.aspect = aspect
        self.overlap = overlap
        self.cells = cells
    }

    /// Proporción del lienzo (ancho / alto).
    public var aspectRatio: Double {
        guard aspect.count == 2, aspect[1] > 0 else { return 1 }
        return Double(aspect[0]) / Double(aspect[1])
    }

    /// Etiqueta tipo "16:9".
    public var aspectLabel: String {
        aspect.count == 2 ? "\(aspect[0]):\(aspect[1])" : "1:1"
    }

    public var isLandscape: Bool { aspectRatio >= 1 }

    /// Plantilla con alguna celda redonda (tipo «Redondas»: sale en Collage y en el Slideshow).
    public var isRound: Bool { cells.contains(where: \.isCircle) }

    /// Tamaño del lienzo dado el lado mayor.
    public func canvasSize(longestSide: Int) -> PixelSize {
        if aspectRatio >= 1 {
            return PixelSize(width: longestSide, height: max(1, Int((Double(longestSide) / aspectRatio).rounded())))
        }
        return PixelSize(width: max(1, Int((Double(longestSide) * aspectRatio).rounded())), height: longestSide)
    }
}

/// Catálogo de plantillas, cargado del JSON exportado de la app antigua.
public enum CollageTemplates {
    /// Todas las plantillas (incluidas las overlap).
    public static let all: [CollageTemplate] = {
        guard let url = Bundle.module.url(forResource: "templates", withExtension: "json"),
              let data = try? Data(contentsOf: url),
              let templates = try? JSONDecoder().decode([CollageTemplate].self, from: data) else {
            return []
        }
        return templates
    }()

    /// Proporciones disponibles, ordenadas de más apaisada a más vertical.
    public static var aspectLabels: [String] {
        let unique = Set(all.map(\.aspectLabel))
        return unique.sorted { a, b in
            (template(withAspectLabel: a)?.aspectRatio ?? 1) > (template(withAspectLabel: b)?.aspectRatio ?? 1)
        }
    }

    private static func template(withAspectLabel label: String) -> CollageTemplate? {
        all.first { $0.aspectLabel == label }
    }

    public static func template(id: String) -> CollageTemplate? {
        all.first { $0.id == id }
    }

    /// Tipo de plantilla para filtrar: básicas (celdas en rejilla), superpuestas (marco y
    /// sombra, solo en el Slideshow) o redondas (con un círculo; en Collage y en el Slideshow).
    public enum TemplateType: String, Sendable, Codable, CaseIterable {
        case basic, overlap, round
    }

    /// Tipo de una plantilla.
    public static func type(of t: CollageTemplate) -> TemplateType {
        t.overlap ? .overlap : (t.isRound ? .round : .basic)
    }

    /// Filtra por número de fotos, proporción, si se admiten overlap y, opcionalmente, tipo.
    public static func filter(photos: Int? = nil, aspectLabel: String? = nil, includeOverlap: Bool = false, type: TemplateType? = nil) -> [CollageTemplate] {
        all.filter { t in
            (includeOverlap || !t.overlap)
                && (photos == nil || t.photos == photos)
                && (aspectLabel == nil || t.aspectLabel == aspectLabel)
                && (type == nil || Self.type(of: t) == type)
        }
    }
}
