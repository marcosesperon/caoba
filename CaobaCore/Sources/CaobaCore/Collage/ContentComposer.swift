import Foundation
import CoreGraphics

/// Lo que sabemos de una foto para repartirla en collages: su proporción,
/// dónde está el sujeto (caras u objetos) y cuántas caras hay.
public struct PhotoProfile: Sendable, Equatable {
    /// Ancho / alto de la foto ya orientada.
    public var aspectRatio: Double
    /// Caja del sujeto, normalizada 0-1 con origen arriba-izquierda; `nil` si no se detectó nada.
    public var subject: CGRect?
    public var faceCount: Int

    public init(aspectRatio: Double, subject: CGRect? = nil, faceCount: Int = 0) {
        self.aspectRatio = aspectRatio
        self.subject = subject
        self.faceCount = faceCount
    }

    /// Centro del sujeto, para usarlo como punto de foco del recorte.
    public var focusPoint: CGPoint? { subject.map { CGPoint(x: $0.midX, y: $0.midY) } }

    /// Qué parte del encuadre ocupa el sujeto (0-1).
    var subjectSize: Double { subject.map { min(1, max(0, $0.width * $0.height)) } ?? 0 }

    /// Cuánto "merece" esta foto una celda grande (0-1): las caras pesan mucho,
    /// y un sujeto que llena el encuadre también.
    var importance: Double {
        if faceCount > 0 { return min(1, 0.6 + 0.4 * min(1, subjectSize * 4)) }
        return min(1, subjectSize * 2)
    }
}

/// Un collage ya decidido: plantilla, qué foto va en cada celda (índices sobre
/// el array de perfiles) y el foco de cada celda.
public struct ComposedRow: Sendable, Equatable {
    public var template: CollageTemplate
    public var photoIndices: [Int]
    public var focusPoints: [CGPoint?]
}

/// Reparte fotos en collages mirando su contenido: para cada grupo de fotos
/// consecutivas elige la plantilla permitida que mejor les sienta y qué foto va
/// en cada celda. Opcionalmente puede intercambiar fotos entre collages vecinos.
public enum ContentComposer {

    // MARK: Puntuación

    /// Proporción real de una celda en píxeles: la de la celda sobre el lienzo
    /// multiplicada por la del lienzo.
    static func cellAspect(_ cell: CollageCell, in template: CollageTemplate) -> Double {
        cell.aspectRatio * template.aspectRatio
    }

    /// Qué fracción del sujeto sobrevive al recorte que haría el render para esa
    /// proporción, centrando el recorte en el sujeto (1 si no hay sujeto).
    static func survival(of photo: PhotoProfile, cellAspect: Double) -> Double {
        guard let subject = photo.subject, subject.width > 0, subject.height > 0 else { return 1 }
        let size = PixelSize(width: 1000, height: max(1, Int((1000 / photo.aspectRatio).rounded())))
        let crop = CropGeometry.rect(in: size, ratio: cellAspect, focus: CGPoint(x: subject.midX, y: subject.midY))
        let box = CGRect(x: subject.minX * Double(size.width), y: subject.minY * Double(size.height),
                         width: subject.width * Double(size.width), height: subject.height * Double(size.height))
        let visible = box.intersection(crop)
        guard !visible.isNull, box.width * box.height > 0 else { return 0 }
        return (visible.width * visible.height) / (box.width * box.height)
    }

    /// Puntuación de poner una foto en una celda concreta de una plantilla.
    /// Alrededor de 0-1: cuánto sujeto se conserva y si casa la orientación, con
    /// bonificación por poner lo importante en las celdas grandes y penalización
    /// por meter un grupo de gente en una celda pequeña.
    public static func score(photo: PhotoProfile, cell: CollageCell, in template: CollageTemplate) -> Double {
        let aspect = cellAspect(cell, in: template)
        let orientation = 1 - min(1, abs(log(photo.aspectRatio / aspect)))
        var score = photo.subject == nil ? orientation : 0.7 * survival(of: photo, cellAspect: aspect) + 0.3 * orientation
        let maxArea = template.cells.map { $0.w * $0.h }.max() ?? 1
        let bigness = maxArea > 0 ? (cell.w * cell.h) / maxArea : 1
        score += 0.3 * photo.importance * bigness
        if photo.faceCount >= 3 { score -= 0.4 * (1 - bigness) }
        score -= 0.15 * (1 - photo.importance) * bigness
        return score
    }

    // MARK: Asignación foto-celda

    /// Mejor reparto de un conjunto de fotos entre las celdas de una plantilla.
    /// Exhaustivo hasta 5 fotos; a partir de ahí, voraz empezando por las celdas
    /// grandes. Devuelve, por celda, el índice de foto, y la suma de puntuaciones.
    static func bestAssignment(photos: [Int], profiles: [PhotoProfile], template: CollageTemplate) -> (indices: [Int], total: Double) {
        let cells = template.cells
        precondition(photos.count == cells.count)
        // Tabla celda x foto para no repetir cálculos.
        let table: [[Double]] = cells.map { cell in photos.map { score(photo: profiles[$0], cell: cell, in: template) } }
        let n = photos.count
        if n <= 5 {
            var best: [Int] = Array(0..<n)
            var bestTotal = -Double.infinity
            forEachPermutation(count: n) { perm in
                var total = 0.0
                for cell in 0..<n { total += table[cell][perm[cell]] }
                if total > bestTotal { bestTotal = total; best = perm }
            }
            return (best.map { photos[$0] }, bestTotal)
        }
        var available = Set(0..<n)
        var assignment = Array(repeating: 0, count: n)
        var total = 0.0
        let order = cells.indices.sorted { cells[$0].w * cells[$0].h > cells[$1].w * cells[$1].h }
        for cell in order {
            let pick = available.max { table[cell][$0] < table[cell][$1] }!
            assignment[cell] = pick
            total += table[cell][pick]
            available.remove(pick)
        }
        return (assignment.map { photos[$0] }, total)
    }

    /// Recorre todas las permutaciones de 0..<count (algoritmo de Heap).
    static func forEachPermutation(count: Int, _ body: ([Int]) -> Void) {
        var a = Array(0..<count)
        var c = Array(repeating: 0, count: count)
        body(a)
        var i = 0
        while i < count {
            if c[i] < i {
                if i % 2 == 0 { a.swapAt(0, i) } else { a.swapAt(c[i], i) }
                body(a)
                c[i] += 1
                i = 0
            } else {
                c[i] = 0
                i += 1
            }
        }
    }

    // MARK: Reparto

    /// Penalización por cada foto que se queda sin collage al final.
    static let leftoverPenalty = 1.0
    /// Por foto del grupo si repite la plantilla del grupo anterior.
    static let repeatPenalty = 0.3
    /// Por foto del grupo si repite solo el número de fotos del grupo anterior.
    static let sameSizePenalty = 0.08
    /// Una plantilla de una foto solo compensa si la foto destaca.
    static let singlePenalty = 0.25
    static let standoutImportance = 0.85
    /// Grupos hacia atrás en los que una plantilla cuenta como «reciente».
    static let varietyWindow = 3
    /// Pérdida máxima por foto que se acepta al cambiar una plantilla repetida por otra.
    static let varietyTolerance = 0.12

    /// Puntuación de un grupo con una plantilla, con la penalización de single ya aplicada.
    static func groupScore(photos: [Int], profiles: [PhotoProfile], template: CollageTemplate) -> (indices: [Int], total: Double) {
        var (indices, total) = bestAssignment(photos: photos, profiles: profiles, template: template)
        if template.photos == 1, profiles[photos[0]].importance < standoutImportance { total -= singlePenalty }
        return (indices, total)
    }

    /// Reparte las fotos (en el orden dado) entre las plantillas permitidas.
    /// Programación dinámica sobre la posición y la plantilla del grupo anterior:
    /// en cada punto se prueba cada plantilla con las siguientes N fotos y se
    /// maximiza la suma de puntuaciones, penalizando repetir plantilla (o tamaño)
    /// respecto al grupo anterior. Así el tamaño de cada grupo también lo decide
    /// el contenido. Las fotos que no quepan se quedan fuera al final (`leftover`).
    public static func compose(profiles: [PhotoProfile], templates: [CollageTemplate], allowReorder: Bool) -> (rows: [ComposedRow], leftover: [Int]) {
        let n = profiles.count
        guard n > 0, !templates.isEmpty else { return ([], Array(0..<n)) }
        let t = templates.count

        // Puntuación de cada (posición, plantilla), calculada una sola vez.
        var memo: [[(indices: [Int], total: Double)?]] = Array(repeating: Array(repeating: nil, count: t), count: n)
        func scoreAt(_ i: Int, _ ti: Int) -> (indices: [Int], total: Double) {
            if let cached = memo[i][ti] { return cached }
            let result = groupScore(photos: Array(i..<(i + templates[ti].photos)), profiles: profiles, template: templates[ti])
            memo[i][ti] = result
            return result
        }

        // dp[i][last]: mejor total desde la foto i si el grupo anterior usó la plantilla `last`
        // (índice t = ningún grupo anterior).
        struct Choice { var total: Double; var template: Int? }
        var dp = Array(repeating: Array(repeating: Choice(total: 0, template: nil), count: t + 1), count: n + 1)
        for i in stride(from: n - 1, through: 0, by: -1) {
            for last in 0...t {
                var best = Choice(total: -leftoverPenalty * Double(n - i), template: nil)
                for ti in 0..<t where templates[ti].photos <= n - i {
                    let template = templates[ti]
                    var total = scoreAt(i, ti).total + dp[i + template.photos][ti].total
                    if last < t {
                        if last == ti { total -= repeatPenalty * Double(template.photos) }
                        else if templates[last].photos == template.photos { total -= sameSizePenalty * Double(template.photos) }
                    }
                    if total > best.total { best = Choice(total: total, template: ti) }
                }
                dp[i][last] = best
            }
        }

        var groups: [(template: CollageTemplate, photos: [Int])] = []
        var i = 0
        var last = t
        while i < n, let ti = dp[i][last].template {
            groups.append((templates[ti], scoreAt(i, ti).indices))
            i += templates[ti].photos
            last = ti
        }
        let leftover = Array(i..<n)

        if allowReorder { improveBySwapping(&groups, profiles: profiles, templates: templates) }
        diversify(&groups, profiles: profiles, templates: templates)

        let rows = groups.map { group in
            ComposedRow(template: group.template, photoIndices: group.photos,
                        focusPoints: group.photos.map { profiles[$0].focusPoint })
        }
        return (rows, leftover)
    }

    /// Pasada de variedad: si una plantilla ya salió en los últimos grupos, se
    /// prueba otra del mismo número de fotos que no haya salido hace poco (ni
    /// venga justo después) y se cambia si pierde poca puntuación.
    static func diversify(_ groups: inout [(template: CollageTemplate, photos: [Int])], profiles: [PhotoProfile], templates: [CollageTemplate]) {
        for g in groups.indices {
            let before = groups[max(0, g - varietyWindow)..<g].map(\.template.id)
            guard before.contains(groups[g].template.id) else { continue }
            let after = groups[(g + 1)..<min(groups.count, g + 1 + varietyWindow)].map(\.template.id)
            let recent = Set(before + after)
            let current = groupScore(photos: groups[g].photos, profiles: profiles, template: groups[g].template)
            var best: (template: CollageTemplate, indices: [Int], total: Double)?
            for template in templates where template.photos == groups[g].photos.count && !recent.contains(template.id) {
                let candidate = groupScore(photos: groups[g].photos, profiles: profiles, template: template)
                if best == nil || candidate.total > best!.total { best = (template, candidate.indices, candidate.total) }
            }
            if let best, best.total >= current.total - varietyTolerance * Double(groups[g].photos.count) {
                groups[g] = (best.template, best.indices)
            }
        }
    }

    /// Con reordenación permitida: prueba a intercambiar fotos entre collages
    /// vecinos (el siguiente y el que va después) mientras suba la puntuación, y
    /// al final deja que cada grupo vuelva a elegir plantilla de su tamaño.
    static func improveBySwapping(_ groups: inout [(template: CollageTemplate, photos: [Int])], profiles: [PhotoProfile], templates: [CollageTemplate]) {
        func total(_ g: (template: CollageTemplate, photos: [Int])) -> Double {
            groupScore(photos: g.photos, profiles: profiles, template: g.template).total
        }
        var pass = 0
        var improved = true
        while improved, pass < 6 {
            improved = false
            pass += 1
            for a in groups.indices {
                for b in (a + 1)..<min(a + 3, groups.count) where b < groups.count {
                    let before = total(groups[a]) + total(groups[b])
                    var bestGain = 1e-6
                    var bestSwap: (Int, Int)?
                    for pa in groups[a].photos.indices {
                        for pb in groups[b].photos.indices {
                            var ga = groups[a], gb = groups[b]
                            swap(&ga.photos[pa], &gb.photos[pb])
                            let gain = total(ga) + total(gb) - before
                            if gain > bestGain { bestGain = gain; bestSwap = (pa, pb) }
                        }
                    }
                    if let (pa, pb) = bestSwap {
                        let moved = groups[a].photos[pa]
                        groups[a].photos[pa] = groups[b].photos[pb]
                        groups[b].photos[pb] = moved
                        improved = true
                    }
                }
            }
        }
        // Cada grupo se queda con la plantilla de su tamaño que mejor le sienta,
        // y con las fotos ya en el orden de sus celdas.
        for g in groups.indices {
            let candidates = templates.filter { $0.photos == groups[g].photos.count }
            var best = (template: groups[g].template, indices: groups[g].photos, total: -Double.infinity)
            for template in candidates {
                let (indices, sum) = groupScore(photos: groups[g].photos, profiles: profiles, template: template)
                if sum > best.total { best = (template, indices, sum) }
            }
            groups[g] = (best.template, best.indices)
        }
    }
}
