import Foundation
import CoreGraphics

// Retoques a mano de un pliego (fase 2): guías que se arrastran, imán, igualar, ajustar a las
// fotos y cambios de casilla. Todo trabaja en mm sobre el pliego, como `cellRects`.

/// Dónde está una composición dentro del pliego.
public enum AlbumBlockPlace: String, Sendable, Hashable, Codable {
    case full, left, right
}

/// Una guía que se puede arrastrar.
public struct AlbumGuide: Sendable, Equatable, Identifiable {
    public enum Kind: Sendable, Equatable, Hashable {
        /// Entre el hijo `index` y el `index + 1` del corte en `path` (índices de hijo desde la raíz).
        case split(place: AlbumBlockPlace, path: [Int], index: Int)
        /// Un borde del bloque (cuando la composición no llena su zona y queda blanco alrededor).
        case edge(place: AlbumBlockPlace, side: Side)
        /// El lomo de un pliego hecho página a página: al moverlo pasa a ser una sola composición.
        case spine
    }

    public enum Side: String, Sendable, Hashable {
        case left, right, top, bottom
    }

    public var kind: Kind
    /// `.columns` = guía vertical (se mueve en horizontal); `.rows` = horizontal.
    public var axis: AlbumSplitAxis
    /// Dónde está la línea, en mm (x para las verticales, y para las horizontales).
    public var position: Double
    /// Hasta dónde se puede llevar sin que ninguna casilla baje del mínimo.
    public var range: ClosedRange<Double>
    /// Tramo que ocupa la línea en la otra dirección (para dibujarla y para acertar con el ratón).
    public var span: ClosedRange<Double>

    public var id: String { "\(kind)" }
}

/// Resultado de mover una guía: el pliego nuevo y la medida de las dos casillas vecinas (mm).
public struct AlbumGuideMove: Sendable, Equatable {
    public var layout: AlbumSpreadLayout
    public var position: Double
    public var before: Double
    public var after: Double
}

extension AlbumNode {
    /// Lo mínimo que puede medir este trozo a lo largo de `axis` con casillas de al menos `minCell`.
    func minLength(_ axis: AlbumSplitAxis, gap: Double, minCell: Double) -> Double {
        switch self {
        case .cell:
            return minCell
        case .split(let own, _, let children):
            let mins = children.map { $0.minLength(axis, gap: gap, minCell: minCell) }
            return own == axis ? mins.reduce(0, +) + gap * Double(children.count - 1) : (mins.max() ?? minCell)
        }
    }

    /// Rectángulos de los hijos de un corte (en el mismo orden).
    static func childRects(axis: AlbumSplitAxis, fractions: [Double], count: Int, in rect: CGRect, gap: Double) -> [CGRect] {
        let total = fractions.reduce(0, +)
        guard total > 0, count > 0 else { return [] }
        let length = (axis == .columns ? rect.width : rect.height) - gap * Double(count - 1)
        var offset = axis == .columns ? rect.minX : rect.minY
        return fractions.map { fraction in
            let size = length * fraction / total
            defer { offset += size + gap }
            return axis == .columns
                ? CGRect(x: offset, y: rect.minY, width: size, height: rect.height)
                : CGRect(x: rect.minX, y: offset, width: rect.width, height: size)
        }
    }

    /// Las guías de los cortes de este árbol dentro de `rect`.
    func guides(in rect: CGRect, gap: Double, minCell: Double, place: AlbumBlockPlace, path: [Int] = []) -> [AlbumGuide] {
        guard case .split(let axis, let fractions, let children) = self else { return [] }
        let rects = Self.childRects(axis: axis, fractions: fractions, count: children.count, in: rect, gap: gap)
        guard rects.count == children.count else { return [] }
        var result: [AlbumGuide] = []
        for i in 0..<(children.count - 1) {
            let a = rects[i], b = rects[i + 1]
            let minA = children[i].minLength(axis, gap: gap, minCell: minCell)
            let minB = children[i + 1].minLength(axis, gap: gap, minCell: minCell)
            let (start, end, position) = axis == .columns
                ? (a.minX + minA + gap / 2, b.maxX - minB - gap / 2, a.maxX + gap / 2)
                : (a.minY + minA + gap / 2, b.maxY - minB - gap / 2, a.maxY + gap / 2)
            let span: ClosedRange<Double> = axis == .columns ? Double(rect.minY)...Double(rect.maxY) : Double(rect.minX)...Double(rect.maxX)
            result.append(AlbumGuide(kind: .split(place: place, path: path, index: i), axis: axis, position: position,
                                     range: min(start, position)...max(end, position), span: span))
        }
        for (i, child) in children.enumerated() {
            result += child.guides(in: rects[i], gap: gap, minCell: minCell, place: place, path: path + [i])
        }
        return result
    }

    /// Mueve la guía `index` del corte en `path` para que quede en `position` (mm).
    func movingGuide(path: [Int], index: Int, to position: Double, in rect: CGRect, gap: Double) -> AlbumNode {
        guard case .split(let axis, let fractions, let children) = self else { return self }
        let rects = Self.childRects(axis: axis, fractions: fractions, count: children.count, in: rect, gap: gap)
        guard rects.count == children.count else { return self }
        if let next = path.first {
            guard children.indices.contains(next) else { return self }
            var newChildren = children
            newChildren[next] = children[next].movingGuide(path: Array(path.dropFirst()), index: index, to: position, in: rects[next], gap: gap)
            return .split(axis: axis, fractions: fractions, children: newChildren)
        }
        guard index >= 0, index + 1 < children.count else { return self }
        let a = rects[index], b = rects[index + 1]
        // Lo que miden juntas las dos casillas vecinas no cambia: solo dónde va la línea entre ellas.
        let (startA, endB) = axis == .columns ? (a.minX, b.maxX) : (a.minY, b.maxY)
        let sizeA = max(1, position - gap / 2 - startA)
        let sizeB = max(1, endB - (position + gap / 2))
        let length = (axis == .columns ? rect.width : rect.height) - gap * Double(children.count - 1)
        let total = fractions.reduce(0, +)
        var newFractions = fractions
        newFractions[index] = sizeA / length * total
        newFractions[index + 1] = sizeB / length * total
        return .split(axis: axis, fractions: newFractions, children: children)
    }

    /// Ruta (índices de hijo) del corte que contiene directamente la casilla `id`.
    func parentPath(of id: UUID, path: [Int] = []) -> [Int]? {
        guard case .split(_, _, let children) = self else { return nil }
        for (i, child) in children.enumerated() {
            if case .cell(let cell) = child, cell.id == id { return path }
            if let found = child.parentPath(of: id, path: path + [i]) { return found }
        }
        return nil
    }

    /// Reparte a partes iguales el corte en `path`.
    func equalizing(path: [Int]) -> AlbumNode {
        guard case .split(let axis, let fractions, let children) = self else { return self }
        if let next = path.first, children.indices.contains(next) {
            var newChildren = children
            newChildren[next] = children[next].equalizing(path: Array(path.dropFirst()))
            return .split(axis: axis, fractions: fractions, children: newChildren)
        }
        return .split(axis: axis, fractions: Array(repeating: 1, count: children.count), children: children)
    }

    /// Proporción natural (ancho / alto) de este trozo si cada casilla tuviera la de su foto, y
    /// el árbol con las partes que la consiguen (galería justificada, sin contar los huecos).
    func fittedToPhotos(_ aspect: (String) -> Double?) -> (node: AlbumNode, aspect: Double) {
        switch self {
        case .cell(let cell):
            return (self, max(cell.photo.flatMap(aspect) ?? 1, 0.05))
        case .split(let axis, _, let children):
            let fitted = children.map { $0.fittedToPhotos(aspect) }
            if axis == .columns {
                // Mismo alto: los anchos van como las proporciones.
                let aspects = fitted.map(\.aspect)
                return (.split(axis: axis, fractions: aspects, children: fitted.map(\.node)), aspects.reduce(0, +))
            } else {
                // Mismo ancho: los altos van como la inversa.
                let inverse = fitted.map { 1 / $0.aspect }
                return (.split(axis: axis, fractions: inverse, children: fitted.map(\.node)), 1 / inverse.reduce(0, +))
            }
        }
    }

    /// Cambia una casilla (por su id).
    func updatingCell(_ id: UUID, _ change: (inout AlbumCell) -> Void) -> AlbumNode {
        switch self {
        case .cell(var cell):
            guard cell.id == id else { return self }
            change(&cell)
            return .cell(cell)
        case .split(let axis, let fractions, let children):
            return .split(axis: axis, fractions: fractions, children: children.map { $0.updatingCell(id, change) })
        }
    }
}

extension AlbumBlock {
    func guides(in content: CGRect, minCell: Double, place: AlbumBlockPlace) -> [AlbumGuide] {
        let gap = AlbumSpec.gapMM
        let frame = frame(in: content)
        var result = node.guides(in: frame, gap: gap, minCell: minCell, place: place)
        // Bordes del bloque, solo si no llena su zona en esa dirección.
        let minW = node.minLength(.columns, gap: gap, minCell: minCell)
        let minH = node.minLength(.rows, gap: gap, minCell: minCell)
        if area.width < 0.999 {
            result.append(AlbumGuide(kind: .edge(place: place, side: .left), axis: .columns, position: frame.minX,
                                     range: Double(content.minX)...Double(max(content.minX, frame.maxX - minW)), span: Double(frame.minY)...Double(frame.maxY)))
            result.append(AlbumGuide(kind: .edge(place: place, side: .right), axis: .columns, position: frame.maxX,
                                     range: Double(min(content.maxX, frame.minX + minW))...Double(content.maxX), span: Double(frame.minY)...Double(frame.maxY)))
        }
        if area.height < 0.999 {
            result.append(AlbumGuide(kind: .edge(place: place, side: .top), axis: .rows, position: frame.minY,
                                     range: Double(content.minY)...Double(max(content.minY, frame.maxY - minH)), span: Double(frame.minX)...Double(frame.maxX)))
            result.append(AlbumGuide(kind: .edge(place: place, side: .bottom), axis: .rows, position: frame.maxY,
                                     range: Double(min(content.maxY, frame.minY + minH))...Double(content.maxY), span: Double(frame.minX)...Double(frame.maxX)))
        }
        return result
    }

    /// Mueve un borde del bloque a `position` (mm).
    func movingEdge(_ side: AlbumGuide.Side, to position: Double, in content: CGRect) -> AlbumBlock {
        var frame = frame(in: content)
        switch side {
        case .left: frame = CGRect(x: position, y: frame.minY, width: frame.maxX - position, height: frame.height)
        case .right: frame.size.width = position - frame.minX
        case .top: frame = CGRect(x: frame.minX, y: position, width: frame.width, height: frame.maxY - position)
        case .bottom: frame.size.height = position - frame.minY
        }
        let area = CGRect(x: (frame.minX - content.minX) / content.width, y: (frame.minY - content.minY) / content.height,
                          width: frame.width / content.width, height: frame.height / content.height)
        return AlbumBlock(node: node, area: area.intersection(AlbumBlock.wholeArea))
    }
}

extension AlbumSpreadLayout {
    /// Casilla mínima al arrastrar guías (mm).
    public static let minCellMM = 15.0
    /// Distancia a la que una guía se pega a algo (mm).
    public static let snapMM = 3.0

    /// Todas las guías que se pueden arrastrar en este pliego.
    public func guides(_ spec: AlbumSpec) -> [AlbumGuide] {
        let minCell = Self.minCellMM
        switch self {
        case .full(let block):
            return block.guides(in: spec.spreadContent, minCell: minCell, place: .full)
        case .pages(let left, let right):
            var result = (left?.guides(in: spec.pageContent(.left), minCell: minCell, place: .left) ?? [])
                + (right?.guides(in: spec.pageContent(.right), minCell: minCell, place: .right) ?? [])
            // El lomo hace de guía si hay fotos a los dos lados: al moverlo se juntan las páginas.
            if let left, let right {
                let content = spec.spreadContent
                let minL = left.node.minLength(.columns, gap: AlbumSpec.gapMM, minCell: minCell)
                let minR = right.node.minLength(.columns, gap: AlbumSpec.gapMM, minCell: minCell)
                result.append(AlbumGuide(kind: .spine, axis: .columns, position: spec.spineCenter,
                                         range: Double(content.minX + minL)...Double(content.maxX - minR), span: Double(content.minY)...Double(content.maxY)))
            }
            return result
        }
    }

    /// Mueve una guía. Devuelve el pliego nuevo y la medida de las dos casillas de los lados.
    public func moving(_ guide: AlbumGuide, to requested: Double, spec: AlbumSpec) -> AlbumGuideMove {
        let position = min(max(requested, guide.range.lowerBound), guide.range.upperBound)
        let gap = AlbumSpec.gapMM
        var layout = self
        switch guide.kind {
        case .spine:
            // Las dos páginas pasan a ser una sola composición que cruza el lomo.
            if case .pages(let left?, let right?) = self {
                let content = spec.spreadContent
                let leftWidth = position - gap / 2 - content.minX
                let rightWidth = content.maxX - position - gap / 2
                layout = .full(AlbumBlock(node: .split(axis: .columns, fractions: [leftWidth, rightWidth], children: [left.node, right.node])))
            }
        case .split(let place, let path, let index):
            layout = updatingBlock(place, spec: spec) { block, content in
                AlbumBlock(node: block.node.movingGuide(path: path, index: index, to: position, in: block.frame(in: content), gap: gap), area: block.area)
            }
        case .edge(let place, let side):
            layout = updatingBlock(place, spec: spec) { block, content in block.movingEdge(side, to: position, in: content) }
        }
        // Medidas de las casillas a cada lado de la línea, para enseñarlas mientras se arrastra.
        let rects = layout.cellRects(spec).map(\.rect)
        let near = rects.filter { r in
            let (lo, hi) = guide.axis == .columns ? (r.minY, r.maxY) : (r.minX, r.maxX)
            return hi > guide.span.lowerBound && lo < guide.span.upperBound
        }
        let before = near.filter { (guide.axis == .columns ? $0.maxX : $0.maxY) <= position + 0.5 }
            .max { (guide.axis == .columns ? $0.maxX : $0.maxY) < (guide.axis == .columns ? $1.maxX : $1.maxY) }
        let after = near.filter { (guide.axis == .columns ? $0.minX : $0.minY) >= position - 0.5 }
            .min { (guide.axis == .columns ? $0.minX : $0.minY) < (guide.axis == .columns ? $1.minX : $1.minY) }
        let size = { (r: CGRect?) -> Double in r.map { guide.axis == .columns ? $0.width : $0.height } ?? 0 }
        return AlbumGuideMove(layout: layout, position: position, before: size(before), after: size(after))
    }

    /// A qué se pega una guía: lomo, centro de cada página, bordes útiles y las demás guías paralelas.
    public func snapTargets(for guide: AlbumGuide, spec: AlbumSpec) -> [Double] {
        var targets: [Double] = []
        if guide.axis == .columns {
            targets += [spec.spineCenter, spec.pageRect(.left).midX, spec.pageRect(.right).midX,
                        spec.spreadContent.minX, spec.spreadContent.maxX,
                        spec.pageContent(.left).maxX, spec.pageContent(.right).minX]
        } else {
            let content = spec.spreadContent
            targets += [spec.pageHeightMM / 2, content.minY, content.maxY]
        }
        targets += guides(spec).filter { $0.axis == guide.axis && $0.kind != guide.kind }.map(\.position)
        return targets
    }

    /// Posición con imán: si hay algo a menos de `snapMM`, se pega a lo más cercano.
    public func snapped(_ position: Double, for guide: AlbumGuide, spec: AlbumSpec) -> (position: Double, snapped: Bool) {
        let nearest = snapTargets(for: guide, spec: spec).min { abs($0 - position) < abs($1 - position) }
        if let nearest, abs(nearest - position) <= Self.snapMM, guide.range.contains(nearest) { return (nearest, true) }
        return (position, false)
    }

    /// Cambia un bloque (el del pliego entero o el de una página).
    func updatingBlock(_ place: AlbumBlockPlace, spec: AlbumSpec, _ change: (AlbumBlock, CGRect) -> AlbumBlock) -> AlbumSpreadLayout {
        switch (self, place) {
        case (.full(let block), .full):
            return .full(change(block, spec.spreadContent))
        case (.pages(let left?, let right), .left):
            return .pages(left: change(left, spec.pageContent(.left)), right: right)
        case (.pages(let left, let right?), .right):
            return .pages(left: left, right: change(right, spec.pageContent(.right)))
        default:
            return self
        }
    }

    /// Cambia una casilla (por su id) esté donde esté.
    public func updatingCell(_ id: UUID, _ change: (inout AlbumCell) -> Void) -> AlbumSpreadLayout {
        switch self {
        case .full(let block):
            return .full(AlbumBlock(node: block.node.updatingCell(id, change), area: block.area))
        case .pages(let left, let right):
            return .pages(left: left.map { AlbumBlock(node: $0.node.updatingCell(id, change), area: $0.area) },
                          right: right.map { AlbumBlock(node: $0.node.updatingCell(id, change), area: $0.area) })
        }
    }

    /// Bloque donde está una casilla.
    func place(of id: UUID) -> AlbumBlockPlace? {
        switch self {
        case .full(let block): return block.cells.contains { $0.id == id } ? .full : nil
        case .pages(let left, let right):
            if left?.cells.contains(where: { $0.id == id }) == true { return .left }
            if right?.cells.contains(where: { $0.id == id }) == true { return .right }
            return nil
        }
    }

    /// «Igualar tamaños»: reparte a partes iguales la fila o columna de la casilla `id`.
    public func equalizing(around id: UUID, spec: AlbumSpec) -> AlbumSpreadLayout {
        guard let place = place(of: id) else { return self }
        return updatingBlock(place, spec: spec) { block, _ in
            guard let path = block.node.parentPath(of: id) else { return block }
            return AlbumBlock(node: block.node.equalizing(path: path), area: block.area)
        }
    }

    /// «Ajustar a las fotos»: cada casilla con la proporción de su foto, sin cambiar la rejilla ni
    /// lo que ocupa cada bloque.
    public func fittedToPhotos(_ aspect: (String) -> Double?, spec: AlbumSpec) -> AlbumSpreadLayout {
        func fit(_ block: AlbumBlock) -> AlbumBlock { AlbumBlock(node: block.node.fittedToPhotos(aspect).node, area: block.area) }
        switch self {
        case .full(let block): return .full(fit(block))
        case .pages(let left, let right): return .pages(left: left.map { fit($0) }, right: right.map { fit($0) })
        }
    }

    /// Cambia la foto de una casilla (y le quita el encuadre a mano, que era de la otra foto).
    public func settingPhoto(_ photo: String?, in id: UUID) -> AlbumSpreadLayout {
        updatingCell(id) { cell in
            cell.photo = photo
            cell.focus = nil
            cell.zoom = nil
            cell.locked = false
        }
    }
}

// MARK: - Dividir, fusionar y quitar casillas (como las celdas de una tabla)

/// Lado de una casilla con el que se fusiona.
public enum AlbumMergeSide: String, Sendable, CaseIterable {
    case left, right, top, bottom

    /// Las vecinas a izquierda y derecha están en un corte en columnas; arriba y abajo, en filas.
    var axis: AlbumSplitAxis { self == .left || self == .right ? .columns : .rows }
    var offset: Int { self == .left || self == .top ? -1 : 1 }
}

extension AlbumNode {
    func contains(_ id: UUID) -> Bool { cells.contains { $0.id == id } }

    /// Un corte con un solo hijo es ese hijo.
    private static func simplified(axis: AlbumSplitAxis, fractions: [Double], children: [AlbumNode]) -> AlbumNode? {
        switch children.count {
        case 0: return nil
        case 1: return children[0]
        default: return .split(axis: axis, fractions: fractions, children: children)
        }
    }

    /// Parte la casilla `id` en dos (la nueva, vacía, a la derecha o debajo). Si ya está en un
    /// corte del mismo sentido, la nueva se añade a él y se reparten su parte a medias.
    func splitting(_ id: UUID, axis: AlbumSplitAxis) -> AlbumNode {
        switch self {
        case .cell(let cell):
            guard cell.id == id else { return self }
            return .split(axis: axis, fractions: [1, 1], children: [self, .cell(AlbumCell(photo: nil))])
        case .split(let own, var fractions, var children):
            if own == axis, let i = children.firstIndex(where: { if case .cell(let c) = $0 { return c.id == id }; return false }) {
                let half = fractions[i] / 2
                fractions[i] = half
                fractions.insert(half, at: i + 1)
                children.insert(.cell(AlbumCell(photo: nil)), at: i + 1)
                return .split(axis: own, fractions: fractions, children: children)
            }
            return .split(axis: own, fractions: fractions, children: children.map { $0.splitting(id, axis: axis) })
        }
    }

    /// Fusiona la casilla `id` con la vecina de ese lado, si es una casilla del mismo corte (comparte
    /// todo el lado). Se queda la foto de `id` o, si está vacía, la de la vecina; si las dos tenían,
    /// la de la vecina queda desplazada. `nil` si no se puede (o se perdería una foto fijada).
    func merging(_ id: UUID, side: AlbumMergeSide) -> (node: AlbumNode, displaced: String?)? {
        guard case .split(let own, var fractions, var children) = self else { return nil }
        if own == side.axis, let i = children.firstIndex(where: { if case .cell(let c) = $0 { return c.id == id }; return false }) {
            let j = i + side.offset
            guard children.indices.contains(j), case .cell(let other) = children[j], case .cell(var keep) = children[i] else { return nil }
            var displaced: String?
            if keep.photo == nil {
                // La elegida está vacía: se queda la foto de la vecina (con su encuadre y su candado).
                let kept = keep.id
                keep = other
                keep.id = kept
            } else if let photo = other.photo {
                guard !other.locked else { return nil }
                displaced = photo
            }
            children[i] = .cell(keep)
            fractions[i] += fractions[j]
            fractions.remove(at: j)
            children.remove(at: j)
            guard let node = Self.simplified(axis: own, fractions: fractions, children: children) else { return nil }
            return (node, displaced)
        }
        for (index, child) in children.enumerated() where child.contains(id) {
            guard let merged = child.merging(id, side: side) else { return nil }
            children[index] = merged.node
            return (.split(axis: own, fractions: fractions, children: children), merged.displaced)
        }
        return nil
    }

    /// Quita la casilla `id`: su parte se la quedan las vecinas. Devuelve el árbol que queda (`nil`
    /// si no queda nada) y la foto que tenía.
    func removing(_ id: UUID) -> (node: AlbumNode?, displaced: String?) {
        switch self {
        case .cell(let cell):
            return cell.id == id ? (nil, cell.photo) : (self, nil)
        case .split(let own, var fractions, var children):
            guard let i = children.firstIndex(where: { $0.contains(id) }) else { return (self, nil) }
            let removed = children[i].removing(id)
            if let node = removed.node {
                children[i] = node
            } else {
                children.remove(at: i)
                fractions.remove(at: i)
            }
            return (Self.simplified(axis: own, fractions: fractions, children: children), removed.displaced)
        }
    }
}

extension AlbumSpreadLayout {
    /// Cambia el árbol del bloque donde está la casilla `id` (o `nil` si el bloque se queda vacío).
    private func changingBlock(of id: UUID, _ change: (AlbumNode) -> AlbumNode?) -> AlbumSpreadLayout {
        switch self {
        case .full(let block):
            return change(block.node).map { .full(AlbumBlock(node: $0, area: block.area)) } ?? .empty
        case .pages(let left, let right):
            if let left, left.node.contains(id) {
                return .pages(left: change(left.node).map { AlbumBlock(node: $0, area: left.area) }, right: right)
            }
            if let right, right.node.contains(id) {
                return .pages(left: left, right: change(right.node).map { AlbumBlock(node: $0, area: right.area) })
            }
            return self
        }
    }

    /// «Dividir en columnas / en filas»: sale una casilla vacía a la derecha o debajo.
    public func splitting(_ id: UUID, axis: AlbumSplitAxis) -> AlbumSpreadLayout {
        changingBlock(of: id) { $0.splitting(id, axis: axis) }
    }

    /// «Fusionar con la de…». `nil` si no hay vecina con la que fusionar por ese lado.
    public func merging(_ id: UUID, side: AlbumMergeSide) -> (layout: AlbumSpreadLayout, displaced: String?)? {
        var displaced: String?
        var possible = false
        let layout = changingBlock(of: id) { node in
            guard let merged = node.merging(id, side: side) else { return node }
            possible = true
            displaced = merged.displaced
            return merged.node
        }
        return possible ? (layout, displaced) : nil
    }

    /// «Quitar casilla»: su sitio se lo quedan las vecinas. `nil` si tiene una foto fijada.
    public func removing(_ id: UUID) -> (layout: AlbumSpreadLayout, displaced: String?)? {
        guard let cell = cells.first(where: { $0.id == id }), !(cell.locked && cell.photo != nil) else { return nil }
        var displaced: String?
        let layout = changingBlock(of: id) { node in
            let removed = node.removing(id)
            displaced = removed.displaced
            return removed.node
        }
        return (layout, displaced)
    }
}
