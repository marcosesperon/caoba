import Testing
import Foundation
import CoreGraphics
import ImageIO
@testable import CaobaCore

@Suite("CropGeometry")
struct CropGeometryTests {
    @Test("Recorte 1:1 de una imagen apaisada, anclado a la izquierda y a la derecha")
    func squareCrop() {
        let size = PixelSize(width: 400, height: 300)
        let left = CropGeometry.rect(in: size, ratio: .square, anchor: .left)
        #expect(left == CGRect(x: 0, y: 0, width: 300, height: 300))
        let right = CropGeometry.rect(in: size, ratio: .square, anchor: .right)
        #expect(right == CGRect(x: 100, y: 0, width: 300, height: 300))
        let center = CropGeometry.rect(in: size, ratio: .square, anchor: .center)
        #expect(center == CGRect(x: 50, y: 0, width: 300, height: 300))
    }

    @Test("Recorte 16:9 de una imagen vertical, anclado arriba y abajo")
    func wideCropOnPortrait() {
        let size = PixelSize(width: 300, height: 400)
        let top = CropGeometry.rect(in: size, ratio: .r16x9, anchor: .top)
        #expect(top == CGRect(x: 0, y: 0, width: 300, height: 169))
        let bottom = CropGeometry.rect(in: size, ratio: .r16x9, anchor: .bottom)
        #expect(bottom?.origin.y == 231)
    }

    @Test("Recorte por punto de foco se queda dentro de la imagen")
    func focusCrop() {
        let size = PixelSize(width: 400, height: 300)
        let r = CropGeometry.rect(in: size, ratio: 1, focus: CGPoint(x: 0.95, y: 0.5))
        #expect(r == CGRect(x: 100, y: 0, width: 300, height: 300))
        let r2 = CropGeometry.rect(in: size, ratio: 1, focus: CGPoint(x: 0.0, y: 0.5))
        #expect(r2.origin.x == 0)
    }

    @Test("croppedTopLeft recorta usando coordenadas arriba-izquierda")
    func cropPixels() {
        let img = TestImages.quadrants(width: 40, height: 20)
        let bottomRight = img.croppedTopLeft(CGRect(x: 20, y: 10, width: 20, height: 10))!
        #expect(TestImages.isWhite(TestImages.pixel(bottomRight, x: 5, y: 5)))
        let topLeft = img.croppedTopLeft(CGRect(x: 0, y: 0, width: 20, height: 10))!
        #expect(TestImages.isRed(TestImages.pixel(topLeft, x: 5, y: 5)))
    }
}

@Suite("ImageProcessor")
struct ImageProcessorTests {

    @Test("Recortar y redimensionar en memoria")
    func applyOps() throws {
        let img = TestImages.quadrants(width: 400, height: 300)
        let ops = ProcessingOperations(crop: (.square, .center), resizeMaxDimension: 100)
        let out = try ImageProcessor.apply(ops, to: img)
        #expect(out.width == 100 && out.height == 100)
    }

    @Test("Procesar por lotes como copia nueva en otra carpeta conserva nombre y EXIF")
    func batchNewCopy() async throws {
        let folder = try TestImages.makeTempFolder()
        let out = folder.appendingPathComponent("salida", isDirectory: true)
        let a = try TestImages.makePhoto(in: folder, name: "a.jpg", date: "2023:01:02 03:04:05", make: "Nikon", model: "Z6")
        let b = try TestImages.makePhoto(in: folder, name: "b.png")

        let ops = ProcessingOperations(resizeMaxDimension: 200, quality: 80)
        let summary = try await ImageProcessor().process(files: [a, b], ops: ops, saveMode: .newCopy(outputFolder: out))
        #expect(summary.processed == 2 && summary.failures.isEmpty)

        let outA = out.appendingPathComponent("a.jpg")
        let outB = out.appendingPathComponent("b.png")
        #expect(FileManager.default.fileExists(atPath: outA.path))
        #expect(FileManager.default.fileExists(atPath: outB.path))
        #expect(ImageIOHelpers.displaySize(of: outA) == PixelSize(width: 200, height: 150))

        // EXIF y TIFF viajan con la copia.
        let props = ImageIOHelpers.properties(of: outA)
        let exif = props?[kCGImagePropertyExifDictionary] as? [CFString: Any]
        let tiff = props?[kCGImagePropertyTIFFDictionary] as? [CFString: Any]
        #expect(exif?[kCGImagePropertyExifDateTimeOriginal] as? String == "2023:01:02 03:04:05")
        #expect(tiff?[kCGImagePropertyTIFFModel] as? String == "Z6")
        // El PNG sigue siendo PNG (la app antigua lo convertía en JPEG a escondidas).
        #expect(ImageIOHelpers.source(for: outB).flatMap { CGImageSourceGetType($0) as String? } == "public.png")
    }

    @Test("Copia en la misma carpeta añade sufijo; sobrescribir reemplaza el original")
    func sameFolderAndOverwrite() async throws {
        let folder = try TestImages.makeTempFolder()
        let a = try TestImages.makePhoto(in: folder, name: "a.jpg", width: 400, height: 300)
        let ops = ProcessingOperations(resizeMaxDimension: 100)

        _ = try await ImageProcessor().process(files: [a], ops: ops, saveMode: .newCopy(outputFolder: nil))
        #expect(FileManager.default.fileExists(atPath: folder.appendingPathComponent("a_processed.jpg").path))
        #expect(ImageIOHelpers.displaySize(of: a) == PixelSize(width: 400, height: 300))

        _ = try await ImageProcessor().process(files: [a], ops: ops, saveMode: .overwrite)
        #expect(ImageIOHelpers.displaySize(of: a) == PixelSize(width: 100, height: 75))
    }

    @Test("Sobrescribir cambiando de formato borra el original con la extensión vieja")
    func overwriteChangingFormat() async throws {
        let folder = try TestImages.makeTempFolder()
        let a = try TestImages.makePhoto(in: folder, name: "a.jpg")
        let ops = ProcessingOperations(format: .png)
        _ = try await ImageProcessor().process(files: [a], ops: ops, saveMode: .overwrite)
        #expect(!FileManager.default.fileExists(atPath: a.path))
        #expect(FileManager.default.fileExists(atPath: folder.appendingPathComponent("a.png").path))
    }

    @Test("Autorrotar una foto con EXIF 6 deja la imagen recta y sin orientación")
    func autorotate() async throws {
        let folder = try TestImages.makeTempFolder()
        let a = try TestImages.makePhoto(in: folder, name: "rot.jpg", width: 40, height: 20, orientation: .right)
        _ = try await ImageProcessor().process(files: [a], ops: ProcessingOperations(autorotate: true), saveMode: .overwrite)
        let props = ImageIOHelpers.properties(of: a)
        #expect(props?[kCGImagePropertyPixelWidth] as? Int == 20)
        #expect(ImageIOHelpers.orientation(from: props) == .up)
    }

    @Test("La preview devuelve antes y después reducidos")
    func preview() throws {
        let folder = try TestImages.makeTempFolder()
        let a = try TestImages.makePhoto(in: folder, name: "a.jpg", width: 1600, height: 1200)
        let (before, after) = try ImageProcessor().preview(file: a, ops: ProcessingOperations(crop: (.square, .center)), maxDimension: 400)
        #expect(before.width == 400 && before.height == 300)
        #expect(after.width == 400 && after.height == 400)
    }

    @Test("Cancelar la tarea para el lote")
    func cancellation() async throws {
        let folder = try TestImages.makeTempFolder()
        let files = try (0..<5).map { try TestImages.makePhoto(in: folder, name: "f\($0).jpg") }
        let task = Task {
            try await ImageProcessor().process(files: files, ops: ProcessingOperations(resizeMaxDimension: 50), saveMode: .newCopy(outputFolder: nil))
        }
        task.cancel()
        await #expect(throws: CaobaError.cancelled) { try await task.value }
    }
}

@Suite("Watermarker")
struct WatermarkerTests {

    @Test("Marca suelta abajo-derecha con opacidad total pinta esa esquina")
    func singleBottomRight() {
        let base = TestImages.solid(width: 200, height: 100, r: 0, g: 0, b: 0)
        let mark = TestImages.solid(width: 50, height: 50, r: 1, g: 0, b: 0)
        let opts = WatermarkOptions(mode: .single, position: .bottomRight, sizePercent: 20, opacity: 100)
        let out = Watermarker.apply(mark, to: base, options: opts)
        // 20 % del lado corto (100) = 20 px de ancho, con padding 10: ocupa x 170-190, y 70-90.
        #expect(TestImages.isRed(TestImages.pixel(out, x: 180, y: 80)))
        #expect(TestImages.pixel(out, x: 20, y: 20).r < 10)
    }

    @Test("Opacidad al 50 % mezcla el color")
    func halfOpacity() {
        let base = TestImages.solid(width: 200, height: 100, r: 0, g: 0, b: 0)
        let mark = TestImages.solid(width: 50, height: 50, r: 1, g: 1, b: 1)
        let opts = WatermarkOptions(mode: .single, position: .topLeft, sizePercent: 50, opacity: 50)
        let p = TestImages.pixel(Watermarker.apply(mark, to: base, options: opts), x: 30, y: 30)
        #expect(p.r > 100 && p.r < 160)
    }

    @Test("Mosaico cubre toda la imagen")
    func tiled() {
        let base = TestImages.solid(width: 300, height: 200, r: 0, g: 0, b: 0)
        let mark = TestImages.solid(width: 10, height: 10, r: 1, g: 0, b: 0)
        let opts = WatermarkOptions(mode: .tiled, sizePercent: 10, opacity: 100, spacing: 0, spacingUnit: .pixels, rotation: 0)
        let out = Watermarker.apply(mark, to: base, options: opts)
        #expect(TestImages.isRed(TestImages.pixel(out, x: 5, y: 5)))
        #expect(TestImages.isRed(TestImages.pixel(out, x: 295, y: 195)))
        #expect(TestImages.isRed(TestImages.pixel(out, x: 150, y: 100)))
    }

    @Test("Procesar PNG por lotes mantiene el formato PNG")
    func batchKeepsFormat() async throws {
        let folder = try TestImages.makeTempFolder()
        let photo = try TestImages.makePhoto(in: folder, name: "p.png")
        let markURL = folder.appendingPathComponent("mark.png")
        try TestImages.write(TestImages.solid(width: 20, height: 20, r: 1, g: 0, b: 0), to: markURL, format: .png)
        let summary = try await Watermarker().process(files: [photo], watermark: markURL, options: WatermarkOptions(), saveMode: .newCopy(outputFolder: nil))
        #expect(summary.processed == 1)
        let out = folder.appendingPathComponent("p_watermarked.png")
        #expect(ImageIOHelpers.source(for: out).flatMap { CGImageSourceGetType($0) as String? } == "public.png")
    }
}
