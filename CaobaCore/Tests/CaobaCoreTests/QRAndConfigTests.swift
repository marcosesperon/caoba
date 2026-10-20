import Testing
import Foundation
import CoreGraphics
import ImageIO
@testable import CaobaCore

@Suite("QRContent")
struct QRContentTests {
    @Test("Formatos de cada tipo")
    func payloads() {
        #expect(QRContent.wifi(ssid: "Casa", password: "p;a", security: .wpa, hidden: true).payload == "WIFI:T:WPA;S:Casa;P:p\\;a;H:true;;")
        #expect(QRContent.wifi(ssid: " ", password: "x", security: .wpa, hidden: false).payload == "")
        #expect(QRContent.email(to: "a@b.c", subject: "Hola qué", body: "").payload == "mailto:a@b.c?subject=Hola%20qu%C3%A9")
        #expect(QRContent.phone(" 600 ").payload == "tel:600")
        #expect(QRContent.sms(number: "600", message: "hola").payload == "sms:600?body=hola")
        #expect(QRContent.geo(latitude: 42.88, longitude: -8.54).payload == "geo:42.880000,-8.540000")
        let v = QRContent.vcard(name: "Marcos Esperón", organization: "CAOBA", title: "", phone: "600", email: "", website: "", address: "Calle 1").payload
        #expect(v.contains("N:Esperón;Marcos;;;") && v.contains("ORG:CAOBA") && v.contains("ADR:;;Calle 1;;;;") && v.hasSuffix("END:VCARD"))
        let start = DateComponents(calendar: .current, year: 2024, month: 5, day: 31, hour: 14, minute: 22).date!
        #expect(QRContent.event(title: "Boda", location: "", start: start, end: nil).payload == "BEGIN:VEVENT\nSUMMARY:Boda\nDTSTART:20240531T142200\nEND:VEVENT")
    }
}

@Suite("QRGenerator")
struct QRGeneratorTests {
    @Test("Genera una matriz cuadrada con patrón de búsqueda en la esquina")
    func modules() throws {
        let grid = try QRGenerator.modules(for: "https://caobafoto.com", correction: .medium)
        #expect(grid.count >= 21 && grid.count == grid[0].count)
        // Las tres primeras celdas de la primera fila son oscuras (patrón de búsqueda).
        #expect(grid[0][0] && grid[0][1] && grid[0][2])
    }

    @Test("La imagen tiene el tamaño pedido, el margen claro y colores propios")
    func image() throws {
        let opts = QROptions(size: 300, foreground: RGBColor(hex: "#FF0000")!, background: .white, correction: .high, marginModules: 4)
        let img = try QRGenerator.make(text: "hola", options: opts)
        #expect(img.width == 300 && img.height == 300)
        #expect(TestImages.isWhite(TestImages.pixel(img, x: 2, y: 2)))
        // Buscamos algún píxel rojo (módulos oscuros).
        var foundRed = false
        for y in stride(from: 0, to: 300, by: 7) { for x in stride(from: 0, to: 300, by: 7) where TestImages.isRed(TestImages.pixel(img, x: x, y: y)) { foundRed = true } }
        #expect(foundRed)
    }

    @Test("Logo centrado y texto vacío da error")
    func logoAndEmpty() throws {
        let logo = TestImages.solid(width: 50, height: 50, r: 0, g: 0, b: 1)
        let img = try QRGenerator.make(text: "con logo", options: QROptions(size: 200, logoPercent: 30), logo: logo)
        #expect(TestImages.isBlue(TestImages.pixel(img, x: 100, y: 100)))
        #expect(throws: CaobaError.invalidParameters("qr.empty")) { try QRGenerator.make(text: "  ", options: QROptions()) }
        #expect(RGBColor(hex: "#1A2B3C")?.hex == "#1A2B3C")
        #expect(RGBColor(hex: "zzz") == nil)
    }
}

@Suite("CaobaConfig")
struct CaobaConfigTests {
    struct SlideshowPreset: Codable, Equatable { var mode: String; var durationPerPhoto: Double; var files: [String] }

    @Test("El orden manual de la carpeta se guarda, se lee y «Reiniciar» lo quita sin tocar el historial")
    func fileOrder() throws {
        let folder = try TestImages.makeTempFolder()
        #expect(FileOrderSettings.load(from: folder) == nil)
        try FileOrderSettings(names: ["c.jpg", "a.jpg", "b.jpg"]).save(in: folder)
        #expect(FileOrderSettings.load(from: folder)?.names == ["c.jpg", "a.jpg", "b.jpg"])
        try CaobaConfig.writeSection("renameHistory", value: ["x"], in: folder)
        CaobaConfig.resetSettings(in: folder)
        #expect(FileOrderSettings.load(from: folder) == nil)
        #expect(CaobaConfig.readSection("renameHistory", as: [String].self, from: folder) == ["x"])
        try FileOrderSettings(names: ["a.jpg"]).save(in: folder)
        try FileOrderSettings.remove(from: folder)
        #expect(FileOrderSettings.load(from: folder) == nil)
    }

    @Test("Lee un .caoba de la app antigua")
    func readsLegacy() throws {
        let folder = try TestImages.makeTempFolder()
        let legacy = """
        { "version": 1, "slideshow": { "mode": "photos", "durationPerPhoto": 4, "files": ["a.jpg", "b.jpg"] } }
        """
        try legacy.write(to: CaobaConfig.fileURL(in: folder), atomically: true, encoding: .utf8)
        let preset = CaobaConfig.readSection("slideshow", as: SlideshowPreset.self, from: folder)
        #expect(preset == SlideshowPreset(mode: "photos", durationPerPhoto: 4, files: ["a.jpg", "b.jpg"]))
        #expect(CaobaConfig.read(from: folder)?.version == 1)
    }

    @Test("Escribir una sección conserva las demás y borrar elimina el fichero")
    func writeAndDelete() throws {
        let folder = try TestImages.makeTempFolder()
        try CaobaConfig.writeSection("slideshow", value: SlideshowPreset(mode: "collage", durationPerPhoto: 3, files: []), in: folder)
        try CaobaConfig.writeSection("collage", value: ["gap": 10], in: folder)
        let config = CaobaConfig.read(from: folder)
        #expect(config?.sections.keys.sorted() == ["collage", "slideshow"])
        #expect(CaobaConfig.readSection("slideshow", as: SlideshowPreset.self, from: folder)?.mode == "collage")
        CaobaConfig.delete(from: folder)
        #expect(CaobaConfig.read(from: folder) == nil)
    }

    @Test("Fichero inválido devuelve nil")
    func invalid() throws {
        let folder = try TestImages.makeTempFolder()
        try "no es json".write(to: CaobaConfig.fileURL(in: folder), atomically: true, encoding: .utf8)
        #expect(CaobaConfig.read(from: folder) == nil)
    }
}

@Suite("FolderScanner y Thumbnails")
struct ScannerTests {
    @Test("Escanea, ignora ocultos y temporales, ordena por nombre natural y por fecha, filtra orientación")
    func scan() async throws {
        let folder = try TestImages.makeTempFolder()
        _ = try TestImages.makePhoto(in: folder, name: "img10.jpg", width: 400, height: 300, date: "2024:01:03 00:00:00")
        _ = try TestImages.makePhoto(in: folder, name: "img2.jpg", width: 300, height: 400, date: "2024:01:01 00:00:00")
        _ = try TestImages.makePhoto(in: folder, name: "img1.png", width: 400, height: 300, date: "2024:01:02 00:00:00")
        _ = try TestImages.makePhoto(in: folder, name: "rot.jpg", width: 400, height: 300, date: "2024:01:04 00:00:00", orientation: .right)
        _ = try TestImages.makePhoto(in: folder, name: ".oculta.jpg")
        _ = try TestImages.makePhoto(in: folder, name: "_caoba_temp.jpg")
        try "x".write(to: folder.appendingPathComponent("notas.txt"), atomically: true, encoding: .utf8)
        try FileManager.default.createDirectory(at: folder.appendingPathComponent("sub.jpg"), withIntermediateDirectories: true)

        let byName = try await FolderScanner().scan(folder: folder)
        #expect(byName.map(\.name) == ["img1.png", "img2.jpg", "img10.jpg", "rot.jpg"])
        let byDate = try await FolderScanner().scan(folder: folder, sort: .date)
        #expect(byDate.map(\.name) == ["img2.jpg", "img1.png", "img10.jpg", "rot.jpg"])
        let vertical = try await FolderScanner().scan(folder: folder, orientation: .vertical)
        #expect(vertical.map(\.name) == ["img2.jpg", "rot.jpg"]) // rot.jpg es 400x300 girada 90º
        let horizontal = try await FolderScanner().scan(folder: folder, orientation: .horizontal)
        #expect(horizontal.map(\.name) == ["img1.png", "img10.jpg"])
    }

    @Test("Con miniatura EXIF embebida pequeña, pedir un tamaño grande decodifica la foto real")
    func embeddedThumbnailNotReused() throws {
        let folder = try TestImages.makeTempFolder()
        let url = folder.appendingPathComponent("embedded.jpg")
        // JPEG grande con miniatura embebida (ImageIO la genera de unos 160 px).
        let dest = CGImageDestinationCreateWithURL(url as CFURL, OutputFormat.jpeg.utType.identifier as CFString, 1, nil)!
        CGImageDestinationAddImage(dest, TestImages.quadrants(width: 2000, height: 1500), [kCGImageDestinationEmbedThumbnail: true] as CFDictionary)
        #expect(CGImageDestinationFinalize(dest))
        let small = ThumbnailProvider.makeThumbnail(url: url, maxPixelSize: 80)
        #expect(small?.width == 80)
        let big = ThumbnailProvider.makeThumbnail(url: url, maxPixelSize: 1000)
        #expect(big?.width == 1000 && big?.height == 750)
        // Y no se amplía por encima del original.
        let huge = ThumbnailProvider.makeThumbnail(url: url, maxPixelSize: 5000)
        #expect(huge?.width == 2000)
    }

    @Test("Thumbnails respetan el tamaño máximo, la orientación y la caché")
    func thumbnails() async throws {
        let folder = try TestImages.makeTempFolder()
        let url = try TestImages.makePhoto(in: folder, name: "rot.jpg", width: 400, height: 200, orientation: .right)
        let provider = ThumbnailProvider()
        let t = await provider.thumbnail(for: url, maxPixelSize: 100)
        #expect(t?.width == 50 && t?.height == 100)
        #expect(TestImages.isRed(TestImages.pixel(t!, x: 40, y: 10)))
        let again = await provider.thumbnail(for: url, maxPixelSize: 100)
        #expect(again === t)
    }
}

@Suite("CollageFolderSettings")
struct CollageFolderSettingsTests {
    @Test("La sección collage se guarda y se lee del .caoba sin tocar las demás")
    func roundTrip() throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("caoba-collage-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        try CaobaConfig.writeSection("otra", value: ["x": 1], in: folder)
        let settings = CollageFolderSettings(compose: ComposeSettings(mode: "content", allowReorder: true, photosFilter: 3, aspectFilter: "16:9", typeFilter: "basic", selectedTemplates: ["grid_2x2"]))
        try settings.save(in: folder)
        #expect(CollageFolderSettings.load(from: folder) == settings)
        #expect(CaobaConfig.readSection("otra", as: [String: Int].self, from: folder) == ["x": 1])
        // Reiniciar borra la sección.
        CaobaConfig.resetSettings(in: folder)
        #expect(CollageFolderSettings.load(from: folder) == nil)
    }
}

