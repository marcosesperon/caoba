import Testing
import Foundation
import CoreGraphics
@testable import CaobaCore

@Suite("ContentComposer")
struct ContentComposerTests {
    // Perfiles sintéticos: sin Vision, solo geometría.
    let portraitFace = PhotoProfile(aspectRatio: 2.0 / 3.0, subject: CGRect(x: 0.35, y: 0.15, width: 0.3, height: 0.25), faceCount: 1)
    let landscapePlain = PhotoProfile(aspectRatio: 3.0 / 2.0)
    let groupPhoto = PhotoProfile(aspectRatio: 3.0 / 2.0, subject: CGRect(x: 0.1, y: 0.2, width: 0.8, height: 0.4), faceCount: 5)
    let wideSubject = PhotoProfile(aspectRatio: 3.0 / 2.0, subject: CGRect(x: 0.05, y: 0.3, width: 0.9, height: 0.3))

    /// Plantilla 16:9 con una celda vertical grande a la izquierda y dos apaisadas pequeñas a la derecha.
    let mixed = CollageTemplate(id: "t_mixed", name: "mixed", photos: 3, aspect: [16, 9], cells: [
        CollageCell(x: 0, y: 0, w: 0.4, h: 1),
        CollageCell(x: 0.4, y: 0, w: 0.6, h: 0.5),
        CollageCell(x: 0.4, y: 0.5, w: 0.6, h: 0.5),
    ])
    let single = CollageTemplate(id: "t_single", name: "single", photos: 1, aspect: [3, 2], cells: [CollageCell(x: 0, y: 0, w: 1, h: 1)])
    let pair = CollageTemplate(id: "t_pair", name: "pair", photos: 2, aspect: [3, 2], cells: [
        CollageCell(x: 0, y: 0, w: 0.5, h: 1), CollageCell(x: 0.5, y: 0, w: 0.5, h: 1),
    ])

    @Test("Una vertical con cara va a la celda vertical grande y las apaisadas a las pequeñas")
    func portraitGoesToTallCell() {
        let profiles = [landscapePlain, portraitFace, landscapePlain]
        let (rows, leftover) = ContentComposer.compose(profiles: profiles, templates: [mixed], allowReorder: false)
        #expect(leftover.isEmpty)
        #expect(rows.count == 1)
        #expect(rows[0].photoIndices[0] == 1)
        #expect(rows[0].focusPoints[0] != nil)
        #expect(Set(rows[0].photoIndices) == Set([0, 1, 2]))
    }

    @Test("Un sujeto apaisado conserva más en una celda apaisada que en una vertical")
    func survivalPrefersMatchingCell() {
        let tall = ContentComposer.score(photo: wideSubject, cell: mixed.cells[0], in: mixed)
        let wide = ContentComposer.score(photo: wideSubject, cell: mixed.cells[1], in: mixed)
        #expect(wide > tall)
        #expect(ContentComposer.survival(of: wideSubject, cellAspect: 1.5) > 0.99)
        #expect(ContentComposer.survival(of: wideSubject, cellAspect: 0.5) < 0.5)
    }

    /// Plantilla 3:2 con una celda apaisada grande arriba y dos pequeñas abajo.
    let stack = CollageTemplate(id: "t_stack", name: "stack", photos: 3, aspect: [3, 2], cells: [
        CollageCell(x: 0, y: 0, w: 1, h: 0.7),
        CollageCell(x: 0, y: 0.7, w: 0.5, h: 0.3),
        CollageCell(x: 0.5, y: 0.7, w: 0.5, h: 0.3),
    ])

    @Test("Un grupo de gente se lleva la celda grande frente a fotos sin sujeto")
    func groupTakesBigCell() {
        let profiles = [landscapePlain, landscapePlain, groupPhoto]
        let (rows, _) = ContentComposer.compose(profiles: profiles, templates: [stack], allowReorder: false)
        #expect(rows[0].photoIndices[0] == 2)
        // Y la diferencia grande/pequeña pesa más en el grupo que en una foto sin sujeto.
        let groupGap = ContentComposer.score(photo: groupPhoto, cell: stack.cells[0], in: stack) - ContentComposer.score(photo: groupPhoto, cell: stack.cells[1], in: stack)
        let plainGap = ContentComposer.score(photo: landscapePlain, cell: stack.cells[0], in: stack) - ContentComposer.score(photo: landscapePlain, cell: stack.cells[1], in: stack)
        #expect(groupGap > plainGap)
    }

    @Test("Sin reordenar se respeta el orden y no se pierden fotos; el tamaño de grupo lo decide el reparto")
    func keepsOrder() {
        let profiles = [portraitFace, landscapePlain, landscapePlain, groupPhoto, landscapePlain]
        let (rows, leftover) = ContentComposer.compose(profiles: profiles, templates: [single, pair, mixed], allowReorder: false)
        #expect(leftover.isEmpty)
        let order = rows.flatMap(\.photoIndices)
        #expect(Set(order) == Set(0..<5))
        // Cada grupo contiene fotos consecutivas.
        var next = 0
        for row in rows {
            #expect(Set(row.photoIndices) == Set(next..<(next + row.template.photos)))
            next += row.template.photos
        }
    }

    @Test("Si nada encaja, las fotos sobrantes quedan al final")
    func leftoverAtEnd() {
        let profiles = [landscapePlain, landscapePlain, landscapePlain, landscapePlain]
        let (rows, leftover) = ContentComposer.compose(profiles: profiles, templates: [mixed], allowReorder: false)
        #expect(rows.count == 1)
        #expect(leftover == [3])
    }

    @Test("Reordenar no pierde fotos y no empeora la puntuación")
    func reorderImproves() {
        let profiles = [landscapePlain, landscapePlain, portraitFace, portraitFace, landscapePlain, landscapePlain]
        let fixed = ContentComposer.compose(profiles: profiles, templates: [mixed], allowReorder: false)
        let free = ContentComposer.compose(profiles: profiles, templates: [mixed], allowReorder: true)
        #expect(Set(free.rows.flatMap(\.photoIndices)) == Set(0..<6))
        func total(_ rows: [ComposedRow]) -> Double {
            rows.reduce(0) { sum, row in
                sum + zip(row.photoIndices, row.template.cells).reduce(0) { $0 + ContentComposer.score(photo: profiles[$1.0], cell: $1.1, in: row.template) }
            }
        }
        #expect(total(free.rows) >= total(fixed.rows) - 1e-9)
        // Con libertad, cada collage puede llevar una vertical con cara en su celda grande.
        #expect(free.rows.allSatisfy { profiles[$0.photoIndices[0]].faceCount == 1 })
    }

    @Test("Las permutaciones de 4 son 24 y las de 1 es 1")
    func permutations() {
        var count = 0
        ContentComposer.forEachPermutation(count: 4) { _ in count += 1 }
        #expect(count == 24)
        var one = 0
        ContentComposer.forEachPermutation(count: 1) { _ in one += 1 }
        #expect(one == 1)
    }

    @Test("Con fotos parecidas no se repite la misma plantilla más de dos veces seguidas ni abundan los singles")
    func variety() {
        // 24 fotos apaisadas con pareja (como un reportaje de dos personas).
        let couple = PhotoProfile(aspectRatio: 1.5, subject: CGRect(x: 0.3, y: 0.2, width: 0.4, height: 0.3), faceCount: 2)
        let profiles = Array(repeating: couple, count: 24)
        let singleWide = CollageTemplate(id: "s16", name: "single", photos: 1, aspect: [16, 9], cells: [CollageCell(x: 0, y: 0, w: 1, h: 1)])
        let split = CollageTemplate(id: "split", name: "60/40", photos: 2, aspect: [16, 9], cells: [
            CollageCell(x: 0, y: 0, w: 0.6, h: 1), CollageCell(x: 0.6, y: 0, w: 0.4, h: 1),
        ])
        let halves = CollageTemplate(id: "halves", name: "halves", photos: 2, aspect: [16, 9], cells: [
            CollageCell(x: 0, y: 0, w: 0.5, h: 1), CollageCell(x: 0.5, y: 0, w: 0.5, h: 1),
        ])
        let rowsOf3 = CollageTemplate(id: "row3", name: "row3", photos: 3, aspect: [16, 9], cells: [
            CollageCell(x: 0, y: 0, w: 1 / 3, h: 1), CollageCell(x: 1 / 3, y: 0, w: 1 / 3, h: 1), CollageCell(x: 2 / 3, y: 0, w: 1 / 3, h: 1),
        ])
        let (rows, leftover) = ContentComposer.compose(profiles: profiles, templates: [singleWide, split, halves, rowsOf3, mixed, stack], allowReorder: false)
        #expect(leftover.isEmpty)
        let ids = rows.map(\.template.id)
        var longestRun = 1, run = 1
        for i in 1..<ids.count { run = ids[i] == ids[i - 1] ? run + 1 : 1; longestRun = max(longestRun, run) }
        #expect(longestRun <= 2)
        #expect(Set(ids).count >= 3)
        let singles = rows.filter { $0.template.photos == 1 }.count
        #expect(singles * 3 <= rows.count)
    }

    @Test("Un single sí se elige para una foto que destaca")
    func singleForStandout() {
        let singleWide = CollageTemplate(id: "s32", name: "single", photos: 1, aspect: [3, 2], cells: [CollageCell(x: 0, y: 0, w: 1, h: 1)])
        let (rows, _) = ContentComposer.compose(profiles: [groupPhoto, landscapePlain, landscapePlain], templates: [singleWide, pair], allowReorder: false)
        #expect(rows.first?.template.id == "s32")
        #expect(rows.first?.photoIndices == [0])
    }
}

