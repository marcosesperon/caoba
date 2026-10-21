import Testing
import Foundation
import CoreGraphics
@testable import CaobaCore

@Suite("Carrusel")
struct CarouselTests {
    @Test("El catálogo tiene los 30 tramos en los tres formatos, y no se mezcla con las plantillas de collage")
    func catalog() throws {
        #expect(CarouselTemplates.all.count == 30 * 3)
        for format in CarouselFormat.allCases {
            let list = CarouselTemplates.templates(for: format)
            #expect(list.count == 30)
            for t in list {
                #expect((1...5).contains(t.slides ?? 0) && t.cells.count == t.photos)
                for c in t.cells { #expect(c.x >= 0 && c.y >= 0 && c.x + c.w <= 1.0001 && c.y + c.h <= 1.0001, "\(t.id)") }
            }
        }
        #expect(!CollageTemplates.all.contains { $0.id.hasPrefix("carousel_") })
        // Se encuentran por id también desde el catálogo de collage (la secuencia guarda ids).
        let id = CarouselTemplates.id(base: "pano_2", format: .square)
        #expect(CollageTemplates.template(id: id)?.slides == 2)
        #expect(CarouselTemplates.baseID(of: try #require(CollageTemplates.template(id: id))) == "pano_2")
    }

    @Test("Encadenar tramos da N diapositivas del tamaño exacto del formato")
    func combine() throws {
        let folder = try TestImages.makeTempFolder()
        let photo = try TestImages.makePhoto(in: folder, name: "a.jpg", width: 900, height: 600)
        for format in CarouselFormat.allCases {
            let rows = ["pano_2", "bg_span_3_cards"].map { base -> CollageRow in
                let t = CarouselTemplates.template(id: CarouselTemplates.id(base: base, format: format))!
                return CollageRow(template: t, files: Array(repeating: photo, count: t.photos))
            }
            #expect(Carousel.slideCount(rows) == 5)
            let pano = try Carousel.renderPanorama(rows, format: format, options: CollageOptions())
            #expect(pano.width == 5 * 1080 && pano.height == format.slideSize.height)
            let slices = Carousel.slices(of: pano, slides: 5)
            #expect(slices.count == 5 && slices.allSatisfy { $0.width == 1080 && $0.height == format.slideSize.height })
        }
        #expect(CarouselFormat.portrait4x5.slideSize == PixelSize(width: 1080, height: 1350))
        #expect(CarouselFormat.portrait3x4.slideSize == PixelSize(width: 1080, height: 1440))
    }

    @Test("Una foto que cruza un corte sigue sin salto en la diapositiva siguiente")
    func continuity() throws {
        let folder = try TestImages.makeTempFolder()
        // Degradado horizontal: cada columna tiene un color distinto.
        let w = 1600, h = 1000
        let ctx = CGContext.rgba(width: w, height: h)!
        for x in 0..<w {
            ctx.setFillColor(CGColor(red: Double(x) / Double(w), green: 0.3, blue: 1 - Double(x) / Double(w), alpha: 1))
            ctx.fill(CGRect(x: x, y: 0, width: 1, height: h))
        }
        let gradient = try TestImages.write(ctx.makeImage()!, to: folder.appendingPathComponent("g.jpg"))
        let t = try #require(CarouselTemplates.template(id: CarouselTemplates.id(base: "pano_2", format: .square)))
        let pano = try Carousel.renderPanorama([CollageRow(template: t, files: [gradient])], format: .square, options: CollageOptions(gap: 0))
        let slices = Carousel.slices(of: pano, slides: 2)
        let a = TestImages.pixel(slices[0], x: 1079, y: 540), b = TestImages.pixel(slices[1], x: 0, y: 540)
        #expect(abs(a.r - b.r) <= 3 && abs(a.b - b.b) <= 3)
    }

    @Test("No pasa de 10 diapositivas y escribe 01…NN y la panorámica en una carpeta nueva")
    func generate() throws {
        let folder = try TestImages.makeTempFolder()
        let photo = try TestImages.makePhoto(in: folder, name: "a.jpg", width: 900, height: 600)
        let t = try #require(CarouselTemplates.template(id: CarouselTemplates.id(base: "pano_3", format: .portrait4x5)))
        let rows = (0..<4).map { _ in CollageRow(template: t, files: [photo]) }   // 12 diapositivas
        #expect(Carousel.slideCount(Carousel.limited(rows)) == 9)
        let out = folder.appendingPathComponent("salida")
        let first = try Carousel.generate(rows, format: .portrait4x5, options: CollageOptions(), outputFolder: out)
        let names = try FileManager.default.contentsOfDirectory(atPath: first.path).sorted()
        #expect(names == (1...9).map { String(format: "%02d.jpg", $0) } + ["panoramica.jpg"])
        // Otra vez: no pisa la anterior.
        let second = try Carousel.generate(rows, format: .portrait4x5, options: CollageOptions(), outputFolder: out)
        #expect(first.lastPathComponent == "carrusel" && second.lastPathComponent == "carrusel_2")
    }
}
