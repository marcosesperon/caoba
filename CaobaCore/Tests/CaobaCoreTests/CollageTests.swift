import Testing
import Foundation
import CoreGraphics
@testable import CaobaCore

@Suite("CollageTemplates")
struct CollageTemplatesTests {
    @Test("El catálogo se carga del JSON y tiene las cuentas esperadas")
    func catalog() {
        let all = CollageTemplates.all
        #expect(all.count == 860)
        #expect(all.filter(\.overlap).count == 112)
        // Sin identificadores repetidos y con tantas celdas como fotos.
        #expect(Set(all.map(\.id)).count == all.count)
        #expect(all.allSatisfy { $0.cells.count == $0.photos })
        // Hay plantillas de 7, 8 y 9 fotos para que «Componer» pueda formar grupos grandes.
        #expect((7...9).allSatisfy { n in CollageTemplates.filter(photos: n).count >= 40 })
        #expect(CollageTemplates.template(id: "16_9_strips_v9")?.cells.count == 9)
        #expect(CollageTemplates.filter(photos: 4).allSatisfy { $0.photos == 4 && !$0.overlap })
        #expect(CollageTemplates.filter(photos: 2, aspectLabel: "16:9").isEmpty == false)
        #expect(CollageTemplates.template(id: "grid_2x2")?.cells.count == 4)
        #expect(CollageTemplates.aspectLabels.first == "3:1")
        // Filtro por tipo: las superpuestas solo salen si se piden, y el tipo acota.
        #expect(CollageTemplates.filter(includeOverlap: true, type: .overlap).count == 112)
        #expect(CollageTemplates.filter(includeOverlap: true, type: .basic).count == 860 - 112 - 70)
        // Las redondas salen también sin pedir superpuestas (van en Collage).
        #expect(CollageTemplates.filter(type: .round).count == 70)
        #expect(CollageTemplates.filter().contains { $0.isRound })
        #expect(CollageTemplates.filter(includeOverlap: false, type: .overlap).isEmpty)
        // Todas las celdas dentro del lienzo.
        for t in all { for c in t.cells { #expect(c.x >= 0 && c.y >= 0 && c.x + c.w <= 1.0001 && c.y + c.h <= 1.0001) } }
    }

    @Test("Celdas redondas: las plantillas antiguas no llevan forma y el círculo es cuadrado en píxeles en todas las proporciones")
    func roundCells() throws {
        #expect(CollageTemplates.template(id: "grid_2x2")?.cells.allSatisfy { $0.shape == nil } == true)
        let round = CollageTemplates.filter(type: .round)
        for t in round {
            let canvas = t.canvasSize(longestSide: 1000)
            let circles = t.cells.filter(\.isCircle)
            #expect(circles.count == 1 && t.cells.last?.isCircle == true, "el círculo va el último en \(t.id)")
            for c in circles {
                let w = c.w * Double(canvas.width), h = c.h * Double(canvas.height)
                #expect(abs(w - h) <= 2, "\(t.id): \(w) × \(h)")
            }
        }
        // Se lee y se guarda la forma.
        let data = #"{"x":0,"y":0,"w":0.5,"h":0.5,"shape":"circle"}"#.data(using: .utf8)!
        #expect(try JSONDecoder().decode(CollageCell.self, from: data).isCircle)
    }

    @Test("Tamaño del lienzo según el lado mayor")
    func canvasSize() {
        let t = CollageTemplates.template(id: "single_16_9")!
        #expect(t.canvasSize(longestSide: 1920) == PixelSize(width: 1920, height: 1080))
        let v = CollageTemplates.template(id: "single_9_16")!
        #expect(v.canvasSize(longestSide: 1920) == PixelSize(width: 1080, height: 1920))
    }
}

@Suite("Collage redondo")
struct RoundCollageTests {
    @Test("El círculo se recorta en redondo encima de la foto de debajo, con aro del color del fondo")
    func render() throws {
        let folder = try TestImages.makeTempFolder()
        let red = try TestImages.write(TestImages.solid(width: 800, height: 800, r: 1, g: 0, b: 0), to: folder.appendingPathComponent("r.jpg"))
        let blue = try TestImages.write(TestImages.solid(width: 800, height: 800, r: 0, g: 0, b: 1), to: folder.appendingPathComponent("b.jpg"))
        let t = try #require(CollageTemplates.template(id: "circle_big_br"))
        let image = try CollageRenderer.render(CollageRow(template: t, files: [red, blue]), options: CollageOptions(longestSide: 800, gap: 10, background: .white))
        let circle = t.cells[1]
        let cx = Int((circle.x + circle.w / 2) * 800), cy = Int((circle.y + circle.h / 2) * 800)
        #expect(TestImages.isBlue(TestImages.pixel(image, x: cx, y: cy)))
        // Esquina del cuadro del círculo: fuera del redondo, se ve la foto de debajo.
        #expect(TestImages.isRed(TestImages.pixel(image, x: Int(circle.x * 800) + 4, y: Int(circle.y * 800) + 4)))
        // Justo fuera del círculo, el aro blanco.
        let edge = TestImages.pixel(image, x: cx, y: Int(circle.y * 800) - 2)
        #expect(TestImages.isWhite(edge))
    }
}

@Suite("CanvasColor")
struct CanvasColorTests {
    @Test("Se lee y se guarda como antes para los tres de siempre y como #RRGGBB para un color propio")
    func coding() throws {
        #expect(CanvasColor(rawValue: "white") == .white)
        let custom = try #require(CanvasColor(rawValue: "#336699"))
        #expect(custom.rawValue == "#336699")
        #expect(CanvasColor(rawValue: "#12345") == nil && CanvasColor(rawValue: "azul") == nil)
        let data = try JSONEncoder().encode([CanvasColor.black, custom])
        #expect(String(data: data, encoding: .utf8) == ##"["black","#336699"]"##)
        #expect(try JSONDecoder().decode([CanvasColor].self, from: data) == [.black, custom])
    }

    @Test("Texto claro sobre un fondo oscuro y oscuro sobre uno claro")
    func contrast() {
        let navy = CanvasColor.custom(RGBColor(red: 0.1, green: 0.15, blue: 0.35))
        let cream = CanvasColor.custom(RGBColor(red: 0.96, green: 0.93, blue: 0.85))
        #expect(navy.isDark && !cream.isDark)
        #expect(navy.text.components![0] > 0.8 && cream.text.components![0] < 0.3)
    }

    @Test("Collage y hoja de contacto dibujados con un fondo propio tienen ese color")
    func render() throws {
        let folder = try TestImages.makeTempFolder()
        let photos = try (0..<2).map { try TestImages.makePhoto(in: folder, name: "p\($0).jpg", width: 600, height: 400) }
        // #008080: tiene que salir tal cual (el color se crea en sRGB, como lo da el selector).
        let teal = CanvasColor.custom(RGBColor(red: 0, green: 128.0 / 255, blue: 128.0 / 255))
        let template = try #require(CollageTemplates.template(id: "16_9_strips_v5") ?? CollageTemplates.filter(photos: 2).first)
        let row = CollageRow(template: template, files: Array(repeating: photos[0], count: template.photos))
        let collage = try CollageRenderer.render(row, options: CollageOptions(longestSide: 600, gap: 40, background: teal))
        let a = TestImages.pixel(collage, x: 3, y: 3)
        #expect(a.r < 10 && abs(a.g - 128) <= 1 && abs(a.b - 128) <= 1)
        let sheet = try ContactSheetRenderer.render(files: photos, options: ContactSheetOptions(columns: 2, thumbSize: 120, background: teal))
        let b = TestImages.pixel(sheet, x: 2, y: 2)
        #expect(b.r < 10 && abs(b.g - 128) <= 1 && abs(b.b - 128) <= 1)
    }
}

@Suite("CollageRenderer")
struct CollageRendererTests {
    struct SeededGenerator: RandomNumberGenerator {
        var state: UInt64
        mutating func next() -> UInt64 { state = state &* 6364136223846793005 &+ 1442695040888963407; return state }
    }

    private func urls(_ n: Int) -> [URL] { (0..<n).map { URL(fileURLWithPath: "/tmp/f\($0).jpg") } }

    @Test("Agrupación secuencial cicla plantillas y deja fuera lo que no completa un grupo")
    func groupingSequential() {
        let t2 = CollageTemplates.template(id: "diptico")!
        let t3 = CollageTemplates.template(id: "1mas2")!
        let (rows, leftover) = CollageRenderer.group(files: urls(8), templates: [t2, t3], mode: .sequential)
        #expect(rows.map(\.template.id) == ["diptico", "1mas2", "diptico"])
        #expect(leftover == 1)
    }

    @Test("Agrupación aleatoria no deja fotos fuera si alguna plantilla cabe")
    func groupingRandom() {
        let t2 = CollageTemplates.template(id: "diptico")!
        let t3 = CollageTemplates.template(id: "1mas2")!
        var g = SeededGenerator(state: 42)
        let (rows, leftover) = CollageRenderer.group(files: urls(9), templates: [t2, t3], mode: .random, generator: &g)
        #expect(leftover == 0)
        #expect(rows.reduce(0) { $0 + $1.files.count } == 9)
    }

    @Test("Asignación por proporción pone la foto apaisada en la celda apaisada")
    func assignByAspect() {
        // Celdas: una muy ancha (3.0), una cuadrada (1.0), una vertical (0.5).
        let assignment = CollageRenderer.assignByAspect(photoAspects: [1.0, 0.6, 2.8], cellAspects: [3.0, 1.0, 0.5])
        #expect(assignment == [2, 0, 1])
        #expect(CollageRenderer.assignByAspect(photoAspects: [1, 1], cellAspects: [1]) == [0, 1])
    }

    @Test("Geometría de celdas: gap entero en bordes y medio entre vecinas")
    func cellGeometry() {
        let canvas = PixelSize(width: 1000, height: 500)
        let left = CollageRenderer.cellRect(CollageCell(x: 0, y: 0, w: 0.5, h: 1), canvas: canvas, imageAreaTop: 0, gap: 10)
        #expect(left == CGRect(x: 10, y: 10, width: 485, height: 480))
        let right = CollageRenderer.cellRect(CollageCell(x: 0.5, y: 0, w: 0.5, h: 1), canvas: canvas, imageAreaTop: 0, gap: 10)
        #expect(right == CGRect(x: 505, y: 10, width: 485, height: 480))
        let titled = CollageRenderer.cellRect(CollageCell(x: 0, y: 0, w: 1, h: 1), canvas: PixelSize(width: 1000, height: 600), imageAreaTop: 100, gap: 0)
        #expect(titled == CGRect(x: 0, y: 100, width: 1000, height: 500))
    }

    @Test("Render de un díptico: cada mitad lleva su foto y el foco desplaza el recorte")
    func renderDiptych() throws {
        let folder = try TestImages.makeTempFolder()
        let red = folder.appendingPathComponent("red.jpg")
        try TestImages.write(TestImages.solid(width: 400, height: 400, r: 1, g: 0, b: 0), to: red)
        // Cuadrantes 800x400: con foco a la izquierda vemos rojo/azul; a la derecha, verde/blanco.
        let quads = try TestImages.makePhoto(in: folder, name: "q.jpg", width: 800, height: 400)
        let template = CollageTemplates.template(id: "diptico")! // 2:1, dos celdas 1:1
        let row = CollageRow(template: template, files: [red, quads], focusPoints: [nil, CGPoint(x: 1.0, y: 0.5)])
        let image = try CollageRenderer.render(row, options: CollageOptions(longestSide: 400, gap: 0))
        #expect(image.width == 400 && image.height == 200)
        #expect(TestImages.isRed(TestImages.pixel(image, x: 100, y: 100)))
        // Mitad derecha: celda 200x200 recortada de la foto 800x400 con foco a la derecha → verde arriba, blanco abajo.
        #expect(TestImages.isGreen(TestImages.pixel(image, x: 300, y: 50)))
        #expect(TestImages.isWhite(TestImages.pixel(image, x: 300, y: 150)))
    }

    @Test("Título, fondo, esquinas y logo no rompen el render; overlap pinta marco")
    func renderExtras() throws {
        let folder = try TestImages.makeTempFolder()
        let files = try (0..<3).map { try TestImages.makePhoto(in: folder, name: "p\($0).jpg", width: 300, height: 200) }
        let logoURL = folder.appendingPathComponent("logo.png")
        try TestImages.write(TestImages.solid(width: 40, height: 20, r: 0, g: 0, b: 1), to: logoURL, format: .png)
        let template = CollageTemplates.template(id: "1mas2")!
        let opts = CollageOptions(longestSide: 600, gap: 12, background: .black, cornerRadius: 20, title: "Boda 2024", quality: 80,
                                  logo: LogoOptions(url: logoURL, position: .topLeft, sizePercent: 20, opacity: 100))
        let image = try CollageRenderer.render(CollageRow(template: template, files: files), options: opts)
        #expect(image.width == 600 && image.height == 600 + 50)
        // Esquina superior izquierda: el logo azul (20 % de 600 = 120 px de ancho, padding 10).
        #expect(TestImages.isBlue(TestImages.pixel(image, x: 30, y: 15)))

        let overlap = CollageTemplates.all.first { $0.overlap && $0.photos == 3 }!
        let ov = try CollageRenderer.render(CollageRow(template: overlap, files: files), options: CollageOptions(longestSide: 500, shadowIntensity: 50))
        #expect(ov.width > 0)
    }

    @Test("Lote a carpeta con nombres automáticos")
    func batch() async throws {
        let folder = try TestImages.makeTempFolder()
        let files = try (0..<4).map { try TestImages.makePhoto(in: folder, name: "p\($0).jpg", width: 200, height: 200) }
        let t = CollageTemplates.template(id: "diptico")!
        let (rows, _) = CollageRenderer.group(files: files, templates: [t], mode: .sequential)
        let out = folder.appendingPathComponent("out")
        let (summary, outputs) = try await CollageRenderer.generate(rows: rows, options: CollageOptions(longestSide: 300), outputFolder: out)
        #expect(summary.processed == 2)
        #expect(outputs.map(\.lastPathComponent) == ["collage_01.jpg", "collage_02.jpg"])
        #expect(ImageIOHelpers.displaySize(of: outputs[0]) == PixelSize(width: 300, height: 150))
    }
}

@Suite("ContactSheetRenderer")
struct ContactSheetTests {
    @Test("Estimación y disposición en rejilla")
    func gridLayout() throws {
        let opts = ContactSheetOptions(columns: 3, thumbSize: 100, showFilenames: true, title: "Hoja")
        let size = ContactSheetRenderer.estimatedSize(fileCount: 7, options: opts)
        #expect(size == PixelSize(width: 3 * 120 + 10, height: 3 * 140 + 10 + 40))
        let layout = try ContactSheetRenderer.layout(fileCount: 7, aspects: [], options: opts)
        #expect(layout.frames.count == 7)
        #expect(layout.frames[0] == CGRect(x: 20, y: 60, width: 100, height: 100))
        #expect(layout.frames[4].origin == CGPoint(x: 20 + 120, y: 60 + 140))
    }

    @Test("Masonry coloca en la columna más corta sin huecos")
    func masonry() throws {
        let opts = ContactSheetOptions(columns: 2, thumbSize: 100, layout: .masonry, showFilenames: false)
        let layout = try ContactSheetRenderer.layout(fileCount: 3, aspects: [1.0, 2.0, 1.0], options: opts)
        #expect(layout.frames[0] == CGRect(x: 0, y: 0, width: 100, height: 100))
        #expect(layout.frames[1] == CGRect(x: 100, y: 0, width: 100, height: 50))
        #expect(layout.frames[2] == CGRect(x: 100, y: 50, width: 100, height: 100))
        #expect(layout.canvas == PixelSize(width: 200, height: 150))
    }

    @Test("Etiquetas acortadas")
    func labels() {
        let url = URL(fileURLWithPath: "/x/un_nombre_de_fichero_bastante_largo_de_verdad.jpg")
        #expect(ContactSheetRenderer.label(for: url, index: 2, options: ContactSheetOptions(showFilenames: true, showNumbering: true)) == "3. un_nombre_de_fich...")
        #expect(ContactSheetRenderer.label(for: url, index: 0, options: ContactSheetOptions(showFilenames: false, showNumbering: true)) == "1")
        #expect(ContactSheetRenderer.label(for: url, index: 0, options: ContactSheetOptions(showFilenames: false, showNumbering: false)) == nil)
    }

    @Test("Render completo con borde, título y cover")
    func render() async throws {
        let folder = try TestImages.makeTempFolder()
        let files = try (0..<5).map { try TestImages.makePhoto(in: folder, name: "p\($0).jpg", width: 300, height: 200) }
        let opts = ContactSheetOptions(columns: 2, thumbSize: 80, cropMode: .cover, showFilenames: true, showNumbering: true, title: "Prueba", background: .gray, showBorder: true)
        let out = folder.appendingPathComponent("sheet.jpg")
        let summary = try await ContactSheetRenderer.generate(files: files, options: opts, output: out)
        #expect(summary.processed == 5)
        let size = ImageIOHelpers.displaySize(of: out)
        #expect(size == ContactSheetRenderer.estimatedSize(fileCount: 5, options: opts))
        let image = try ImageIOHelpers.loadImage(from: out)
        // Dentro de la primera miniatura (cover de cuadrantes) debería haber rojo arriba-izquierda.
        #expect(TestImages.isRed(TestImages.pixel(image, x: 25, y: 65)))
    }
}

@Suite("FocusDetector")
struct FocusDetectorTests {
    @Test("La saliencia encuentra un objeto claro sobre fondo liso")
    func saliency() throws {
        // Fondo gris con un cuadrado rojo en la esquina inferior derecha.
        let ctx = CGContext.rgba(width: 600, height: 400)!
        ctx.setFillColor(CGColor(red: 0.5, green: 0.5, blue: 0.5, alpha: 1)); ctx.fill(CGRect(x: 0, y: 0, width: 600, height: 400))
        ctx.setFillColor(CGColor(red: 1, green: 0, blue: 0, alpha: 1)); ctx.fill(CGRect(x: 440, y: 40, width: 100, height: 100)) // CG: abajo-derecha
        let image = ctx.makeImage()!
        let result = FocusDetector.detect(image: image, mode: .saliency)
        #expect(result.point.x > 0.6)
        #expect(result.point.y > 0.6)
        #expect(FocusDetector.detect(image: image, mode: .center) == .center)
    }

    @Test("Sin caras, el modo caras cae a saliencia y la caché responde igual")
    func facesFallback() async throws {
        let folder = try TestImages.makeTempFolder()
        let url = try TestImages.makePhoto(in: folder, name: "q.jpg", width: 400, height: 300)
        let detector = FocusDetector()
        let a = await detector.focus(for: url, mode: .faces)
        let b = await detector.focus(for: url, mode: .faces)
        #expect(a == b)
        #expect(a.hasFaces == false)
    }
}
