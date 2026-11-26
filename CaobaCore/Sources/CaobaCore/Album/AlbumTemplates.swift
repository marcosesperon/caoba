import Foundation
import CoreGraphics

/// Plantillas de collage que sirven como rejilla de un pliego: las rectangulares que no se pisan
/// y que se pueden partir con cortes rectos de lado a lado (666 de las 1049). Se pasan a árbol
/// de cortes una sola vez; al aplicarlas se estiran a la página o al pliego y se retocan con las
/// guías como cualquier otra rejilla.
public enum AlbumTemplates {
    public struct Entry: Sendable, Identifiable {
        /// El id de la plantilla de collage.
        public var id: String
        public var name: String
        public var photos: Int
        /// Proporción con la que se diseñó (al aplicarla se estira).
        public var aspect: Double
        /// El árbol, con las casillas vacías.
        public var node: AlbumNode

        /// El árbol con estas fotos, en orden de lectura.
        public func node(with photos: [String]) -> AlbumNode {
            node.assigning(photos.map { AlbumCell(photo: $0) })
        }
    }

    public static let all: [Entry] = CollageTemplates.all.compactMap(convert)

    /// Las plantillas con ese número de fotos, sin repetidas: muchas de collage solo cambian en la
    /// proporción del lienzo y, estiradas al pliego, son la misma rejilla (las de 1 foto, todas).
    public static func templates(photos: Int) -> [Entry] {
        byCount[photos] ?? []
    }

    private static let byCount: [Int: [Entry]] = Dictionary(grouping: all, by: \.photos).mapValues { entries in
        var seen = Set<String>()
        return entries.filter { seen.insert(shape(of: $0.node)).inserted }
    }

    /// La forma de un árbol (cortes y partes redondeadas), para reconocer las repetidas.
    private static func shape(of node: AlbumNode) -> String {
        switch node {
        case .cell: return "c"
        case .split(let axis, let fractions, let children):
            let total = fractions.reduce(0, +)
            let parts = fractions.map { String(format: "%.2f", $0 / max(total, 0.0001)) }.joined(separator: ",")
            return "\(axis.rawValue)[\(parts)](\(children.map(shape(of:)).joined(separator: ";")))"
        }
    }

    /// Pasa una plantilla a árbol de cortes, o `nil` si no se puede (solapes, círculos, giros,
    /// polígonos o casillas entrelazadas como un molinillo).
    static func convert(_ template: CollageTemplate) -> Entry? {
        guard !template.overlap, !template.cells.isEmpty,
              template.cells.allSatisfy({ $0.shape == nil && ($0.rotation ?? 0) == 0 && $0.points == nil }) else { return nil }
        let rects = template.cells.map { CGRect(x: $0.x, y: $0.y, width: $0.w, height: $0.h) }
        guard let node = split(rects, in: CGRect(x: 0, y: 0, width: 1, height: 1)) else { return nil }
        return Entry(id: template.id, name: template.name, photos: template.cells.count, aspect: template.aspectRatio, node: node)
    }

    /// Margen para dar por buena una línea de corte (las plantillas dejan huecos entre casillas).
    private static let tolerance = 0.012

    private static func split(_ cells: [CGRect], in bounds: CGRect) -> AlbumNode? {
        if cells.count == 1 { return .cell(AlbumCell(photo: nil)) }
        for axis in [AlbumSplitAxis.columns, .rows] {
            if let parts = cut(cells, axis: axis, bounds: bounds) {
                var children: [AlbumNode] = []
                var fractions: [Double] = []
                for (group, rect) in parts {
                    guard let child = split(group, in: rect) else { return nil }
                    children.append(child)
                    fractions.append(axis == .columns ? rect.width : rect.height)
                }
                return .split(axis: axis, fractions: fractions, children: children)
            }
        }
        return nil
    }

    /// Todas las líneas que cruzan el trozo de lado a lado en esa dirección, y los grupos que salen.
    private static func cut(_ cells: [CGRect], axis: AlbumSplitAxis, bounds: CGRect) -> [([CGRect], CGRect)]? {
        let start = { (r: CGRect) in axis == .columns ? r.minX : r.minY }
        let end = { (r: CGRect) in axis == .columns ? r.maxX : r.maxY }
        let sorted = cells.sorted { start($0) < start($1) }
        var groups: [[CGRect]] = []
        var current: [CGRect] = []
        var reach = -Double.infinity
        for cell in sorted {
            // Una casilla que empieza después de donde llega todo lo anterior abre un grupo nuevo.
            if !current.isEmpty, start(cell) >= reach - tolerance {
                groups.append(current)
                current = []
            }
            current.append(cell)
            reach = max(reach, end(cell))
        }
        if !current.isEmpty { groups.append(current) }
        guard groups.count > 1 else { return nil }
        // Cada grupo ocupa desde la mitad del hueco anterior hasta la mitad del siguiente.
        var result: [([CGRect], CGRect)] = []
        let lo = axis == .columns ? bounds.minX : bounds.minY
        let hi = axis == .columns ? bounds.maxX : bounds.maxY
        var edges = [lo]
        for i in 0..<(groups.count - 1) {
            let a = groups[i].map(end).max() ?? lo
            let b = groups[i + 1].map(start).min() ?? hi
            edges.append((a + b) / 2)
        }
        edges.append(hi)
        for (i, group) in groups.enumerated() {
            let rect = axis == .columns
                ? CGRect(x: edges[i], y: bounds.minY, width: edges[i + 1] - edges[i], height: bounds.height)
                : CGRect(x: bounds.minX, y: edges[i], width: bounds.width, height: edges[i + 1] - edges[i])
            result.append((group, rect))
        }
        return result
    }
}
