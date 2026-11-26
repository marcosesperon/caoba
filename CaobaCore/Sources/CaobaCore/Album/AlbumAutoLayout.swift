import Foundation
import CoreGraphics

/// Reparto automático del álbum. No hay un número fijo de fotos por pliego: se analiza la tira
/// y se buscan los cortes que mejor salen en conjunto, sin cambiar nunca el orden.
///
/// Cada pliego posible se puntúa (cuanto menos, mejor) por:
/// - **encaje**: lo que hay que recortar a cada foto para que entre en su casilla, y que el
///   recorte no se coma las caras;
/// - **espacio**: que ninguna cara quede diminuta una vez impresa (se mira en mm reales) y que
///   ninguna foto quede en una casilla enana;
/// - **momento**: cortar en un salto de tiempo grande (cambio de escena) cuesta menos que
///   cortar en medio de una ráfaga;
/// - **lomo**: una foto que cruza el lomo no puede dejar caras en su franja, y ningún borde de
///   casilla debería caer dentro de ella.
///
/// Cada pliego se compone página a página o entero, cruzando el lomo con una o varias fotos, y
/// con las formas propias (filas o columnas justificadas) o con plantillas de collage.
///
/// Con número de pliegos fijo se busca el mejor reparto con exactamente esos; sin él, cada
/// pliego tiene un pequeño coste y el propio análisis decide cuántos hacen falta. Los pliegos
/// con candado no se tocan y las fotos con candado se quedan en su casilla (fase 2).
public enum AlbumAutoLayout {
    /// Una foto de la tira con su análisis.
    public struct Photo: Sendable, Equatable {
        public var name: String
        public var info: AlbumPhotoInfo

        public init(name: String, info: AlbumPhotoInfo) {
            self.name = name
            self.info = info
        }
    }

    // MARK: - Pesos (ajustados con los tests; mejor tocarlos con cuidado)

    /// Coste de cada pliego cuando no hay número fijo: sin él, todo saldría a una foto por pliego.
    static let spreadCost = 1.6
    /// Una página en blanco en medio del álbum.
    static let blankPageCost = 3.0
    /// Cara más pequeña aceptable impresa (mm de alto). Por debajo ya no se reconoce a nadie.
    static let minFaceMM = 10.0
    /// Lado corto cómodo de una casilla, en parte del alto útil de la página.
    static let comfortableSide = 0.5

    /// Alto de cara que ya se ve cómodo impreso: un retrato pide la cara grande; en un grupo,
    /// cada cara puede ser más pequeña.
    static func comfortableFaceMM(faces: Int) -> Double {
        switch faces {
        case ...2: return 30
        case 3...6: return 20
        default: return 14
        }
    }
    /// Más fotos que esto en una página ya no se prueba.
    static let maxPerPage = 6
    /// Más fotos que esto en una composición de pliego entero ya no se prueba.
    static let maxFullSpread = 6
    /// Blanco alrededor de una composición que no llena la página (por cada página entera vacía).
    static let whiteSpaceCost = 1.5
    /// Cada cara que cae en la franja del lomo: se pierde en el pliegue.
    static let spineFaceCost = 8.0
    /// Un borde de casilla dentro de la franja del lomo (un corte justo en el pliegue).
    static let spineEdgeCost = 3.0
    /// Pequeña preferencia por componer página a página cuando todo lo demás empata.
    static let fullSpreadBias = 0.15
    /// Proporción a partir de la cual una foto es panorámica y pide el ancho del pliego.
    static let panoramaAspect = 2.0
    /// Lo que cuesta que una foto con candado cambie de casilla: por lo que se mueven sus bordes,
    /// en parte del ancho del pliego.
    static let anchorMoveCost = 20.0

    // MARK: - Entrada principal

    /// Rehace el reparto desde el pliego `start`. Los anteriores se quedan tal cual (sus fotos
    /// tienen que ser el principio de la tira). Desde ahí:
    /// - los pliegos con candado se quedan como están y parten el álbum en tramos, cada uno con
    ///   las fotos de la tira que le tocan;
    /// - si el pliego `start` tiene un número de fotos pedido a mano, lo respeta;
    /// - las fotos con candado se quedan en su casilla y las demás se colocan alrededor.
    public static func redistribute(_ document: AlbumDocument, from start: Int = 0) -> [AlbumSpread] {
        let info = { (name: String) in document.info[name] ?? AlbumPhotoInfo(aspect: 1.5, captureDate: .distantPast) }
        var kept = Array(document.spreads.prefix(max(0, start)))
        // Lo que se queda tiene que coincidir con el principio de la tira; si no, se recorta.
        while !kept.isEmpty, Array(document.photos.prefix(kept.flatMap(\.photos).count)) != kept.flatMap(\.photos) {
            kept.removeLast()
        }
        let rest = Array(document.spreads.dropFirst(kept.count))
        let strip = Array(document.photos.dropFirst(kept.flatMap(\.photos).count))
        let position = Dictionary(strip.enumerated().map { ($1, $0) }, uniquingKeysWith: { a, _ in a })

        // Tramos: lo que hay entre pliegos con candado.
        struct Run { var spreads: [AlbumSpread]; var locked: AlbumSpread?; var before = 0 }
        var runs: [Run] = [Run(spreads: [], locked: nil)]
        // Fotos que hay delante de cada pliego: un pliego con candado sin fotos (casillas vacías)
        // no tiene sitio en la tira, así que se queda donde está con las que tenía delante.
        var placedBefore = 0
        for spread in rest {
            defer { placedBefore += spread.photos.count }
            // Con candado y algo dentro (fotos o, en un pliego maquetado a mano, casillas vacías).
            if spread.locked && !spread.layout.cells.isEmpty {
                runs[runs.count - 1].locked = spread
                runs[runs.count - 1].before = placedBefore
                runs.append(Run(spreads: [], locked: nil))
            } else {
                runs[runs.count - 1].spreads.append(spread)
            }
        }
        let lockedPhotos = Set(runs.compactMap(\.locked).flatMap(\.photos))
        // Cada foto libre va al tramo que le toca por su sitio en la tira: antes de la primera foto
        // del pliego con candado que cierra el tramo.
        let bounds = runs.map { run in
            run.locked.map { $0.photos.compactMap { position[$0] }.min() ?? run.before } ?? Int.max
        }
        var pools = Array(repeating: [Photo](), count: runs.count)
        for name in strip where !lockedPhotos.contains(name) {
            let p = position[name] ?? Int.max
            let index = bounds.firstIndex { p < $0 } ?? runs.count - 1
            pools[index].append(Photo(name: name, info: info(name)))
        }

        // Pliegos de cada tramo. Entre dos candados se mantienen los que había; el último tramo
        // tiene los que falten hasta el número del álbum (o los que hagan falta, sin número).
        var counts: [Int?] = runs.enumerated().map { r, run in
            r < runs.count - 1 ? (run.spreads.isEmpty ? nil : run.spreads.count) : nil
        }
        if let total = document.spec.spreads {
            let fixed = kept.count + runs.compactMap(\.locked).count + counts.dropLast().compactMap { $0 }.reduce(0, +)
            var remaining = total - fixed
            // Si el último tramo no tiene fotos (el último pliego tiene candado), los pliegos de
            // más o de menos van al último tramo que sí las tiene: si no, saldrían en blanco detrás.
            if pools[runs.count - 1].isEmpty, let target = pools.indices.dropLast().last(where: { !pools[$0].isEmpty }) {
                counts[target] = max(1, (counts[target] ?? 0) + remaining)
                remaining = 0
            }
            counts[runs.count - 1] = remaining > 0 ? remaining : nil
        }

        var result = kept
        for (r, run) in runs.enumerated() {
            let count = counts[r]
            // Fotos pedidas a mano en cada pliego del tramo (por su sitio dentro del tramo).
            let required = Dictionary(run.spreads.enumerated().compactMap { i, spread in spread.manualCount.map { (i, $0) } },
                                      uniquingKeysWith: { a, _ in a })
            // Primer y último pliego de una página: el primero del álbum y el último del último tramo.
            let single = document.spec.singleFirstLast
            var spreads = solveRun(pools[r], old: run.spreads, count: count, required: required, spec: document.spec,
                                   firstSingle: single && result.isEmpty, lastSingle: single && r == runs.count - 1)
            // Con número fijo y menos fotos que pliegos, los que faltan salen en blanco.
            if let count, spreads.count < count {
                spreads += (spreads.count..<count).map { i in AlbumSpread(id: run.spreads.indices.contains(i) ? run.spreads[i].id : UUID()) }
            }
            result += spreads
            if let locked = run.locked { result.append(locked) }
        }
        return result
    }

    /// Reparte las fotos (en orden) en pliegos. `spreadCount` fija cuántos; `nil` = los que hagan falta.
    public static func distribute(_ photos: [Photo], spec: AlbumSpec, spreadCount: Int? = nil) -> [AlbumSpread] {
        solveRun(photos, old: [], count: spreadCount, required: [:], spec: spec, firstSingle: spec.singleFirstLast, lastSingle: spec.singleFirstLast)
    }

    /// La mejor composición de un pliego para estas fotos (sin mirar los cortes con sus vecinos).
    public static func bestSpread(_ photos: [Photo], spec: AlbumSpec) -> (spread: AlbumSpread, cost: Double) {
        guard !photos.isEmpty else { return (AlbumSpread(), blankPageCost * 2) }
        return Planner(photos: photos, spec: spec).bestSpread(start: 0, count: photos.count)
    }

    /// «Otras composiciones»: las mejores formas de componer este pliego con sus mismas fotos,
    /// de mejor a peor y sin repetidas. Si hay fotos con candado, se prefieren las que las dejan
    /// donde estaban.
    public static func alternatives(for spread: AlbumSpread, document: AlbumDocument, spec: AlbumSpec? = nil,
                                    side: AlbumPageSide? = nil, limit: Int = 24) -> [AlbumSpreadLayout] {
        let spec = spec ?? document.spec
        let photos = spread.photos.map { Photo(name: $0, info: document.info[$0] ?? AlbumPhotoInfo(aspect: 1.5, captureDate: .distantPast)) }
        guard !photos.isEmpty else { return [] }
        let planner = Planner(photos: photos, spec: spec)
        let anchor = Anchor(spread: spread, spec: spec)
        return planner.ranked(start: 0, count: photos.count, limit: limit, anchor: anchor.isEmpty ? nil : anchor, side: side).map(\.spread.layout)
    }

    /// Composiciones con `count` casillas vacías, de mejor a peor: la rejilla de partida de un
    /// pliego vacío y sus «otras composiciones». Se calculan con fotos de relleno en 3:2 y luego
    /// se vacían. Con `side`, solo esa página (pliegos de una página).
    public static func emptyLayouts(count: Int, spec: AlbumSpec, side: AlbumPageSide? = nil, limit: Int = 24) -> [AlbumSpreadLayout] {
        guard count > 0 else { return [] }
        let fillers = (0..<count).map { Photo(name: "·\($0)", info: AlbumPhotoInfo(aspect: 1.5, captureDate: .distantPast, faces: [])) }
        // Se calcula la lista entera y luego se ordena: con `limit` 1 solo saldría la mejor, aunque cruzara.
        let ranked = Planner(photos: fillers, spec: spec).ranked(start: 0, count: count, limit: max(limit, 24), anchor: nil, side: side)
        // Sin fotos no se sabe dónde caerán las caras: primero las de página a página, para que la
        // de partida no tenga una casilla cruzando el lomo (siguen en «otras composiciones»).
        let crosses = { (layout: AlbumSpreadLayout) -> Bool in if case .full = layout { return true }; return false }
        let options = Array((ranked.filter { !crosses($0.spread.layout) } + ranked.filter { crosses($0.spread.layout) }).prefix(limit))
        return options.map { option in
            option.spread.layout.cells.reduce(option.spread.layout) { layout, cell in layout.updatingCell(cell.id) { $0.photo = nil } }
        }
    }

    /// El pliego con una foto más, con su mejor composición. Las fotos van en el orden de la tira
    /// (la nueva, si no está en ella, al final) y las fijadas se quedan donde estaban.
    public static func recomposed(_ spread: AlbumSpread, adding photo: String, document: AlbumDocument,
                                  spec: AlbumSpec? = nil, side: AlbumPageSide? = nil) -> AlbumSpreadLayout {
        let spec = spec ?? document.spec
        let order = Dictionary(document.photos.enumerated().map { ($1, $0) }, uniquingKeysWith: { a, _ in a })
        let names = (spread.photos.filter { $0 != photo } + [photo])
            .sorted { (order[$0] ?? Int.max) < (order[$1] ?? Int.max) }
        let photos = names.map { Photo(name: $0, info: document.info[$0] ?? AlbumPhotoInfo(aspect: 1.5, captureDate: .distantPast)) }
        let anchor = Anchor(spread: spread, spec: spec)
        let planner = Planner(photos: photos, spec: spec)
        return planner.ranked(start: 0, count: photos.count, limit: 1, anchor: anchor.isEmpty ? nil : anchor, side: side).first?.spread.layout
            ?? spread.layout
    }

    /// Un pliego con `cells` casillas y estas fotos en orden: si hay menos fotos, las casillas de
    /// más quedan vacías; si hay más, se usan las primeras. Las fijadas de `keeping` se quedan donde
    /// estaban. Para el número de fotos en manual.
    public static func composed(_ photos: [String], cells: Int, document: AlbumDocument, keeping spread: AlbumSpread? = nil,
                                spec: AlbumSpec? = nil, side: AlbumPageSide? = nil) -> AlbumSpreadLayout {
        composedOptions(photos, cells: cells, document: document, keeping: spread, spec: spec, side: side).first ?? .empty
    }

    /// Las composiciones con `cells` casillas para estas fotos, de mejor a peor y con las casillas
    /// de más vacías. Primero las que no tienen ninguna casilla vacía tocando el lomo (no se sabe
    /// qué foto irá ahí). Para «otras composiciones» de un pliego con casillas vacías.
    public static func composedOptions(_ photos: [String], cells: Int, document: AlbumDocument, keeping spread: AlbumSpread? = nil,
                                       spec: AlbumSpec? = nil, side: AlbumPageSide? = nil, limit: Int = 24) -> [AlbumSpreadLayout] {
        let spec = spec ?? document.spec
        guard cells > 0 else { return [] }
        let real = photos.prefix(cells).map { Photo(name: $0, info: document.info[$0] ?? AlbumPhotoInfo(aspect: 1.5, captureDate: .distantPast)) }
        // Las casillas de más, como fotos 3:2 «sin analizar»: así no cruzan el lomo y no deciden
        // la composición por su cuenta.
        let fillers = (real.count..<cells).map { Photo(name: "·\($0)", info: AlbumPhotoInfo(aspect: 1.5, captureDate: .distantPast)) }
        let all = real + fillers
        let anchor = spread.map { Anchor(spread: $0, spec: spec) }
        let planner = Planner(photos: all, spec: spec)
        let fillerNames = Set(fillers.map(\.name))
        let options = planner.ranked(start: 0, count: all.count, limit: max(limit, 24), anchor: anchor?.isEmpty == false ? anchor : nil, side: side)
            .map(\.spread.layout)
        let strip = spec.spineStrip
        let touches = { (layout: AlbumSpreadLayout) -> Bool in
            layout.cellRects(spec).contains { ($0.cell.photo.map(fillerNames.contains) ?? false) && $0.rect.intersects(strip) }
        }
        let ordered = options.filter { !touches($0) } + options.filter(touches)
        return ordered.prefix(limit).map { layout in
            layout.cells.reduce(layout) { result, cell in
                guard let photo = cell.photo, fillerNames.contains(photo) else { return result }
                return result.updatingCell(cell.id) { $0.photo = nil }
            }
        }
    }

    /// Lo que se enseña debajo del pliego para que el reparto no sea una caja negra.
    static func reason(for photos: [Photo], chosen spread: AlbumSpread) -> AlbumSpreadReason {
        if photos.count == 1, let only = photos.first {
            if only.info.aspect >= panoramaAspect { return .panorama }
            if only.info.faceCount >= 6 { return .group(faces: only.info.faceCount) }
        }
        // De la más antigua a la más nueva (si se han movido a mano, pueden no ir en orden).
        let dates = photos.map(\.info.captureDate).filter { $0 != .distantPast }
        if photos.count >= 2, dates.count == photos.count, let first = dates.min(), let last = dates.max(),
           last.timeIntervalSince(first) <= 60 {
            return .sameMoment(seconds: Int(last.timeIntervalSince(first).rounded()))
        }
        return .bestFit
    }

    // MARK: - Un tramo de la tira

    /// Fotos con candado de un pliego sin candado: tienen que seguir en ese pliego y en su casilla.
    struct Anchor {
        var spreadID: UUID
        /// Foto → su casilla (con su encuadre) y dónde estaba, en mm.
        var cells: [String: (cell: AlbumCell, rect: CGRect)]
        /// La rejilla que tenía el pliego, por si sigue con el mismo número de fotos.
        var layout: AlbumSpreadLayout
        var count: Int

        init(spread: AlbumSpread, spec: AlbumSpec) {
            spreadID = spread.id
            layout = spread.layout
            count = spread.photos.count
            var cells: [String: (cell: AlbumCell, rect: CGRect)] = [:]
            for entry in spread.layout.cellRects(spec) where entry.cell.locked {
                if let photo = entry.cell.photo { cells[photo] = (entry.cell, entry.rect) }
            }
            self.cells = cells
        }

        var isEmpty: Bool { cells.isEmpty }
    }

    /// Reparte un tramo: `old` son sus pliegos de antes (para conservar ids y fotos con candado) y
    /// `required`, las fotos pedidas a mano en algunos de ellos (por su sitio en el tramo).
    static func solveRun(_ photos: [Photo], old: [AlbumSpread], count: Int?, required: [Int: Int], spec: AlbumSpec,
                         firstSingle: Bool = false, lastSingle: Bool = false) -> [AlbumSpread] {
        guard !photos.isEmpty else { return [] }
        // Fotos con candado de los pliegos de este tramo.
        var anchors: [UUID: Anchor] = [:]
        var anchorOf: [Int: UUID] = [:]
        let index = Dictionary(photos.enumerated().map { ($1.name, $0) }, uniquingKeysWith: { a, _ in a })
        for spread in old where spread.hasLockedPhotos {
            let anchor = Anchor(spread: spread, spec: spec)
            anchors[spread.id] = anchor
            for photo in anchor.cells.keys { if let i = index[photo] { anchorOf[i] = spread.id } }
        }
        let planner = Planner(photos: photos, spec: spec, anchors: anchors, anchorOf: anchorOf, firstSingle: firstSingle, lastSingle: lastSingle)
        let maxPerSpread = maxPerPage * 2
        let wanted = required.mapValues { min(max($0, 1), maxPerSpread) }
        var cuts: [Int]?
        if let count, count >= 1 {
            let spreads = min(count, photos.count)
            if photos.count <= spreads * maxPerSpread {
                cuts = planner.fixedCuts(spreads: spreads, maxPerSpread: maxPerSpread, required: wanted)
                    ?? planner.fixedCuts(spreads: spreads, maxPerSpread: maxPerSpread)
            }
        }
        let finalCuts = cuts ?? planner.freeCuts(maxPerSpread: maxPerSpread, required: wanted)
        var result: [AlbumSpread] = []
        var start = 0
        for (i, end) in finalCuts.enumerated() {
            let segment = Array(photos[start..<end])
            var best = planner.spreadForSegment(start: start, count: end - start, side: planner.side(start: start, end: end))
            if let manual = required[i], wanted[i] == end - start {
                best.spread.manualCount = manual
                best.spread.reason = .manualCount
            } else {
                best.spread.reason = reason(for: segment, chosen: best.spread)
            }
            // El id: el del pliego con fotos fijadas que le toca o, si no, el del mismo sitio.
            if let anchorID = planner.anchorID(start: start, end: end) {
                best.spread.id = anchorID
            } else if old.indices.contains(i), anchors[old[i].id] == nil {
                best.spread.id = old[i].id
            }
            result.append(best.spread)
            start = end
        }
        return result
    }

    // MARK: - Geometría del encuadre

    /// Parte visible de una foto (0-1 sobre la foto) en una casilla de otra proporción, centrada
    /// en `focus` sin salirse de la foto, con `zoom` (1 = justo lo que llena la casilla). Es la
    /// misma cuenta que `CropGeometry.rect`.
    public static func visibleRegion(photoAspect: Double, cellAspect: Double, focus: CGPoint, zoom: Double = 1) -> CGRect {
        var w = 1.0, h = 1.0
        if cellAspect > photoAspect { h = photoAspect / cellAspect } else { w = cellAspect / photoAspect }
        let scale = max(1, zoom)
        w /= scale
        h /= scale
        let x = min(max(0, focus.x - w / 2), 1 - w)
        let y = min(max(0, focus.y - h / 2), 1 - h)
        return CGRect(x: x, y: y, width: w, height: h)
    }

    // MARK: - Coste de una foto en una casilla

    /// Cambiar de vertical a apaisada (o al revés) cuesta tanto que solo pasa si no hay otra salida.
    static let orientationMismatchCost = 25.0
    /// Margen de «casi cuadrada»: entre 0,9 y 1,1 vale para las dos orientaciones.
    static func isVertical(_ aspect: Double) -> Bool { aspect < 0.9 }
    static func isHorizontal(_ aspect: Double) -> Bool { aspect > 1.1 }

    /// Cuánto «molesta» poner esta foto en una casilla de este tamaño (mm). `pageHeight` es el
    /// alto útil de la página, para medir lo cómoda que es la casilla, y `spreadWidth` el ancho
    /// útil del pliego, que es lo que pide una panorámica.
    static func cellCost(_ info: AlbumPhotoInfo, rect: CGRect, pageHeight: Double, spreadWidth: Double) -> Double {
        guard rect.width > 1, rect.height > 1 else { return 50 }
        let cellAspect = rect.width / rect.height
        let photoAspect = max(info.aspect, 0.01)
        let ratio = abs(log(cellAspect / photoAspect))
        // Recorte: crece deprisa, para que una vertical no acabe en una casilla apaisada.
        var cost = ratio * 1.2 + ratio * ratio * 2.5
        // Una vertical nunca en una casilla apaisada, ni al revés (las casi cuadradas valen para
        // las dos). Un recorte moderado sí, centrado en lo principal (`visibleRegion` con el foco).
        if isVertical(photoAspect) && isHorizontal(cellAspect) || isHorizontal(photoAspect) && isVertical(cellAspect) {
            cost += orientationMismatchCost
        }
        let focus = info.focus ?? CGPoint(x: 0.5, y: 0.5)
        let visible = visibleRegion(photoAspect: photoAspect, cellAspect: cellAspect, focus: focus)
        // Que el recorte no corte caras.
        if let box = info.facesBox?.insetBy(dx: -0.02, dy: -0.02), !visible.contains(box) {
            let inside = visible.intersection(box)
            let lost = 1 - (inside.isNull ? 0 : (inside.width * inside.height) / max(box.width * box.height, 0.0001))
            cost += 6 * lost
        }
        // Una panorámica encogida en media página pierde todo su sentido.
        if photoAspect >= panoramaAspect {
            let wanted = 0.9 * spreadWidth
            if rect.width < wanted { cost += 10 * (wanted - rect.width) / wanted }
        }
        // Alto que tendría la foto entera impresa en esta casilla.
        let printedHeight = rect.height / visible.height
        if let smallest = info.smallestFace, smallest > 0 {
            let faceMM = smallest * printedHeight
            if faceMM < minFaceMM {
                let miss = (minFaceMM - faceMM) / minFaceMM
                cost += 4 + 8 * miss
            } else {
                let comfortable = comfortableFaceMM(faces: info.faceCount)
                if faceMM < comfortable {
                    let miss = (comfortable - faceMM) / comfortable
                    cost += 6 * miss * miss + 2 * miss
                }
            }
        }
        // Y ninguna foto, con caras o sin ellas, en una casilla enana.
        let comfortable = comfortableSide * pageHeight
        let side = min(rect.width, rect.height)
        if side < comfortable {
            let miss = (comfortable - side) / comfortable
            cost += 6 * miss * miss + 2 * miss
        }
        return cost
    }

    // MARK: - Planificador (con cachés: cada trozo de la tira se compone una sola vez)

    final class Planner {
        let photos: [Photo]
        let spec: AlbumSpec
        let anchors: [UUID: Anchor]
        /// Índice en `photos` de cada foto con candado → su pliego.
        let anchorOf: [Int: UUID]
        private var pageCache: [Int: [(block: AlbumBlock, cost: Double)]] = [:]
        private var spreadCache: [Int: (spread: AlbumSpread, cost: Double)] = [:]
        private var segmentCache: [Int: (spread: AlbumSpread, cost: Double)] = [:]

        /// El primer trozo de la tira es el primer pliego del álbum, de una página (la derecha); el
        /// último, el último, de una página (la izquierda).
        let firstSingle: Bool
        let lastSingle: Bool

        init(photos: [Photo], spec: AlbumSpec, anchors: [UUID: Anchor] = [:], anchorOf: [Int: UUID] = [:],
             firstSingle: Bool = false, lastSingle: Bool = false) {
            self.photos = photos
            self.spec = spec
            self.anchors = anchors
            self.anchorOf = anchorOf
            self.firstSingle = firstSingle
            self.lastSingle = lastSingle
        }

        /// Qué página se usa en el trozo `start..<end`, si es un pliego de una página.
        func side(start: Int, end: Int) -> AlbumPageSide? {
            if firstSingle && start == 0 { return .right }
            if lastSingle && end == photos.count { return .left }
            return nil
        }

        // MARK: Candados dentro del tramo

        /// Pliego con fotos fijadas al que pertenece el trozo `start..<end`, si lleva alguna.
        func anchorID(start: Int, end: Int) -> UUID? {
            (start..<end).lazy.compactMap { self.anchorOf[$0] }.first
        }

        /// Un trozo vale si no mezcla fotos fijadas de dos pliegos y, si lleva alguna, las lleva todas.
        func isValid(start: Int, end: Int) -> Bool {
            let ids = Set((start..<end).compactMap { anchorOf[$0] })
            guard ids.count <= 1 else { return false }
            guard let id = ids.first else { return true }
            return anchorOf.allSatisfy { $0.value != id || (start..<end).contains($0.key) }
        }

        /// El pliego para un trozo, respetando las fotos fijadas si las lleva.
        func spreadForSegment(start: Int, count: Int, side: AlbumPageSide? = nil) -> (spread: AlbumSpread, cost: Double) {
            let key = (start * 1000 + count) * 3 + (side == nil ? 0 : side == .left ? 1 : 2)
            if let cached = segmentCache[key] { return cached }
            let result: (spread: AlbumSpread, cost: Double)
            if let id = anchorID(start: start, end: start + count), let anchor = anchors[id] {
                if count == anchor.count {
                    // Mismo número de fotos: se queda la rejilla y solo cambian las fotos libres.
                    var free = (start..<start + count).map { photos[$0].name }.filter { anchor.cells[$0] == nil }[...]
                    var layout = anchor.layout
                    for cell in anchor.layout.cells where !cell.locked {
                        let next = free.popFirst()
                        layout = layout.updatingCell(cell.id) { c in
                            if c.photo != next { c.photo = next; c.focus = nil; c.zoom = nil }
                        }
                    }
                    result = (AlbumSpread(layout: layout), cost(of: layout, start: start, count: count))
                } else {
                    result = ranked(start: start, count: count, limit: 1, anchor: anchor, side: side).first ?? bestSpread(start: start, count: count, side: side)
                }
            } else {
                result = bestSpread(start: start, count: count, side: side)
            }
            segmentCache[key] = result
            return result
        }

        /// Coste de un pliego ya compuesto (para compararlo con los demás).
        func cost(of layout: AlbumSpreadLayout, start: Int, count: Int) -> Double {
            let infos = Dictionary((start..<start + count).map { (photos[$0].name, photos[$0].info) }, uniquingKeysWith: { a, _ in a })
            let page = spec.pageContent(.left).height
            return layout.cellRects(spec).reduce(0.0) { total, entry in
                total + (entry.cell.photo.flatMap { infos[$0] }.map { cellCost($0, rect: entry.rect, pageHeight: page, spreadWidth: spec.spreadContent.width) } ?? 0)
            }
        }

        // MARK: Cortes de la tira

        /// Coste de cortar entre la foto `index - 1` y la `index`: barato si hay un salto de
        /// tiempo grande, caro en medio de una ráfaga.
        func cutCost(at index: Int) -> Double {
            guard index > 0, index < photos.count else { return 0 }
            let a = photos[index - 1].info.captureDate, b = photos[index].info.captureDate
            guard a != .distantPast, b != .distantPast else { return 0 }
            let gap = abs(b.timeIntervalSince(a))
            return 0.9 * exp(-gap / 90)
        }

        /// Coste de un pliego con las fotos `start..<start+count`, con sus saltos de escena dentro.
        func segmentCost(start: Int, count: Int) -> Double {
            guard isValid(start: start, end: start + count) else { return .infinity }
            let side = side(start: start, end: start + count)
            // Un pliego de una página no lleva más fotos de las que caben en una página.
            if side != nil && count > maxPerPage { return .infinity }
            var cost = spreadForSegment(start: start, count: count, side: side).cost
            // Un cambio de escena dentro del mismo pliego tampoco queda bien.
            for i in (start + 1)..<(start + count) {
                let a = photos[i - 1].info.captureDate, b = photos[i].info.captureDate
                guard a != .distantPast, b != .distantPast else { continue }
                cost += 0.5 * (1 - exp(-abs(b.timeIntervalSince(a)) / 900))
            }
            return cost
        }

        /// Tabla de la programación dinámica: `best[s][j]` es lo mejor para poner las `j` primeras
        /// fotos en `s` pliegos. `required` fija las fotos de algunos pliegos (desde 0).
        private func table(spreads: Int, maxPerSpread: Int, required: [Int: Int]) -> (best: [[Double]], from: [[Int]]) {
            let n = photos.count
            let inf = Double.infinity
            var best = Array(repeating: Array(repeating: inf, count: n + 1), count: spreads + 1)
            var from = Array(repeating: Array(repeating: -1, count: n + 1), count: spreads + 1)
            best[0][0] = 0
            for s in 1...max(spreads, 1) where spreads >= 1 {
                for j in s...max(n, s) where j <= n {
                    for k in 1...min(maxPerSpread, j) {
                        let i = j - k
                        if let wanted = required[s - 1], k != wanted { continue }
                        guard best[s - 1][i] < inf else { continue }
                        let cost = best[s - 1][i] + segmentCost(start: i, count: k) + cutCost(at: i)
                        if cost < best[s][j] { best[s][j] = cost; from[s][j] = i }
                    }
                }
            }
            return (best, from)
        }

        private func cuts(from table: [[Int]], spreads: Int) -> [Int] {
            var cuts: [Int] = []
            var j = photos.count
            for s in stride(from: spreads, to: 0, by: -1) {
                cuts.append(j)
                j = table[s][j]
            }
            return cuts.reversed()
        }

        /// Mejor reparto con un número fijo de pliegos (programación dinámica). `required` fija
        /// las fotos de algunos pliegos. `nil` si los candados o lo pedido no lo permiten.
        func fixedCuts(spreads: Int, maxPerSpread: Int, required: [Int: Int] = [:]) -> [Int]? {
            let t = table(spreads: spreads, maxPerSpread: maxPerSpread, required: required)
            guard t.best[spreads][photos.count] < .infinity else { return nil }
            return cuts(from: t.from, spreads: spreads)
        }

        /// Mejor reparto dejando que el análisis decida cuántos pliegos. Con fotos pedidas en algunos
        /// pliegos hay que saber en qué pliego va cada trozo: se prueba cada número de pliegos.
        func freeCuts(maxPerSpread: Int, required: [Int: Int] = [:]) -> [Int] {
            let n = photos.count
            if !required.isEmpty {
                let minimum = (required.keys.max() ?? 0) + 1
                let maximum = max(minimum, n)
                let t = table(spreads: maximum, maxPerSpread: maxPerSpread, required: required)
                var bestCount: Int?
                var bestCost = Double.infinity
                for count in minimum...maximum where t.best[count][n] < .infinity {
                    let cost = t.best[count][n] + Double(count) * spreadCost
                    if cost < bestCost { bestCost = cost; bestCount = count }
                }
                if let bestCount { return cuts(from: t.from, spreads: bestCount) }
            }
            var best = Array(repeating: Double.infinity, count: n + 1)
            var from = Array(repeating: -1, count: n + 1)
            best[0] = 0
            for j in 1...n {
                for k in 1...min(maxPerSpread, j) {
                    let i = j - k
                    guard best[i] < .infinity else { continue }
                    let cost = best[i] + segmentCost(start: i, count: k) + cutCost(at: i) + spreadCost
                    if cost < best[j] { best[j] = cost; from[j] = i }
                }
            }
            // Si los candados lo hacen imposible (no debería), una foto por pliego.
            guard best[n] < .infinity else { return Array(1...n) }
            var cuts: [Int] = []
            var j = n
            while j > 0 { cuts.append(j); j = from[j] }
            return cuts.reversed()
        }

        // MARK: Composición de un pliego

        func bestSpread(start: Int, count: Int, side: AlbumPageSide? = nil) -> (spread: AlbumSpread, cost: Double) {
            let key = (start * 1000 + count) * 3 + (side == nil ? 0 : side == .left ? 1 : 2)
            if let cached = spreadCache[key] { return cached }
            let best = ranked(start: start, count: count, limit: 1, anchor: nil, side: side).first ?? (AlbumSpread(), blankPageCost * 2)
            spreadCache[key] = best
            return best
        }

        /// Las mejores composiciones de un pliego, de mejor a peor y sin repetidas. Con `anchor`,
        /// cuesta mover de casilla las fotos fijadas (y se les devuelve su encuadre y su candado).
        func ranked(start: Int, count: Int, limit: Int, anchor: Anchor?, side: AlbumPageSide? = nil) -> [(spread: AlbumSpread, cost: Double)] {
            guard count > 0 else { return [] }
            var options: [(layout: AlbumSpreadLayout, cost: Double)] = []
            let perPage = limit == 1 && anchor == nil ? 1 : 4
            // Pliego de una página: solo esa página, sin cruzar el lomo (la otra va pegada a la tapa).
            if let side {
                for option in pages(start: start, count: count).prefix(max(perPage, limit)) {
                    options.append((side == .left ? .pages(left: option.block, right: nil) : .pages(left: nil, right: option.block), option.cost))
                }
                return finish(options, limit: limit, anchor: anchor)
            }
            // Cada página por su lado: se prueban todos los puntos de corte entre las dos.
            for left in 0...count where left <= maxPerPage && count - left <= maxPerPage {
                let lOptions: [(block: AlbumBlock?, cost: Double)] = left == 0 ? [(nil, blankPageCost)]
                    : pages(start: start, count: left).prefix(perPage).map { ($0.block, $0.cost) }
                let rOptions: [(block: AlbumBlock?, cost: Double)] = count - left == 0 ? [(nil, blankPageCost)]
                    : pages(start: start + left, count: count - left).prefix(perPage).map { ($0.block, $0.cost) }
                for lo in lOptions {
                    for ro in rOptions { options.append((.pages(left: lo.block, right: ro.block), lo.cost + ro.cost)) }
                }
            }
            // El pliego entero, cruzando el lomo con una o varias fotos.
            if count <= maxFullSpread {
                let items = Array(photos[start..<start + count])
                let content = spec.spreadContent
                let pageHeight = spec.pageContent(.left).height
                for block in AlbumAutoLayout.candidates(items, content: content, templates: true) {
                    var cost = whiteSpace(block) + (count > 1 ? fullSpreadBias : 0)
                    for (i, entry) in block.cellRects(in: content).enumerated() {
                        cost += cellCost(items[i].info, rect: entry.rect, pageHeight: pageHeight, spreadWidth: content.width)
                            + spineCost(items[i].info, rect: entry.rect)
                    }
                    options.append((.full(block), cost))
                }
            }
            return finish(options, limit: limit, anchor: anchor)
        }

        /// Ordena las opciones (con el coste de mover las fotos fijadas), quita las repetidas y
        /// devuelve las `limit` mejores.
        private func finish(_ input: [(layout: AlbumSpreadLayout, cost: Double)], limit: Int, anchor: Anchor?) -> [(spread: AlbumSpread, cost: Double)] {
            var options = input
            // Con fotos fijadas: cuanto más se aleje su casilla de donde estaba, peor.
            if let anchor {
                options = options.map { option in
                    var extra = 0.0
                    for entry in option.layout.cellRects(spec) {
                        guard let photo = entry.cell.photo, let old = anchor.cells[photo]?.rect else { continue }
                        let moved = abs(entry.rect.minX - old.minX) + abs(entry.rect.minY - old.minY)
                            + abs(entry.rect.maxX - old.maxX) + abs(entry.rect.maxY - old.maxY)
                        extra += anchorMoveCost * moved / spec.spreadSize.width
                    }
                    return (option.layout, option.cost + extra)
                }
            }
            options.sort { $0.cost < $1.cost }
            var result: [(spread: AlbumSpread, cost: Double)] = []
            var seen: [[CGRect]] = []
            for option in options {
                let shape = option.layout.cellRects(spec).map { $0.rect.integral }
                guard !seen.contains(shape) else { continue }
                seen.append(shape)
                var layout = option.layout
                // Las fotos fijadas recuperan su encuadre y su candado en la casilla nueva.
                if let anchor {
                    for cell in layout.cells {
                        guard let photo = cell.photo, let old = anchor.cells[photo]?.cell else { continue }
                        layout = layout.updatingCell(cell.id) { $0.focus = old.focus; $0.zoom = old.zoom; $0.locked = true }
                    }
                }
                result.append((AlbumSpread(layout: layout), option.cost))
                if result.count >= limit { break }
            }
            return result
        }

        /// Coste del blanco que deja una composición que no llena su zona.
        func whiteSpace(_ block: AlbumBlock) -> Double {
            whiteSpaceCost * (1 - block.area.width * block.area.height)
        }

        /// Lo que cuesta esta casilla del pliego por el lomo: caras en su franja y bordes dentro de ella.
        func spineCost(_ info: AlbumPhotoInfo, rect: CGRect) -> Double {
            let strip = spec.spineStrip
            var cost = 0.0
            if (rect.minX > strip.minX && rect.minX < strip.maxX) || (rect.maxX > strip.minX && rect.maxX < strip.maxX) {
                cost += spineEdgeCost
            }
            guard rect.minX < strip.maxX, rect.maxX > strip.minX else { return cost }
            // Una vertical (o cuadrada) no se dobla por su zona central: lo principal suele estar
            // ahí aunque no sea una cara (una mascota, un objeto…). Las apaisadas sí pueden cruzar
            // a doble página: para ellas mandan las caras, más abajo.
            if !isHorizontal(info.aspect), rect.minX < strip.minX, rect.maxX > strip.maxX {
                let fold = (spec.spineCenter - rect.minX) / rect.width
                if fold > 0.3 && fold < 0.7 { cost += spineFaceCost }
            }
            let visible = visibleRegion(photoAspect: info.aspect, cellAspect: rect.width / rect.height, focus: info.focus ?? CGPoint(x: 0.5, y: 0.5))
            // Lo que no puede caer en el pliegue: las caras. Si la foto aún no se ha analizado (no se
            // sabe dónde están), se supone que lo principal está en el centro, salvo en una
            // panorámica, que está para cruzar el lomo. Analizada y sin caras, puede cruzarlo.
            let protected: [CGRect]
            if let faces = info.faces {
                protected = faces
            } else if info.aspect < panoramaAspect {
                protected = [CGRect(x: 0.32, y: 0.2, width: 0.36, height: 0.45)]
            } else {
                protected = []
            }
            for face in protected {
                // De coordenadas de la foto a mm del pliego.
                let x = rect.minX + (face.minX - visible.minX) / visible.width * rect.width
                let w = face.width / visible.width * rect.width
                if x < strip.maxX && x + w > strip.minX { cost += spineFaceCost }
            }
            return cost
        }

        /// Las mejores composiciones de una página con `count` fotos desde `start`, de mejor a peor.
        func pages(start: Int, count: Int) -> [(block: AlbumBlock, cost: Double)] {
            guard count > 0 else { return [] }
            let key = start * 1000 + count
            if let cached = pageCache[key] { return cached }
            let items = Array(photos[start..<start + count])
            let content = spec.pageContent(.left)
            var all: [(block: AlbumBlock, cost: Double)] = []
            for block in AlbumAutoLayout.candidates(items, content: content, templates: true) {
                var cost = whiteSpace(block)
                for (i, entry) in block.cellRects(in: content).enumerated() {
                    cost += cellCost(items[i].info, rect: entry.rect, pageHeight: content.height, spreadWidth: spec.spreadContent.width)
                }
                all.append((block, cost))
            }
            all.sort { $0.cost < $1.cost }
            let top = Array(all.prefix(24))
            pageCache[key] = top
            return top
        }
    }

    // MARK: - Composiciones candidatas

    /// Todas las formas de partir una zona para estas fotos en orden: en filas (cada fila con
    /// sus fotos una al lado de otra) o en columnas (cada columna con sus fotos apiladas). Las
    /// partes salen de la proporción de cada foto, como en una galería justificada. Cada forma
    /// sale dos veces: estirada hasta llenar la zona (recortando algo las fotos) y a su
    /// proporción natural, centrada con blanco alrededor. Con `templates`, también las
    /// plantillas de collage con ese número de fotos, estiradas a la zona.
    static func candidates(_ items: [Photo], content: CGRect, templates: Bool = false) -> [AlbumBlock] {
        let cells = items.map { AlbumCell(photo: $0.name) }
        var result: [AlbumBlock] = []
        let shapes: [([Int], AlbumSplitAxis)] = items.count == 1 ? [([1], .rows)]
            : compositions(items.count).flatMap { [($0, AlbumSplitAxis.rows), ($0, AlbumSplitAxis.columns)] }
        for (groups, axis) in shapes {
            let node = build(groups, items: items, cells: cells, axis: axis, content: content)
            result.append(AlbumBlock(node: node))
            let fit = naturalArea(groups, items: items, axis: axis, content: content)
            if fit.width < 0.97 || fit.height < 0.97 { result.append(AlbumBlock(node: node, area: fit)) }
        }
        if templates, items.count > 1 {
            for template in AlbumTemplates.templates(photos: items.count) {
                result.append(AlbumBlock(node: template.node(with: items.map(\.name))))
            }
        }
        return result
    }

    /// Parte de la zona que ocupa una forma sin estirar ninguna foto, centrada.
    static func naturalArea(_ groups: [Int], items: [Photo], axis: AlbumSplitAxis, content: CGRect) -> CGRect {
        let gap = AlbumSpec.gapMM
        // En filas, el alto depende del ancho; en columnas, al revés. Se trabaja con «largo»
        // (lo que se reparte entre grupos) y «ancho» (lo que comparten).
        let across = axis == .rows ? content.width : content.height
        let along = axis == .rows ? content.height : content.width
        var sums: [Double] = []
        var index = 0
        for size in groups {
            let group = items[index..<index + size]
            index += size
            sums.append(group.reduce(0.0) { $0 + (axis == .rows ? max($1.info.aspect, 0.01) : 1 / max($1.info.aspect, 0.01)) })
        }
        // Largo natural con todo el ancho: suma de (ancho - huecos del grupo) / suma de proporciones.
        func length(_ width: Double) -> Double {
            zip(groups, sums).reduce(0.0) { $0 + (width - gap * Double($1.0 - 1)) / $1.1 } + gap * Double(groups.count - 1)
        }
        var width = across
        var natural = length(width)
        if natural > along {
            // No cabe: se estrecha hasta que el largo sea justo el de la zona (es lineal).
            let slope = zip(groups, sums).reduce(0.0) { $0 + 1 / $1.1 }
            let fixed = natural - slope * across
            width = max(1, (along - fixed) / slope)
            natural = along
        }
        let w = min(1, width / across), l = min(1, natural / along)
        return axis == .rows
            ? CGRect(x: (1 - w) / 2, y: (1 - l) / 2, width: w, height: l)
            : CGRect(x: (1 - l) / 2, y: (1 - w) / 2, width: l, height: w)
    }

    /// Formas de partir `n` fotos en grupos seguidos: 3 → [3], [1,2], [2,1], [1,1,1].
    static func compositions(_ n: Int) -> [[Int]] {
        guard n > 0 else { return [[]] }
        var result: [[Int]] = []
        for first in 1...n {
            for rest in compositions(n - first) { result.append([first] + rest) }
        }
        return result
    }

    /// Monta el árbol: en `.rows`, cada grupo es una fila (fotos en columnas); en `.columns`, al revés.
    private static func build(_ groups: [Int], items: [Photo], cells: [AlbumCell], axis: AlbumSplitAxis, content: CGRect) -> AlbumNode {
        let gap = AlbumSpec.gapMM
        var children: [AlbumNode] = []
        var fractions: [Double] = []
        var index = 0
        for size in groups {
            let group = items[index..<index + size]
            let groupCells = Array(cells[index..<index + size])
            index += size
            if axis == .rows {
                // Fila justificada: anchos según la proporción; alto natural de la fila.
                let sum = group.reduce(0.0) { $0 + max($1.info.aspect, 0.01) }
                fractions.append((content.width - gap * Double(size - 1)) / sum)
                children.append(size == 1 ? .cell(groupCells[0])
                    : .split(axis: .columns, fractions: group.map { max($0.info.aspect, 0.01) }, children: groupCells.map { .cell($0) }))
            } else {
                // Columna justificada: altos según la proporción; ancho natural de la columna.
                let sum = group.reduce(0.0) { $0 + 1 / max($1.info.aspect, 0.01) }
                fractions.append((content.height - gap * Double(size - 1)) / sum)
                children.append(size == 1 ? .cell(groupCells[0])
                    : .split(axis: .rows, fractions: group.map { 1 / max($0.info.aspect, 0.01) }, children: groupCells.map { .cell($0) }))
            }
        }
        if children.count == 1 { return children[0] }
        return .split(axis: axis, fractions: fractions, children: children)
    }
}
