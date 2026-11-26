import XCTest
import CoreGraphics
@testable import CaobaCore

final class AlbumTests: XCTestCase {
    private let spec = AlbumSpec(pageWidthMM: 300, pageHeightMM: 300, bleedMM: 3, safetyMM: 10, spineMM: 10)
    private let start = Date(timeIntervalSince1970: 1_800_000_000)

    /// Foto de prueba: proporción, segundos desde el principio y caras (alto de cada una, 0-1).
    private func photo(_ name: String, _ aspect: Double, at seconds: Double, faces: [Double] = [], faceX: Double = 0.5) -> AlbumAutoLayout.Photo {
        let boxes = faces.enumerated().map { i, h in
            CGRect(x: min(0.95 - h, faceX - h / 2 + Double(i) * 0.001), y: 0.3, width: h * 0.8, height: h)
        }
        let focus = boxes.isEmpty ? CGPoint(x: 0.5, y: 0.5) : CGPoint(x: faceX, y: 0.3 + (faces.max() ?? 0) / 2)
        return .init(name: name, info: AlbumPhotoInfo(aspect: aspect, captureDate: start.addingTimeInterval(seconds), faces: boxes, focus: focus))
    }

    // MARK: - Medidas

    func testExportPixelSizeIncludesBleed() {
        // (600 + 2·3) mm y (300 + 2·3) mm a 300 ppp.
        XCTAssertEqual(spec.exportPixelSize, PixelSize(width: 7157, height: 3614))
        var hi = spec
        hi.ppi = 600
        XCTAssertEqual(hi.exportPixelSize.width, 14315)
    }

    func testContentAreasRespectSafetyAndSpine() {
        XCTAssertEqual(spec.pageContent(.left), CGRect(x: 10, y: 10, width: 280, height: 280))
        XCTAssertEqual(spec.pageContent(.right), CGRect(x: 310, y: 10, width: 280, height: 280))
        XCTAssertEqual(spec.spreadContent, CGRect(x: 10, y: 10, width: 580, height: 280))
        XCTAssertEqual(spec.spineStrip, CGRect(x: 290, y: 0, width: 20, height: 300))
        XCTAssertTrue(spec.isValid)
        XCTAssertFalse(AlbumSpec(pageWidthMM: 30, pageHeightMM: 300).isValid)
    }

    // MARK: - Árbol de cortes

    func testCellRectsSplitWithGap() {
        let a = AlbumCell(photo: "a.jpg"), b = AlbumCell(photo: "b.jpg"), c = AlbumCell(photo: "c.jpg")
        let node = AlbumNode.split(axis: .columns, fractions: [2, 1], children: [
            .cell(a),
            .split(axis: .rows, fractions: [1, 1], children: [.cell(b), .cell(c)]),
        ])
        let rects = node.cellRects(in: CGRect(x: 0, y: 0, width: 304, height: 104), gap: 4)
        XCTAssertEqual(rects.map(\.cell.photo), ["a.jpg", "b.jpg", "c.jpg"])
        XCTAssertEqual(rects[0].rect, CGRect(x: 0, y: 0, width: 200, height: 104))
        XCTAssertEqual(rects[1].rect, CGRect(x: 204, y: 0, width: 100, height: 50))
        XCTAssertEqual(rects[2].rect, CGRect(x: 204, y: 54, width: 100, height: 50))
    }

    func testCompositionsKeepOrder() {
        XCTAssertEqual(AlbumAutoLayout.compositions(3), [[1, 1, 1], [1, 2], [2, 1], [3]])
        XCTAssertEqual(AlbumAutoLayout.compositions(5).count, 16)
    }

    func testVisibleRegionStaysInsidePhoto() {
        let r = AlbumAutoLayout.visibleRegion(photoAspect: 1.5, cellAspect: 1, focus: CGPoint(x: 0.95, y: 0.5))
        XCTAssertEqual(r.width, 1 / 1.5, accuracy: 0.0001)
        XCTAssertEqual(r.maxX, 1, accuracy: 0.0001)
        XCTAssertEqual(r.height, 1)
    }

    // MARK: - Reparto automático

    func testKeepsEveryPhotoInOrder() {
        let photos = (0..<23).map { photo("p\($0).jpg", $0 % 3 == 0 ? 2 / 3 : 1.5, at: Double($0) * 40) }
        let spreads = AlbumAutoLayout.distribute(photos, spec: spec)
        XCTAssertEqual(spreads.flatMap(\.photos), photos.map(\.name))
        XCTAssertTrue(spreads.allSatisfy { !$0.photos.isEmpty })
    }

    func testCountDependsOnPhotosNotOnAFixedNumber() {
        // Mismas 12 fotos: retratos de cerca aguantan casillas pequeñas; grupos grandes no.
        let close = (0..<12).map { photo("c\($0).jpg", 2 / 3, at: Double($0) * 300, faces: [0.25]) }
        let groups = (0..<12).map { photo("g\($0).jpg", 1.5, at: Double($0) * 300, faces: Array(repeating: 0.035, count: 12)) }
        let closeSpreads = AlbumAutoLayout.distribute(close, spec: spec).count
        let groupSpreads = AlbumAutoLayout.distribute(groups, spec: spec).count
        XCTAssertGreaterThan(groupSpreads, closeSpreads)
    }

    func testPanoramaGetsTheWholeSpread() {
        let photos = [photo("a.jpg", 1.5, at: 0), photo("b.jpg", 1.5, at: 30),
                      photo("pano.jpg", 3.2, at: 600),
                      photo("c.jpg", 1.5, at: 1200), photo("d.jpg", 2 / 3, at: 1230)]
        let spreads = AlbumAutoLayout.distribute(photos, spec: spec)
        // La panorámica cruza el lomo a todo lo ancho (sola o con otras fotos encima o debajo).
        let pano = spreads.first { $0.photos.contains("pano.jpg") }
        if case .full = pano?.layout {} else { XCTFail("La panorámica debería cruzar el lomo") }
        let rect = pano?.layout.cellRects(spec).first { $0.cell.photo == "pano.jpg" }?.rect
        XCTAssertGreaterThan(rect?.width ?? 0, spec.spreadContent.width * 0.85)
    }

    func testBigGroupGetsRoomOfItsOwn() {
        var photos = (0..<4).map { photo("p\($0).jpg", 2 / 3, at: Double($0) * 20, faces: [0.2]) }
        photos.append(photo("grupo.jpg", 1.5, at: 2000, faces: Array(repeating: 0.03, count: 14), faceX: 0.25))
        photos += (5..<9).map { photo("p\($0).jpg", 2 / 3, at: 4000 + Double($0) * 20, faces: [0.2]) }
        let spreads = AlbumAutoLayout.distribute(photos, spec: spec)
        let group = spreads.first { $0.photos.contains("grupo.jpg") }
        XCTAssertEqual(group?.photos, ["grupo.jpg"])
    }

    func testFaceOnTheSpineAvoidsFullSpread() {
        // Una apaisada con la cara justo en el centro no cruza el lomo.
        let spread = AlbumAutoLayout.bestSpread([photo("a.jpg", 1.9, at: 0, faces: [0.2], faceX: 0.5)], spec: spec).spread
        if case .full = spread.layout { XCTFail("La cara caería en el lomo") }
        // Con las caras a un lado, sí.
        let side = AlbumAutoLayout.bestSpread([photo("b.jpg", 1.9, at: 0, faces: [0.2], faceX: 0.2)], spec: spec).spread
        if case .full = side.layout {} else { XCTFail("Debería ir a pliego completo") }
    }

    func testFixedSpreadCountIsExact() {
        let photos = (0..<20).map { photo("p\($0).jpg", 1.5, at: Double($0) * 60) }
        let spreads = AlbumAutoLayout.distribute(photos, spec: spec, spreadCount: 7)
        XCTAssertEqual(spreads.count, 7)
        XCTAssertEqual(spreads.flatMap(\.photos), photos.map(\.name))
    }

    func testCutsAtSceneChanges() {
        // Dos ráfagas de 4 separadas una hora: con 2 pliegos, el corte va entre ellas.
        let photos = (0..<4).map { photo("a\($0).jpg", 1.5, at: Double($0) * 5) }
            + (0..<4).map { photo("b\($0).jpg", 1.5, at: 3600 + Double($0) * 5) }
        let spreads = AlbumAutoLayout.distribute(photos, spec: spec, spreadCount: 2)
        XCTAssertEqual(spreads.map(\.photos.count), [4, 4])
        XCTAssertEqual(spreads[0].reason, .sameMoment(seconds: 15))
    }

    func testPortraitsGoInPortraitCells() {
        let photos = [photo("v1.jpg", 2 / 3, at: 0), photo("v2.jpg", 2 / 3, at: 10)]
        let spread = AlbumAutoLayout.bestSpread(photos, spec: spec).spread
        for entry in spread.layout.cellRects(spec) {
            XCTAssertLessThan(entry.rect.width / entry.rect.height, 1, "Una vertical en casilla apaisada")
        }
    }

    func testRedistributeRespectsManualCountAndKeepsEarlierSpreads() {
        let names = (0..<12).map { "p\($0).jpg" }
        var doc = AlbumDocument(typeName: "Prueba", spec: spec, photos: names)
        for (i, name) in names.enumerated() { doc.info[name] = AlbumPhotoInfo(aspect: 1.5, captureDate: start.addingTimeInterval(Double(i) * 60), faces: []) }
        doc.spreads = AlbumAutoLayout.redistribute(doc)
        let first = doc.spreads[0]
        // El segundo pliego pasa a llevar 5 fotos; el primero no se toca.
        doc.spreads[1].manualCount = 5
        let after = AlbumAutoLayout.redistribute(doc, from: 1)
        XCTAssertEqual(after[0], first)
        XCTAssertEqual(after[1].photos.count, 5)
        XCTAssertEqual(after[1].reason, .manualCount)
        XCTAssertEqual(after.flatMap(\.photos), names)
    }

    func testFixedCountWithFewPhotosLeavesBlankSpreads() {
        var s = spec
        s.spreads = 5
        var doc = AlbumDocument(typeName: "Prueba", spec: s, photos: ["a.jpg", "b.jpg"])
        doc.info = ["a.jpg": AlbumPhotoInfo(aspect: 1.5, captureDate: start, faces: []),
                    "b.jpg": AlbumPhotoInfo(aspect: 1.5, captureDate: start, faces: [])]
        let spreads = AlbumAutoLayout.redistribute(doc)
        XCTAssertEqual(spreads.count, 5)
        XCTAssertEqual(spreads.flatMap(\.photos), ["a.jpg", "b.jpg"])
    }

    // MARK: - Guardado

    func testDocumentRoundTrip() throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("caoba-album-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: folder) }
        let library = AlbumLibrary(folder: folder)
        let photos = (0..<6).map { photo("p\($0).jpg", 1.5, at: Double($0) * 60, faces: [0.1]) }
        var doc = AlbumDocument(typeName: "30x30", spec: spec, photos: photos.map(\.name))
        for p in photos { doc.info[p.name] = p.info }
        doc.spreads = AlbumAutoLayout.redistribute(doc)
        try doc.save(to: library.file(of: "Boda"))
        XCTAssertEqual(try AlbumDocument.load(from: library.file(of: "Boda")), doc)
        XCTAssertEqual(library.albumNames(), ["Boda"])
        XCTAssertEqual(library.uniqueName("boda"), "boda 2")
        try library.rename("Boda", to: "Boda novios")
        XCTAssertEqual(library.albumNames(), ["Boda novios"])
        XCTAssertNoThrow(try AlbumDocument.load(from: library.file(of: "Boda novios")))
        // Solo mayúsculas: también en discos que no las distinguen.
        try library.rename("Boda novios", to: "Boda Novios")
        XCTAssertEqual(library.albumNames(), ["Boda Novios"])
        XCTAssertNoThrow(try AlbumDocument.load(from: library.file(of: "Boda Novios")))
    }

    func testOldSpecDecodesWithDefaults() throws {
        let spec = try JSONDecoder().decode(AlbumSpec.self, from: Data(#"{"pageWidthMM": 250}"#.utf8))
        XCTAssertEqual(spec.pageWidthMM, 250)
        XCTAssertEqual(spec.ppi, 300)
        XCTAssertNil(spec.spreads)
    }

    // MARK: - Fase 2: plantillas

    func testCollageTemplatesBecomeGuillotineTrees() {
        XCTAssertEqual(AlbumTemplates.all.count, 666)
        for entry in AlbumTemplates.all {
            XCTAssertEqual(entry.node.cells.count, entry.photos, entry.id)
        }
        let three = AlbumTemplates.templates(photos: 3)
        XCTAssertFalse(three.isEmpty)
        let node = three[0].node(with: ["a.jpg", "b.jpg", "c.jpg"])
        XCTAssertEqual(node.cells.compactMap(\.photo), ["a.jpg", "b.jpg", "c.jpg"])
    }

    // MARK: - Fase 2: guías

    private func twoColumnsPage() -> AlbumSpreadLayout {
        let node = AlbumNode.split(axis: .columns, fractions: [1, 1], children: [.cell(AlbumCell(photo: "a.jpg")), .cell(AlbumCell(photo: "b.jpg"))])
        return .pages(left: AlbumBlock(node: node), right: AlbumBlock(node: .cell(AlbumCell(photo: "c.jpg"))))
    }

    func testMovingAGuideResizesOnlyItsNeighbours() throws {
        let layout = twoColumnsPage()
        let guide = try XCTUnwrap(layout.guides(spec).first { if case .split(.left, [], 0) = $0.kind { return true }; return false })
        XCTAssertEqual(guide.position, 150, accuracy: 0.001)
        // Entre 10 + 15 + 2 y 290 - 15 - 2.
        XCTAssertEqual(guide.range.lowerBound, 27, accuracy: 0.001)
        XCTAssertEqual(guide.range.upperBound, 273, accuracy: 0.001)
        let move = layout.moving(guide, to: 100, spec: spec)
        let rects = move.layout.cellRects(spec)
        XCTAssertEqual(rects[0].rect.width, 88, accuracy: 0.001)
        XCTAssertEqual(rects[1].rect.minX, 102, accuracy: 0.001)
        XCTAssertEqual(rects[1].rect.maxX, 290, accuracy: 0.001)
        XCTAssertEqual(move.before, 88, accuracy: 0.001)
        XCTAssertEqual(move.after, 188, accuracy: 0.001)
        // Nunca por debajo del mínimo.
        let squeezed = layout.moving(guide, to: 0, spec: spec)
        XCTAssertEqual(squeezed.layout.cellRects(spec)[0].rect.width, AlbumSpreadLayout.minCellMM, accuracy: 0.001)
    }

    func testDraggingTheSpineJoinsBothPages() throws {
        let layout = twoColumnsPage()
        let spine = try XCTUnwrap(layout.guides(spec).first { $0.kind == .spine })
        let move = layout.moving(spine, to: 400, spec: spec)
        guard case .full = move.layout else { return XCTFail("Debería ser una sola composición") }
        let rects = move.layout.cellRects(spec)
        XCTAssertEqual(rects.map(\.cell.photo), ["a.jpg", "b.jpg", "c.jpg"])
        // La segunda foto ya cruza el lomo.
        XCTAssertGreaterThan(rects[1].rect.maxX, 300)
        XCTAssertEqual(rects[2].rect.minX, 402, accuracy: 0.001)
    }

    func testGuidesSnapToTheSpineAndPageCentres() throws {
        let layout = twoColumnsPage()
        let guide = try XCTUnwrap(layout.guides(spec).first { if case .split = $0.kind { return true }; return false })
        XCTAssertEqual(layout.snapped(148.5, for: guide, spec: spec).position, 150)
        XCTAssertTrue(layout.snapped(148.5, for: guide, spec: spec).snapped)
        XCTAssertFalse(layout.snapped(120, for: guide, spec: spec).snapped)
    }

    func testEqualizeAndFitToPhotos() throws {
        let a = AlbumCell(photo: "a.jpg"), b = AlbumCell(photo: "b.jpg")
        let layout = AlbumSpreadLayout.pages(left: AlbumBlock(node: .split(axis: .columns, fractions: [3, 1], children: [.cell(a), .cell(b)])), right: nil)
        let equal = layout.equalizing(around: b.id, spec: spec).cellRects(spec)
        XCTAssertEqual(equal[0].rect.width, equal[1].rect.width, accuracy: 0.001)
        // Una vertical y una apaisada: el ancho va como la proporción.
        let fitted = layout.fittedToPhotos({ $0 == "a.jpg" ? 2.0 / 3 : 1.5 }, spec: spec).cellRects(spec)
        XCTAssertEqual(fitted[0].rect.width / fitted[1].rect.width, (2.0 / 3) / 1.5, accuracy: 0.01)
    }

    func testZoomShrinksTheVisibleRegion() {
        let r = AlbumAutoLayout.visibleRegion(photoAspect: 1, cellAspect: 1, focus: CGPoint(x: 0.5, y: 0.5), zoom: 2)
        XCTAssertEqual(r, CGRect(x: 0.25, y: 0.25, width: 0.5, height: 0.5))
    }

    // MARK: - Fase 2: candados y alternativas

    private func document(_ count: Int, gap: Double = 60) -> AlbumDocument {
        let names = (0..<count).map { "p\($0).jpg" }
        var doc = AlbumDocument(typeName: "Prueba", spec: spec, photos: names)
        for (i, name) in names.enumerated() {
            doc.info[name] = AlbumPhotoInfo(aspect: i % 3 == 0 ? 2.0 / 3 : 1.5, captureDate: start.addingTimeInterval(Double(i) * gap), faces: [])
        }
        doc.spreads = AlbumAutoLayout.redistribute(doc)
        return doc
    }

    func testLockedSpreadSurvivesTheCascade() {
        var doc = document(20)
        XCTAssertGreaterThan(doc.spreads.count, 3)
        doc.spreads[2].locked = true
        let locked = doc.spreads[2]
        // Se cambia el número de fotos del primero: todo corre, salvo el pliego con candado.
        doc.spreads[0].manualCount = 1
        let after = AlbumAutoLayout.redistribute(doc, from: 0)
        XCTAssertTrue(after.contains(locked))
        XCTAssertEqual(after.flatMap(\.photos).sorted(), doc.photos.sorted())
        XCTAssertEqual(after[0].photos.count, 1)
    }

    func testLockedPhotoKeepsItsCellWhenItsSpreadIsRebuilt() throws {
        var doc = document(20)
        let spread = doc.spreads[2]
        let target = try XCTUnwrap(spread.layout.cells.last)
        let oldRect = try XCTUnwrap(spread.layout.cellRects(spec).first { $0.cell.id == target.id }?.rect)
        doc.spreads[2].layout = spread.layout.updatingCell(target.id) { $0.locked = true; $0.zoom = 1.5 }
        // Un pliego antes cambia de número: las fotos corren, pero la fijada sigue en su pliego y casilla.
        doc.spreads[1].manualCount = doc.spreads[1].photos.count + 1
        let after = AlbumAutoLayout.redistribute(doc, from: 1)
        let holder = try XCTUnwrap(after.first { $0.photos.contains(target.photo!) })
        XCTAssertEqual(holder.id, spread.id)
        let entry = try XCTUnwrap(holder.layout.cellRects(spec).first { $0.cell.photo == target.photo })
        XCTAssertTrue(entry.cell.locked)
        XCTAssertEqual(entry.cell.zoom, 1.5)
        XCTAssertEqual(entry.rect.minX, oldRect.minX, accuracy: 30)
        XCTAssertEqual(after.flatMap(\.photos).sorted(), doc.photos.sorted())
    }

    func testAlternativesAreDistinctAndIncludeCrossSpineOnes() {
        let photos = [photo("a.jpg", 1.5, at: 0), photo("b.jpg", 2.0 / 3, at: 5), photo("c.jpg", 2.0 / 3, at: 10)]
        var doc = AlbumDocument(typeName: "Prueba", spec: spec, photos: photos.map(\.name))
        for p in photos { doc.info[p.name] = p.info }
        let spread = AlbumAutoLayout.bestSpread(photos, spec: spec).spread
        let options = AlbumAutoLayout.alternatives(for: spread, document: doc)
        XCTAssertGreaterThan(options.count, 10)
        let shapes = options.map { $0.cellRects(spec).map { $0.rect.integral } }
        XCTAssertEqual(Set(shapes.map { "\($0)" }).count, shapes.count)
        XCTAssertTrue(options.contains { if case .full = $0, $0.cells.count > 1 { return true }; return false })
    }

    func testCrossSpineMultiPhotoLayoutWhenItFitsBest() {
        // Una apaisada muy ancha (sin ser panorámica) con las caras a un lado y dos detalles:
        // lo mejor es que la grande cruce el lomo y los detalles vayan al lado.
        let photos = [photo("grande.jpg", 1.9, at: 0, faces: [0.15, 0.15], faceX: 0.2),
                      photo("d1.jpg", 1, at: 5), photo("d2.jpg", 1, at: 10)]
        let spread = AlbumAutoLayout.bestSpread(photos, spec: spec).spread
        guard case .full = spread.layout else { return XCTFail("Debería cruzar el lomo: \(spread.layout)") }
        let big = spread.layout.cellRects(spec).first { $0.cell.photo == "grande.jpg" }!.rect
        XCTAssertGreaterThan(big.maxX, spec.spineStrip.maxX)
    }

    func testLargeAlbumIsQuick() {
        let photos = (0..<150).map { photo("p\($0).jpg", $0 % 3 == 0 ? 2.0 / 3 : 1.5, at: Double($0) * 30) }
        let clock = Date()
        let spreads = AlbumAutoLayout.distribute(photos, spec: spec)
        print("ÁLBUM: 150 fotos en \(spreads.count) pliegos, \(Date().timeIntervalSince(clock)) s")
        XCTAssertEqual(spreads.flatMap(\.photos).count, 150)
    }

    // MARK: - Fase 3: a sangre y exportación

    /// Pliego pequeño para que la exportación vaya rápida: páginas de 10 × 10 cm.
    private let small = AlbumSpec(pageWidthMM: 100, pageHeightMM: 100, bleedMM: 3, safetyMM: 10, spineMM: 5, ppi: 300)

    func testBleedExtendsOnlyTheSidesThatTouchTheMargin() {
        let cell = AlbumCell(photo: "a.jpg", bleed: true)
        // Página izquierda entera: arriba, abajo e izquierda hasta el sangrado; el lado del lomo, hasta el lomo.
        let page = AlbumSpreadLayout.pages(left: AlbumBlock(node: .cell(cell)), right: nil)
        XCTAssertEqual(page.drawRects(small)[0].rect, CGRect(x: -3, y: -3, width: 103, height: 106))
        XCTAssertEqual(page.cellRects(small)[0].rect, CGRect(x: 10, y: 10, width: 80, height: 80))
        XCTAssertTrue(page.touchesMargin(cell.id, spec: small))
        // Pliego entero: hasta el sangrado por los cuatro lados.
        let full = AlbumSpreadLayout.full(AlbumBlock(node: .cell(cell)))
        XCTAssertEqual(full.drawRects(small)[0].rect, CGRect(x: -3, y: -3, width: 206, height: 106))
        // Una casilla en medio (bloque con blanco alrededor) no toca ningún margen.
        let inner = AlbumSpreadLayout.pages(left: AlbumBlock(node: .cell(cell), area: CGRect(x: 0.25, y: 0.25, width: 0.5, height: 0.5)), right: nil)
        XCTAssertFalse(inner.touchesMargin(cell.id, spec: small))
        XCTAssertEqual(inner.drawRects(small)[0].rect, inner.cellRects(small)[0].rect)
    }

    func testEffectivePPI() {
        // 3000 px a lo ancho en 254 mm (10 pulgadas) = 300 ppp; ampliada al doble, 150.
        let rect = CGRect(x: 0, y: 0, width: 254, height: 254 / 1.5)
        let size = PixelSize(width: 3000, height: 2000)
        let centre = CGPoint(x: 0.5, y: 0.5)
        XCTAssertEqual(AlbumExport.effectivePPI(pixels: size, cell: AlbumCell(photo: "a"), rect: rect, focus: centre), 300, accuracy: 0.5)
        XCTAssertEqual(AlbumExport.effectivePPI(pixels: size, cell: AlbumCell(photo: "a", zoom: 2), rect: rect, focus: centre), 150, accuracy: 0.5)
        XCTAssertEqual(AlbumExport.level(for: 180), .low)
        XCTAssertEqual(AlbumExport.level(for: 120), .veryLow)
        XCTAssertEqual(AlbumExport.level(for: 260), .ok)
    }

    func testIssuesListsOnlyTheLowOnes() {
        var doc = AlbumDocument(typeName: "Prueba", spec: small, photos: ["grande.jpg", "chica.jpg"])
        doc.spreads = [AlbumSpread(layout: .pages(left: AlbumBlock(node: .cell(AlbumCell(photo: "grande.jpg"))),
                                                  right: AlbumBlock(node: .cell(AlbumCell(photo: "chica.jpg")))))]
        // 80 mm son 3,15 pulgadas: 3000 px dan de sobra; 400 px, unos 127 ppp.
        let issues = AlbumExport.issues(in: doc, pixels: ["grande.jpg": PixelSize(width: 3000, height: 3000), "chica.jpg": PixelSize(width: 400, height: 400)])
        XCTAssertEqual(issues.map(\.photo), ["chica.jpg"])
        XCTAssertEqual(issues.first?.level, .veryLow)
    }

    func testRenderDrawsPhotosBleedAndWhite() throws {
        let folder = try TestImages.makeTempFolder()
        defer { try? FileManager.default.removeItem(at: folder) }
        try TestImages.write(TestImages.solid(width: 600, height: 600, r: 1, g: 0, b: 0), to: folder.appendingPathComponent("rojo.jpg"))
        var doc = AlbumDocument(typeName: "Prueba", spec: small, photos: ["rojo.jpg"])
        doc.spreads = [AlbumSpread(layout: .pages(left: AlbumBlock(node: .cell(AlbumCell(photo: "rojo.jpg"))), right: nil))]
        let image = try AlbumExport.render(doc.spreads[0], document: doc, folder: folder)
        XCTAssertEqual(image.width, small.exportPixelSize.width)
        XCTAssertEqual(image.height, small.exportPixelSize.height)
        let mm = 300 / 25.4
        let px = { (x: Double, y: Double) in TestImages.pixel(image, x: Int((x + 3) * mm), y: Int((y + 3) * mm)) }
        XCTAssertTrue(TestImages.isRed(px(50, 50)), "Centro de la página izquierda")
        XCTAssertTrue(TestImages.isWhite(px(-2, 50)), "Sangrado sin «a sangre»")
        XCTAssertTrue(TestImages.isWhite(px(150, 50)), "Página derecha en blanco")
        // A sangre: el sangrado también lleva foto.
        doc.spreads[0].layout = doc.spreads[0].layout.updatingCell(doc.spreads[0].layout.cells[0].id) { $0.bleed = true }
        let bled = try AlbumExport.render(doc.spreads[0], document: doc, folder: folder)
        XCTAssertTrue(TestImages.isRed(TestImages.pixel(bled, x: 3, y: Int(53 * mm))))
    }

    func testExportWritesNumberedFilesAndReplacesThePreviousOnes() async throws {
        let photos = try TestImages.makeTempFolder()
        let out = try TestImages.makeTempFolder()
        defer { try? FileManager.default.removeItem(at: photos); try? FileManager.default.removeItem(at: out) }
        for name in ["a.jpg", "b.jpg", "c.jpg"] { try TestImages.makePhoto(in: photos, name: name) }
        var doc = AlbumDocument(typeName: "Prueba", spec: small, photos: ["a.jpg", "b.jpg", "c.jpg"])
        doc.spreads = ["a.jpg", "b.jpg", "c.jpg"].map { AlbumSpread(layout: .pages(left: AlbumBlock(node: .cell(AlbumCell(photo: $0))), right: nil)) }
        doc.spreads.append(AlbumSpread())   // uno en blanco: también sale, para no saltar números
        // Lo de una exportación anterior con más pliegos, y un fichero que no es nuestro.
        try Data("viejo".utf8).write(to: out.appendingPathComponent("07.jpg"))
        try Data("mío".utf8).write(to: out.appendingPathComponent("portada.jpg"))
        let remove: (URL) throws -> Void = { try FileManager.default.removeItem(at: $0) }
        let summary = try await AlbumExport.export(doc, photos: photos, to: out, trash: remove)
        XCTAssertEqual(summary.processed, 4)
        let names = try FileManager.default.contentsOfDirectory(atPath: out.path).sorted()
        XCTAssertEqual(names, ["01.jpg", "02.jpg", "03.jpg", "04.jpg", "portada.jpg"])
        // Ppp, medida y perfil sRGB dentro del JPEG.
        let props = try XCTUnwrap(ImageIOHelpers.properties(of: out.appendingPathComponent("01.jpg")))
        XCTAssertEqual((props[kCGImagePropertyDPIWidth] as? NSNumber)?.intValue, 300)
        XCTAssertEqual((props[kCGImagePropertyPixelWidth] as? NSNumber)?.intValue, small.exportPixelSize.width)
        XCTAssertTrue(((props[kCGImagePropertyProfileName] as? String) ?? "").contains("sRGB"))
        // Exportar solo un pliego no toca los demás.
        let before = try FileManager.default.attributesOfItem(atPath: out.appendingPathComponent("01.jpg").path)[.modificationDate] as? Date
        try await Task.sleep(for: .milliseconds(1100))
        _ = try await AlbumExport.export(doc, photos: photos, to: out, only: 1, trash: remove)
        let after = try FileManager.default.attributesOfItem(atPath: out.appendingPathComponent("01.jpg").path)[.modificationDate] as? Date
        XCTAssertEqual(before, after)
        XCTAssertEqual(AlbumExport.fileName(4, of: 120), "005.jpg")
    }

    // MARK: - Fase 4: páginas sueltas y portada

    func testCoverGeometryHasARealSpine() throws {
        var album = spec
        album.cover = AlbumCover(widthMM: 310, heightMM: 310, spineWidthMM: 20, bleedMM: 15)
        let cover = try XCTUnwrap(album.coverSpec)
        XCTAssertEqual(cover.spreadSize, CGSize(width: 640, height: 310))
        XCTAssertEqual(cover.spineCenter, 320)
        XCTAssertEqual(cover.pageContent(.right).minX, 340)
        XCTAssertEqual(cover.spineStrip, CGRect(x: 300, y: 0, width: 40, height: 310))
        // 670 × 340 mm a 300 ppp.
        XCTAssertEqual(cover.exportPixelSize, PixelSize(width: 7913, height: 4016))
        // La portada de partida: la primera foto a sangre en la tapa (página derecha).
        let start = AlbumDocument.initialCover(photo: "a.jpg")
        let rect = start.layout.drawRects(cover)[0].rect
        XCTAssertEqual(rect, CGRect(x: 330, y: -15, width: 325, height: 340))
    }

    func testFirstAndLastSpreadsUseASinglePage() {
        var s = spec
        s.singleFirstLast = true
        let photos = (0..<16).map { photo("p\($0).jpg", $0 % 3 == 0 ? 2.0 / 3 : 1.5, at: Double($0) * 60) }
        for count in [nil, 5] as [Int?] {
            let spreads = AlbumAutoLayout.distribute(photos, spec: s, spreadCount: count)
            XCTAssertEqual(spreads.flatMap(\.photos), photos.map(\.name))
            guard case .pages(nil, .some) = spreads.first?.layout else { return XCTFail("El primero solo con la derecha") }
            guard case .pages(.some, nil) = spreads.last?.layout else { return XCTFail("El último solo con la izquierda") }
            for spread in spreads.dropFirst().dropLast() {
                if case .pages(nil, _) = spread.layout { XCTFail("Un pliego de en medio sin página izquierda") }
            }
        }
        var doc = AlbumDocument(typeName: "Prueba", spec: s, photos: photos.map(\.name))
        for p in photos { doc.info[p.name] = p.info }
        doc.spreads = AlbumAutoLayout.redistribute(doc)
        XCTAssertEqual(doc.singleSide(ofSpread: 0), .right)
        XCTAssertEqual(doc.singleSide(ofSpread: doc.spreads.count - 1), .left)
        XCTAssertNil(doc.singleSide(ofSpread: 1))
        // Otras composiciones del primero, también solo con la derecha.
        for option in AlbumAutoLayout.alternatives(for: doc.spreads[0], document: doc, side: .right) {
            guard case .pages(nil, .some) = option else { return XCTFail("Alternativa con la izquierda") }
        }
    }

    func testExportWithSinglePagesAndCover() async throws {
        let photos = try TestImages.makeTempFolder()
        let out = try TestImages.makeTempFolder()
        defer { try? FileManager.default.removeItem(at: photos); try? FileManager.default.removeItem(at: out) }
        for name in ["a.jpg", "b.jpg", "c.jpg"] { try TestImages.makePhoto(in: photos, name: name) }
        var s = small
        s.singleFirstLast = true
        s.singlePageExport = .pageOnly
        s.cover = AlbumCover(widthMM: 105, heightMM: 105, spineWidthMM: 8, bleedMM: 12)
        var doc = AlbumDocument(typeName: "Prueba", spec: s, photos: ["a.jpg", "b.jpg", "c.jpg"])
        let cell = { (name: String) in AlbumBlock(node: .cell(AlbumCell(photo: name, bleed: true))) }
        doc.spreads = [AlbumSpread(layout: .pages(left: nil, right: cell("a.jpg"))),
                       AlbumSpread(layout: .pages(left: cell("b.jpg"), right: nil)),
                       AlbumSpread(layout: .pages(left: cell("c.jpg"), right: nil))]
        doc.cover = AlbumDocument.initialCover(photo: "a.jpg")
        let remove: (URL) throws -> Void = { try FileManager.default.removeItem(at: $0) }
        let summary = try await AlbumExport.export(doc, photos: photos, to: out, trash: remove)
        XCTAssertEqual(summary.processed, 4)
        let width = { (name: String) in (ImageIOHelpers.properties(of: out.appendingPathComponent(name))?[kCGImagePropertyPixelWidth] as? NSNumber)?.intValue }
        XCTAssertEqual(width("00.jpg"), s.coverSpec?.exportPixelSize.width)
        XCTAssertEqual(width("01.jpg"), s.pagePixelSize.width)
        XCTAssertEqual(width("02.jpg"), s.exportPixelSize.width)
        XCTAssertEqual(width("03.jpg"), s.pagePixelSize.width)
        // La página sola a sangre por el lado del lomo: también ahí llega la foto (no queda blanco).
        let first = try ImageIOHelpers.loadImage(from: out.appendingPathComponent("01.jpg"))
        XCTAssertFalse(TestImages.isWhite(TestImages.pixel(first, x: 2, y: first.height / 2)))
        // Solo la portada.
        try FileManager.default.removeItem(at: out.appendingPathComponent("00.jpg"))
        _ = try await AlbumExport.export(doc, photos: photos, to: out, only: AlbumExport.coverIndex, trash: remove)
        XCTAssertTrue(FileManager.default.fileExists(atPath: out.appendingPathComponent("00.jpg").path))
    }

    func testChangingTheSpreadCountKeepsItAndTheLocks() {
        var doc = document(20)
        let count = doc.spreads.count
        doc.spreads[count - 1].locked = true
        let locked = doc.spreads[count - 1]
        // Un pliego más: todo el álbum con uno más, y el del candado igual.
        doc.spec.spreads = count + 1
        let more = AlbumAutoLayout.redistribute(doc, from: 0)
        XCTAssertEqual(more.count, count + 1)
        XCTAssertTrue(more.contains(locked))
        XCTAssertTrue(more.allSatisfy { !$0.photos.isEmpty })
        // Uno menos quitando uno de en medio: sus fotos se reparten y no sale otro pliego.
        doc.spec.spreads = count - 1
        doc.spreads.remove(at: 1)
        let fewer = AlbumAutoLayout.redistribute(doc, from: 0)
        XCTAssertEqual(fewer.count, count - 1)
        XCTAssertTrue(fewer.contains(locked))
        XCTAssertEqual(fewer.flatMap(\.photos).sorted(), doc.photos.sorted())
    }

    // MARK: - Reparto a mano

    func testRequestedCountsAreKeptInEverySpread() {
        // Número fijo: el 2.º con 2 fotos y el 4.º con 6.
        var doc = document(24)
        let count = doc.spreads.count
        doc.spec.spreads = count
        doc.spreads[1].manualCount = 2
        doc.spreads[3].manualCount = 6
        let fixed = AlbumAutoLayout.redistribute(doc, from: 0)
        XCTAssertEqual(fixed.count, count)
        XCTAssertEqual(fixed[1].photos.count, 2)
        XCTAssertEqual(fixed[3].photos.count, 6)
        XCTAssertEqual(fixed[3].manualCount, 6)
        XCTAssertEqual(fixed.flatMap(\.photos), doc.photos)
        // Número libre: también se respetan.
        doc.spec.spreads = nil
        let free = AlbumAutoLayout.redistribute(doc, from: 0)
        XCTAssertEqual(free[1].photos.count, 2)
        XCTAssertEqual(free[3].photos.count, 6)
        XCTAssertEqual(free.flatMap(\.photos), doc.photos)
    }

    func testUnplacedPhotosAndEmptyCellsGetLaidOut() {
        var doc = document(12)
        // A mano: entra una foto nueva (sin colocar) y otra sale dejando su casilla vacía.
        let leaving = doc.spreads[0].photos[0]
        doc.spreads[0].layout = doc.spreads[0].layout.settingPhoto(nil, in: doc.spreads[0].layout.cells[0].id)
        doc.photos.removeAll { $0 == leaving }
        doc.photos.insert("nueva.jpg", at: 3)
        doc.info["nueva.jpg"] = AlbumPhotoInfo(aspect: 1.5, captureDate: start.addingTimeInterval(130), faces: [])
        XCTAssertEqual(doc.unplacedPhotos, ["nueva.jpg"])
        let spreads = AlbumAutoLayout.redistribute(doc, from: 0)
        XCTAssertEqual(spreads.flatMap(\.photos), doc.photos)
        XCTAssertTrue(spreads.allSatisfy { $0.layout.cells.allSatisfy { $0.photo != nil } })
    }

    func testOldAlbumsOpenInManualWithNothingPending() throws {
        let doc = try JSONDecoder().decode(AlbumDocument.self, from: Data(#"{"typeName": "Viejo", "photos": ["a.jpg"]}"#.utf8))
        XCTAssertFalse(doc.autoLayout)
        XCTAssertFalse(doc.pendingLayout)
    }

    // MARK: - Pliego vacío

    func testEmptyLayoutsHaveEmptyCells() {
        let layouts = AlbumAutoLayout.emptyLayouts(count: 3, spec: spec)
        XCTAssertGreaterThan(layouts.count, 5)
        XCTAssertTrue(layouts.allSatisfy { $0.cells.count == 3 && $0.cells.allSatisfy { $0.photo == nil } })
        XCTAssertTrue(layouts.contains { if case .full = $0 { return true }; return false })
        // La de partida no cruza el lomo.
        if case .full = layouts[0] { XCTFail("La rejilla de partida cruza el lomo") }
        // Tampoco cuando se pide solo una (la de partida de un pliego vacío).
        if case .full = AlbumAutoLayout.emptyLayouts(count: 3, spec: spec, limit: 1)[0] { XCTFail("Con limit 1 cruza el lomo") }
        // Pliego de una página: solo la derecha.
        for layout in AlbumAutoLayout.emptyLayouts(count: 2, spec: spec, side: .right) {
            guard case .pages(nil, .some) = layout else { return XCTFail("Con la izquierda") }
        }
    }

    func testRecomposedAddsAPhotoKeepingThePinnedOne() throws {
        var doc = document(12)
        let spread = doc.spreads[0]
        let pinned = try XCTUnwrap(spread.layout.cells.first)
        doc.spreads[0].layout = spread.layout.updatingCell(pinned.id) { $0.locked = true }
        let extra = doc.photos.last!
        let layout = AlbumAutoLayout.recomposed(doc.spreads[0], adding: extra, document: doc)
        XCTAssertEqual(Set(layout.cells.compactMap(\.photo)), Set(spread.photos + [extra]))
        XCTAssertTrue(layout.cells.contains { $0.photo == pinned.photo && $0.locked })
    }

    func testLockedEmptySpreadSurvivesLayingOut() {
        var doc = document(12)
        doc.spec.spreads = doc.spreads.count + 1
        let empty = AlbumSpread(layout: AlbumAutoLayout.emptyLayouts(count: 3, spec: spec)[0], locked: true)
        doc.spreads.insert(empty, at: 1)
        let after = AlbumAutoLayout.redistribute(doc, from: 0)
        XCTAssertEqual(after[1], empty)
        XCTAssertEqual(after.flatMap(\.photos).sorted(), doc.photos.sorted())
    }

    // MARK: - Dividir, fusionar y quitar casillas

    /// Página izquierda: columna con una vacía encima de una foto, y al lado otra foto.
    private func tableLayout() -> (layout: AlbumSpreadLayout, empty: AlbumCell, below: AlbumCell, side: AlbumCell) {
        let empty = AlbumCell(photo: nil), below = AlbumCell(photo: "b.jpg"), side = AlbumCell(photo: "c.jpg")
        let column = AlbumNode.split(axis: .rows, fractions: [1, 1], children: [.cell(empty), .cell(below)])
        let node = AlbumNode.split(axis: .columns, fractions: [1, 1], children: [column, .cell(side)])
        return (.pages(left: AlbumBlock(node: node), right: nil), empty, below, side)
    }

    func testMergingAnEmptyCellKeepsTheOtherPhoto() throws {
        let t = tableLayout()
        // La vacía con la de abajo: la foto ocupa toda la columna.
        let merged = try XCTUnwrap(t.layout.merging(t.empty.id, side: .bottom))
        XCTAssertNil(merged.displaced)
        let rects = merged.layout.cellRects(spec)
        XCTAssertEqual(rects.map(\.cell.photo), ["b.jpg", "c.jpg"])
        XCTAssertEqual(rects[0].rect.height, spec.pageContent(.left).height, accuracy: 0.01)
        // No hay vecina arriba ni a la izquierda de la vacía.
        XCTAssertNil(t.layout.merging(t.empty.id, side: .top))
        XCTAssertNil(t.layout.merging(t.empty.id, side: .left))
    }

    func testMergingTwoPhotosDisplacesTheOther() throws {
        let t = tableLayout()
        let full = t.layout.settingPhoto("a.jpg", in: t.empty.id)
        let merged = try XCTUnwrap(full.merging(t.empty.id, side: .bottom))
        XCTAssertEqual(merged.displaced, "b.jpg")
        XCTAssertEqual(merged.layout.cells.compactMap(\.photo), ["a.jpg", "c.jpg"])
        // Con la de abajo fijada, no se fusiona (se perdería).
        let pinned = full.updatingCell(t.below.id) { $0.locked = true }
        XCTAssertNil(pinned.merging(t.empty.id, side: .bottom))
    }

    func testSplittingAddsAnEmptyCell() {
        let t = tableLayout()
        // En la columna (filas): se añade a ella, a medias con la elegida.
        let rows = t.layout.splitting(t.below.id, axis: .rows)
        XCTAssertEqual(rows.cells.count, 4)
        let rects = rows.cellRects(spec)
        XCTAssertEqual(rects[1].rect.height, rects[2].rect.height, accuracy: 0.01)
        // La de al lado, en columnas: también se añade a su corte.
        let columns = t.layout.splitting(t.side.id, axis: .columns)
        XCTAssertEqual(columns.cells.map(\.photo), [nil, "b.jpg", "c.jpg", nil])
    }

    func testRemovingCellsSimplifiesAndCanEmptyThePage() throws {
        let t = tableLayout()
        let removed = try XCTUnwrap(t.layout.removing(t.empty.id))
        XCTAssertNil(removed.displaced)
        XCTAssertEqual(removed.layout.cells.compactMap(\.photo), ["b.jpg", "c.jpg"])
        let second = try XCTUnwrap(removed.layout.removing(t.below.id))
        XCTAssertEqual(second.displaced, "b.jpg")
        let last = try XCTUnwrap(second.layout.removing(t.side.id))
        guard case .pages(nil, nil) = last.layout else { return XCTFail("La página debería quedar en blanco") }
        // Una foto fijada no se quita.
        XCTAssertNil(t.layout.updatingCell(t.below.id) { $0.locked = true }.removing(t.below.id))
    }

    func testComposedWithMoreOrFewerCells() {
        let doc = document(12)
        let photos = Array(doc.photos.prefix(3))
        let more = AlbumAutoLayout.composed(photos, cells: 5, document: doc)
        XCTAssertEqual(more.cells.count, 5)
        XCTAssertEqual(more.cells.compactMap(\.photo).sorted(), photos.sorted())
        let fewer = AlbumAutoLayout.composed(photos, cells: 2, document: doc)
        XCTAssertEqual(fewer.cells.compactMap(\.photo).sorted(), Array(photos.prefix(2)).sorted())
    }

    // MARK: - Proporciones

    func testNoPhotoChangesOrientation() {
        // Mezcla de verticales (2:3, 4:5), apaisadas (3:2, 16:9) y cuadradas.
        let aspects = [2.0 / 3, 1.5, 0.8, 16.0 / 9, 1, 1.5, 2.0 / 3, 0.8, 1.5, 1.5, 2.0 / 3, 1.25, 0.8, 1.5, 2.0 / 3, 1.5]
        let photos = aspects.enumerated().map { i, a in photo("p\(i).jpg", a, at: Double(i) * 40, faces: [0.15], faceX: 0.45) }
        let info = Dictionary(uniqueKeysWithValues: photos.map { ($0.name, $0.info.aspect) })
        for count in [nil, 4] as [Int?] {
            for spread in AlbumAutoLayout.distribute(photos, spec: spec, spreadCount: count) {
                for entry in spread.layout.cellRects(spec) {
                    let photoAspect = info[entry.cell.photo!]!
                    let cellAspect = entry.rect.width / entry.rect.height
                    XCTAssertFalse(photoAspect < 0.9 && cellAspect > 1.1, "Vertical en casilla apaisada")
                    XCTAssertFalse(photoAspect > 1.1 && cellAspect < 0.9, "Apaisada en casilla vertical")
                }
            }
        }
    }

    func testNewAlbumsStartInAutomatic() {
        XCTAssertTrue(AlbumDocument(typeName: "Nuevo", spec: spec).autoLayout)
    }

    func testUnanalysedPhotoDoesNotPutItsCentreOnTheSpine() {
        // Sin analizar (sin caras conocidas), una vertical sola no se centra cruzando el lomo.
        let unknown = AlbumAutoLayout.Photo(name: "v.jpg", info: AlbumPhotoInfo(aspect: 2.0 / 3, captureDate: start))
        let spread = AlbumAutoLayout.bestSpread([unknown], spec: spec).spread
        for entry in spread.layout.cellRects(spec) {
            let crosses = entry.rect.minX < spec.spineStrip.minX && entry.rect.maxX > spec.spineStrip.maxX
            XCTAssertFalse(crosses && abs(entry.rect.midX - spec.spineCenter) < entry.rect.width * 0.2, "El centro de la foto cae en el lomo")
        }
    }

    func testVerticalPhotoIsNotFoldedThroughItsMiddle() {
        // Analizada, con las caras a los lados del centro: aun así no se dobla por la mitad.
        let v = photo("v.jpg", 2.0 / 3, at: 0, faces: [0.1, 0.1], faceX: 0.15)
        let spread = AlbumAutoLayout.bestSpread([v], spec: spec).spread
        for entry in spread.layout.cellRects(spec) where entry.rect.minX < spec.spineStrip.minX && entry.rect.maxX > spec.spineStrip.maxX {
            let fold = (spec.spineCenter - entry.rect.minX) / entry.rect.width
            XCTAssertFalse(fold > 0.3 && fold < 0.7, "La vertical se dobla por el centro")
        }
    }

    func testTemplatesHaveNoDuplicateGrids() {
        XCTAssertEqual(AlbumTemplates.templates(photos: 1).count, 1)
        XCTAssertGreaterThan(AlbumTemplates.templates(photos: 3).count, 5)
    }

    func testComposedEmptyCellsDoNotCrossTheSpine() {
        let doc = document(12)
        let layout = AlbumAutoLayout.composed(Array(doc.photos.prefix(2)), cells: 3, document: doc)
        for entry in layout.cellRects(spec) where entry.cell.photo == nil {
            XCTAssertFalse(entry.rect.intersects(spec.spineStrip), "La casilla vacía toca el lomo")
        }
    }

    func testComposedOptionsKeepTheEmptyCells() {
        let doc = document(12)
        let photos = Array(doc.photos.prefix(2))
        let options = AlbumAutoLayout.composedOptions(photos, cells: 4, document: doc)
        XCTAssertGreaterThan(options.count, 3)
        for layout in options {
            XCTAssertEqual(layout.cells.count, 4)
            XCTAssertEqual(layout.cells.compactMap(\.photo).sorted(), photos.sorted())
        }
    }
}
