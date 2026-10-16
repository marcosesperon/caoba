import Testing
import Foundation
import ImageIO
@testable import CaobaCore

@Suite("MetadataService")
struct MetadataServiceTests {

    private func photoWithMetadata(in folder: URL) throws -> URL {
        let url = folder.appendingPathComponent("meta.jpg")
        return try TestImages.write(TestImages.quadrants(width: 64, height: 48), to: url, quality: 0.9,
            exif: [kCGImagePropertyExifISOSpeedRatings: [400], kCGImagePropertyExifDateTimeOriginal: "2020:01:01 10:00:00",
                   kCGImagePropertyExifFNumber: 2.8, kCGImagePropertyExifLensModel: "50mm f/1.8"],
            tiff: [kCGImagePropertyTIFFMake: "NIKON CORPORATION", kCGImagePropertyTIFFModel: "NIKON Z 6",
                   kCGImagePropertyTIFFArtist: "ArtistaBase", kCGImagePropertyTIFFCopyright: "CopyBase",
                   kCGImagePropertyTIFFImageDescription: "DescBase"],
            gps: [kCGImagePropertyGPSLatitude: 40.5, kCGImagePropertyGPSLatitudeRef: "S",
                  kCGImagePropertyGPSLongitude: 3.25, kCGImagePropertyGPSLongitudeRef: "W"])
    }

    /// Bytes de imagen a partir del marcador SOS del JPEG: si no cambian, no se ha recomprimido.
    private func scanPayload(_ url: URL) throws -> Data {
        let bytes = [UInt8](try Data(contentsOf: url))
        for i in 0..<(bytes.count - 1) where bytes[i] == 0xFF && bytes[i + 1] == 0xDA { return Data(bytes[i...]) }
        return Data(bytes)
    }

    @Test("Lectura completa de EXIF, TIFF y GPS")
    func read() throws {
        let folder = try TestImages.makeTempFolder()
        let url = try photoWithMetadata(in: folder)
        let m = MetadataService.read(url)
        #expect(m.artist == "ArtistaBase")
        #expect(m.copyright == "CopyBase")
        #expect(m.description == "DescBase")
        #expect(m.dateTimeOriginal == "2020:01:01 10:00:00")
        #expect(m.camera == "NIKON CORPORATION NIKON Z 6")
        #expect(m.lens == "50mm f/1.8")
        #expect(m.iso == 400)
        #expect(m.fNumber == 2.8)
        #expect(m.size == PixelSize(width: 64, height: 48))
        #expect(m.gps == GPSCoordinate(latitude: -40.5, longitude: -3.25))
    }

    @Test("Escribir campos no recomprime y conserva lo demás")
    func writeKeepsPayload() throws {
        let folder = try TestImages.makeTempFolder()
        let url = try photoWithMetadata(in: folder)
        let before = try scanPayload(url)

        let edit = MetadataEdit(artist: "Marcos", copyright: "(c) CAOBA", description: "Nueva",
                                dateTimeOriginal: "2024:05:31 14:22:10",
                                gps: .some(GPSCoordinate(latitude: 42.8805, longitude: -8.5456)))
        try MetadataService.write(edit, to: url)

        #expect(try scanPayload(url) == before)
        let m = MetadataService.read(url)
        #expect(m.artist == "Marcos")
        #expect(m.copyright == "(c) CAOBA")
        #expect(m.description == "Nueva")
        #expect(m.dateTimeOriginal == "2024:05:31 14:22:10")
        #expect(m.iso == 400) // no se ha perdido
        #expect(m.model == "NIKON Z 6")
        #expect(abs((m.gps?.latitude ?? 0) - 42.8805) < 0.0001)
        #expect(abs((m.gps?.longitude ?? 0) + 8.5456) < 0.0001)
    }

    @Test("Cadena vacía borra el campo; nil lo deja igual")
    func clearFields() throws {
        let folder = try TestImages.makeTempFolder()
        let url = try photoWithMetadata(in: folder)
        try MetadataService.write(MetadataEdit(artist: "", gps: .some(nil)), to: url)
        let m = MetadataService.read(url)
        #expect(m.artist == nil)
        #expect(m.gps == nil)
        #expect(m.copyright == "CopyBase")
        #expect(m.dateTimeOriginal == "2020:01:01 10:00:00")
    }

    @Test("Strip deja solo lo que se pide")
    func strip() throws {
        let folder = try TestImages.makeTempFolder()
        let url = try photoWithMetadata(in: folder)
        let before = try scanPayload(url)
        try MetadataService.write(MetadataEdit(artist: "Solo yo"), to: url, stripOthers: true)
        let m = MetadataService.read(url)
        #expect(m.artist == "Solo yo")
        #expect(m.model == nil)
        #expect(m.iso == nil)
        #expect(m.gps == nil)
        #expect(try scanPayload(url) == before)
    }

    @Test("Escribir en una foto sin tags previos se lee de vuelta (vía XMP)")
    func writeOnBarePhoto() throws {
        let folder = try TestImages.makeTempFolder()
        let url = try TestImages.makePhoto(in: folder, name: "bare.jpg")
        try MetadataService.write(MetadataEdit(artist: "Nuevo", copyright: "(c)", description: "D", dateTimeOriginal: "2022:02:02 02:02:02", gps: .some(GPSCoordinate(latitude: -1.5, longitude: 2.25))), to: url)
        let m = MetadataService.read(url)
        #expect(m.artist == "Nuevo" && m.copyright == "(c)" && m.description == "D")
        #expect(m.dateTimeOriginal == "2022:02:02 02:02:02")
        #expect(abs((m.gps?.latitude ?? 0) + 1.5) < 0.0001 && abs((m.gps?.longitude ?? 0) - 2.25) < 0.0001)
    }

    @Test("Lote con progreso y cambios por fichero")
    func batch() async throws {
        let folder = try TestImages.makeTempFolder()
        let a = try TestImages.makePhoto(in: folder, name: "a.jpg")
        let b = try TestImages.makePhoto(in: folder, name: "b.jpg")
        let summary = try await MetadataService.writePerFile([(a, MetadataEdit(artist: "A")), (b, MetadataEdit(artist: "B")), (b, MetadataEdit())])
        #expect(summary.processed == 2 && summary.skipped == 1)
        #expect(MetadataService.read(a).artist == "A")
        #expect(MetadataService.read(b).artist == "B")
    }

    @Test("Conversión de formatos XMP")
    func formats() {
        #expect(MetadataService.xmpDate(fromExif: "2024:05:31 14:22:10") == "2024-05-31T14:22:10")
        #expect(MetadataService.xmpCoordinate(42.8805, positive: "N", negative: "S") == "42,52.8300N")
        #expect(MetadataService.xmpCoordinate(-8.5456, positive: "E", negative: "W") == "8,32.7360W")
        #expect(MetadataService.exifDate(fromXMP: "2024-05-31T14:22:10+02:00") == "2024:05:31 14:22:10")
        #expect(abs((MetadataService.parseXMPCoordinate("8,32.7360W") ?? 0) + 8.5456) < 0.0001)
        #expect(abs((MetadataService.parseXMPCoordinate("42,52,49.8N") ?? 0) - 42.8805) < 0.0001)
        #expect(MetadataService.parseXMPCoordinate("basura") == nil)
    }
}
