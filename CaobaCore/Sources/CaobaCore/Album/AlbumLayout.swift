import Foundation
import CoreGraphics

/// Una casilla del pliego: qué foto lleva y cómo va encuadrada.
public struct AlbumCell: Codable, Sendable, Equatable, Identifiable {
    public var id: UUID
    /// Nombre del fichero en la carpeta de fotos (el `JPG` de la sesión). `nil` = casilla vacía.
    public var photo: String?
    /// Punto de la foto (0-1, origen arriba-izquierda) que se quiere en el centro del encuadre.
    /// `nil` = el que diga el análisis (las caras o lo más llamativo).
    public var focus: CGPoint?
    /// Ampliación sobre el encuadre que justo llena la casilla (1 = sin ampliar). `nil` = 1.
    public var zoom: Double?
    /// Candado de foto: esta foto se queda en esta casilla aunque se rehaga el reparto.
    public var locked: Bool
    /// «A sangre»: los lados de la casilla que tocan el margen de seguridad llegan hasta el corte
    /// y el sangrado (fase 3).
    public var bleed: Bool

    public static let maxZoom = 5.0

    public init(id: UUID = UUID(), photo: String?, focus: CGPoint? = nil, zoom: Double? = nil, locked: Bool = false, bleed: Bool = false) {
        self.id = id
        self.photo = photo
        self.focus = focus
        self.zoom = zoom
        self.locked = locked
        self.bleed = bleed
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(UUID.self, forKey: .id)
        photo = try c.decodeIfPresent(String.self, forKey: .photo)
        focus = try c.decodeIfPresent(CGPoint.self, forKey: .focus)
        zoom = try c.decodeIfPresent(Double.self, forKey: .zoom)
        locked = try c.decodeIfPresent(Bool.self, forKey: .locked) ?? false
        bleed = try c.decodeIfPresent(Bool.self, forKey: .bleed) ?? false
    }

    /// Ampliación efectiva (al menos 1).
    public var scale: Double { max(1, min(zoom ?? 1, Self.maxZoom)) }
}

/// Dirección en la que se parte un trozo del pliego.
public enum AlbumSplitAxis: String, Codable, Sendable, Hashable {
    /// Trozos uno al lado de otro (las guías son verticales).
    case columns
    /// Trozos uno encima de otro (las guías son horizontales).
    case rows
}

/// Árbol de cortes: un trozo del pliego es una casilla o se parte en varios trozos, en columnas
/// o en filas, cada uno con su parte del total. Así las casillas nunca se pisan, y mover una
/// guía (fase 2) es solo cambiar dos de esas partes.
public indirect enum AlbumNode: Codable, Sendable, Equatable {
    case cell(AlbumCell)
    case split(axis: AlbumSplitAxis, fractions: [Double], children: [AlbumNode])

    /// Las casillas en orden de lectura (de izquierda a derecha y de arriba abajo).
    public var cells: [AlbumCell] {
        switch self {
        case .cell(let cell): return [cell]
        case .split(_, _, let children): return children.flatMap(\.cells)
        }
    }

    /// Dónde cae cada casilla dentro de `rect` (en mm), dejando `gap` entre trozos vecinos.
    public func cellRects(in rect: CGRect, gap: Double) -> [(cell: AlbumCell, rect: CGRect)] {
        switch self {
        case .cell(let cell):
            return [(cell, rect)]
        case .split(let axis, let fractions, let children):
            let total = fractions.reduce(0, +)
            guard total > 0, fractions.count == children.count, !children.isEmpty else { return [] }
            let gaps = gap * Double(children.count - 1)
            let length = (axis == .columns ? rect.width : rect.height) - gaps
            var offset = axis == .columns ? rect.minX : rect.minY
            var result: [(cell: AlbumCell, rect: CGRect)] = []
            for (child, fraction) in zip(children, fractions) {
                let size = length * fraction / total
                let part = axis == .columns
                    ? CGRect(x: offset, y: rect.minY, width: size, height: rect.height)
                    : CGRect(x: rect.minX, y: offset, width: rect.width, height: size)
                result += child.cellRects(in: part, gap: gap)
                offset += size + gap
            }
            return result
        }
    }

    /// Cambia las fotos de las casillas, en orden de lectura (las que sobren quedan como estaban).
    public func assigning(_ photos: [AlbumCell]) -> AlbumNode {
        var queue = photos[...]
        return assigning(&queue)
    }

    private func assigning(_ queue: inout ArraySlice<AlbumCell>) -> AlbumNode {
        switch self {
        case .cell(let cell):
            guard let next = queue.popFirst() else { return .cell(cell) }
            return .cell(next)
        case .split(let axis, let fractions, let children):
            return .split(axis: axis, fractions: fractions, children: children.map { $0.assigning(&queue) })
        }
    }
}

/// Una composición (una página, o el pliego entero) y la parte de la zona útil que ocupa.
/// Normalmente toda; si las fotos piden otra proporción, a veces queda mejor centrada con
/// blanco alrededor que con las fotos recortadas (una vertical sola en una página cuadrada).
public struct AlbumBlock: Codable, Sendable, Equatable {
    public var node: AlbumNode
    /// Rectángulo dentro de la zona útil, en partes de ella (0-1).
    public var area: CGRect

    public static let wholeArea = CGRect(x: 0, y: 0, width: 1, height: 1)

    public init(node: AlbumNode, area: CGRect = AlbumBlock.wholeArea) {
        self.node = node
        self.area = area
    }

    public var cells: [AlbumCell] { node.cells }

    /// Dónde cae el bloque dentro de la zona útil `content` (en mm).
    public func frame(in content: CGRect) -> CGRect {
        CGRect(x: content.minX + area.minX * content.width, y: content.minY + area.minY * content.height,
               width: area.width * content.width, height: area.height * content.height)
    }

    public func cellRects(in content: CGRect) -> [(cell: AlbumCell, rect: CGRect)] {
        node.cellRects(in: frame(in: content), gap: AlbumSpec.gapMM)
    }
}

/// Cómo va repartido un pliego: una composición que cruza el lomo, o una por página.
public enum AlbumSpreadLayout: Codable, Sendable, Equatable {
    /// Ocupa la zona útil del pliego entero, lomo incluido (una panorámica, un grupo grande…).
    case full(AlbumBlock)
    /// Cada página por su lado. `nil` = página en blanco.
    case pages(left: AlbumBlock?, right: AlbumBlock?)

    public static let empty = AlbumSpreadLayout.pages(left: nil, right: nil)

    public var cells: [AlbumCell] {
        switch self {
        case .full(let block): return block.cells
        case .pages(let left, let right): return (left?.cells ?? []) + (right?.cells ?? [])
        }
    }

    /// Lo que se dibuja de cada casilla, en mm: su rectángulo y, si va «a sangre», alargado por
    /// los lados que tocan el margen de seguridad hasta el corte más el sangrado (en un pliego de
    /// páginas sueltas, el lado del lomo llega hasta el lomo). Lo usan el pliego en pantalla y la
    /// exportación, para que se vea lo mismo que sale. Con `pageOnly` (un pliego de una página que
    /// se exporta solo con su página), el lado del lomo también llena el sangrado.
    public func drawRects(_ spec: AlbumSpec, pageOnly: Bool = false) -> [(cell: AlbumCell, rect: CGRect)] {
        let isFull: Bool = { if case .full = self { return true }; return false }()
        return cellRects(spec).map { entry in
            guard entry.cell.bleed else { return entry }
            return (entry.cell, Self.bled(entry.rect, spec: spec, crossesSpine: isFull, pageOnly: pageOnly))
        }
    }

    /// Si la casilla toca algún margen (y por tanto puede ir «a sangre»).
    public func touchesMargin(_ id: UUID, spec: AlbumSpec) -> Bool {
        guard let rect = cellRects(spec).first(where: { $0.cell.id == id })?.rect else { return false }
        let isFull: Bool = { if case .full = self { return true }; return false }()
        return Self.bled(rect, spec: spec, crossesSpine: isFull) != rect
    }

    /// Un rectángulo alargado hasta el sangrado por los lados que tocan el margen de seguridad.
    static func bled(_ rect: CGRect, spec: AlbumSpec, crossesSpine: Bool, pageOnly: Bool = false) -> CGRect {
        let tolerance = 0.5
        let size = spec.spreadSize
        let safety = spec.safetyMM
        let bleed = spec.bleedMM
        var minX = rect.minX, maxX = rect.maxX, minY = rect.minY, maxY = rect.maxY
        if abs(minY - safety) < tolerance { minY = -bleed }
        if abs(maxY - (size.height - safety)) < tolerance { maxY = size.height + bleed }
        if abs(minX - safety) < tolerance { minX = -bleed }
        if abs(maxX - (size.width - safety)) < tolerance { maxX = size.width + bleed }
        if !crossesSpine {
            // Junto al lomo: hasta el lomo, sin pasar a la otra página (o hasta su sangrado si la
            // página se exporta sola).
            if abs(maxX - (spec.spineStart - safety)) < tolerance { maxX = spec.spineStart + (pageOnly ? bleed : 0) }
            if abs(minX - (spec.spineEnd + safety)) < tolerance { minX = spec.spineEnd - (pageOnly ? bleed : 0) }
        }
        return CGRect(x: minX, y: minY, width: maxX - minX, height: maxY - minY)
    }

    /// Cada casilla con su rectángulo en mm sobre el pliego (origen arriba-izquierda del corte).
    public func cellRects(_ spec: AlbumSpec) -> [(cell: AlbumCell, rect: CGRect)] {
        switch self {
        case .full(let block):
            return block.cellRects(in: spec.spreadContent)
        case .pages(let left, let right):
            return (left?.cellRects(in: spec.pageContent(.left)) ?? []) + (right?.cellRects(in: spec.pageContent(.right)) ?? [])
        }
    }
}

/// Por qué el reparto automático dejó un pliego así. La app lo enseña en pequeño debajo.
public enum AlbumSpreadReason: Codable, Sendable, Equatable, Hashable {
    /// Una panorámica que pide el pliego entero.
    case panorama
    /// Un grupo grande: con menos sitio, las caras saldrían diminutas.
    case group(faces: Int)
    /// Fotos del mismo momento (disparadas en pocos segundos).
    case sameMoment(seconds: Int)
    /// El usuario fijó cuántas fotos lleva.
    case manualCount
    /// Lo que mejor encaja con los formatos de las fotos.
    case bestFit
}

/// Un pliego del álbum.
public struct AlbumSpread: Codable, Sendable, Equatable, Identifiable {
    public var id: UUID
    public var layout: AlbumSpreadLayout
    /// Cuántas fotos ha pedido el usuario para este pliego; `nil` = las que decida el reparto.
    public var manualCount: Int?
    public var reason: AlbumSpreadReason?
    /// Candado de pliego: la cascada y «Repartir automáticamente» lo saltan. Se pone solo al
    /// retocarlo a mano.
    public var locked: Bool

    public init(id: UUID = UUID(), layout: AlbumSpreadLayout = .empty, manualCount: Int? = nil, reason: AlbumSpreadReason? = nil, locked: Bool = false) {
        self.id = id
        self.layout = layout
        self.manualCount = manualCount
        self.reason = reason
        self.locked = locked
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(UUID.self, forKey: .id)
        layout = try c.decodeIfPresent(AlbumSpreadLayout.self, forKey: .layout) ?? .empty
        manualCount = try c.decodeIfPresent(Int.self, forKey: .manualCount)
        reason = try c.decodeIfPresent(AlbumSpreadReason.self, forKey: .reason)
        locked = try c.decodeIfPresent(Bool.self, forKey: .locked) ?? false
    }

    /// Fotos del pliego en orden de lectura.
    public var photos: [String] { layout.cells.compactMap(\.photo) }
    /// Fotos con candado de foto.
    public var lockedPhotos: [String] { layout.cells.filter(\.locked).compactMap(\.photo) }
    public var hasLockedPhotos: Bool { layout.cells.contains { $0.locked && $0.photo != nil } }
}
