import Testing
import Foundation
import CoreGraphics
import ImageIO
@testable import CaobaCore

@Suite("ImageIOHelpers")
struct ImageIOHelpersTests {

    @Test("La imagen de cuadrantes se genera como esperamos")
    func quadrantsLayout() {
        let img = TestImages.quadrants(width: 40, height: 20)
        #expect(TestImages.isRed(TestImages.pixel(img, x: 5, y: 5)))
        #expect(TestImages.isGreen(TestImages.pixel(img, x: 35, y: 5)))
        #expect(TestImages.isBlue(TestImages.pixel(img, x: 5, y: 15)))
        #expect(TestImages.isWhite(TestImages.pixel(img, x: 35, y: 15)))
    }

    @Test("Girar en memoria: orientación 6 (right) rota 90º en sentido horario")
    func orientedRight() {
        // EXIF 6: la fila superior almacenada debe quedar a la derecha.
        let img = TestImages.quadrants(width: 40, height: 20).oriented(.right)
        #expect(img.width == 20 && img.height == 20 * 2)
        // Rojo (antes arriba-izquierda) pasa a arriba-derecha; verde a abajo-derecha.
        #expect(TestImages.isRed(TestImages.pixel(img, x: 15, y: 5)))
        #expect(TestImages.isGreen(TestImages.pixel(img, x: 15, y: 35)))
        #expect(TestImages.isBlue(TestImages.pixel(img, x: 5, y: 5)))
        #expect(TestImages.isWhite(TestImages.pixel(img, x: 5, y: 35)))
    }

    @Test("Girar en memoria: orientación 8 (left) rota 90º antihorario")
    func orientedLeft() {
        let img = TestImages.quadrants(width: 40, height: 20).oriented(.left)
        #expect(img.width == 20 && img.height == 40)
        // Rojo pasa a abajo-izquierda; verde a arriba-izquierda.
        #expect(TestImages.isRed(TestImages.pixel(img, x: 5, y: 35)))
        #expect(TestImages.isGreen(TestImages.pixel(img, x: 5, y: 5)))
        #expect(TestImages.isWhite(TestImages.pixel(img, x: 15, y: 5)))
    }

    @Test("Girar en memoria: orientaciones espejadas 5 y 7 (transpuesta y transversa)")
    func orientedMirrored() {
        let base = TestImages.quadrants(width: 40, height: 20)
        // EXIF 5 = transpuesta: rojo se queda arriba-izquierda, verde pasa a abajo-izquierda.
        let t = base.oriented(.leftMirrored)
        #expect(t.width == 20 && t.height == 40)
        #expect(TestImages.isRed(TestImages.pixel(t, x: 5, y: 5)))
        #expect(TestImages.isGreen(TestImages.pixel(t, x: 5, y: 35)))
        #expect(TestImages.isBlue(TestImages.pixel(t, x: 15, y: 5)))
        // EXIF 7 = transversa: blanco pasa a arriba-izquierda, rojo a abajo-derecha.
        let v = base.oriented(.rightMirrored)
        #expect(TestImages.isWhite(TestImages.pixel(v, x: 5, y: 5)))
        #expect(TestImages.isRed(TestImages.pixel(v, x: 15, y: 35)))
        // EXIF 2 = espejo horizontal.
        let m = base.oriented(.upMirrored)
        #expect(TestImages.isGreen(TestImages.pixel(m, x: 5, y: 5)))
    }

    @Test("Girar en memoria: orientación 3 (down) rota 180º")
    func orientedDown() {
        let img = TestImages.quadrants(width: 40, height: 20).oriented(.down)
        #expect(TestImages.isWhite(TestImages.pixel(img, x: 5, y: 5)))
        #expect(TestImages.isRed(TestImages.pixel(img, x: 35, y: 15)))
    }

    @Test("Cargar un JPEG con orientación EXIF 6 devuelve la imagen ya girada")
    func loadAppliesOrientation() throws {
        let folder = try TestImages.makeTempFolder()
        let url = try TestImages.makePhoto(in: folder, name: "rot.jpg", width: 40, height: 20, orientation: .right)
        let loaded = try ImageIOHelpers.loadImage(from: url)
        #expect(loaded.width == 20 && loaded.height == 40)
        #expect(TestImages.isRed(TestImages.pixel(loaded, x: 15, y: 5)))
        // El tamaño "visible" también se intercambia sin decodificar.
        #expect(ImageIOHelpers.displaySize(of: url) == PixelSize(width: 20, height: 40))
        // Y la rotación de ImageIO coincide con la nuestra en memoria.
        let raw = try ImageIOHelpers.loadImage(from: url, applyingOrientation: false)
        let mine = raw.oriented(.right)
        #expect(TestImages.isRed(TestImages.pixel(mine, x: 15, y: 5)))
        #expect(TestImages.isGreen(TestImages.pixel(mine, x: 15, y: 35)))
    }

    @Test("Fechas EXIF en ambos sentidos")
    func exifDates() {
        let date = ExifDate.parse("2024:05:31 14:22:10")
        #expect(date != nil)
        #expect(ExifDate.format(date!) == "2024:05:31 14:22:10")
        #expect(ExifDate.parse("0000:00:00 00:00:00") == nil)
        #expect(ExifDate.parse("   ") == nil)
    }

    @Test("sizeFitting no amplía y mantiene proporción")
    func fitting() {
        let img = TestImages.quadrants(width: 400, height: 300)
        #expect(img.sizeFitting(maxDimension: 1000) == PixelSize(width: 400, height: 300))
        #expect(img.sizeFitting(maxDimension: 200) == PixelSize(width: 200, height: 150))
    }
}
