import Testing
import Foundation
@testable import CaobaCore

@Suite("ShutterCount")
struct ShutterCountTests {
    @Test("Tabla de vida útil: exacto, parcial, genérico y desconocido")
    func lifeTable() {
        #expect(ShutterLife.expectancy(make: "NIKON CORPORATION", model: "NIKON D850") == (200_000, false))
        #expect(ShutterLife.expectancy(make: "Canon", model: "Canon EOS R6") == (300_000, false))
        #expect(ShutterLife.expectancy(make: "SONY", model: "ILCE-7M4") == (300_000, false))
        #expect(ShutterLife.expectancy(make: "NIKON CORPORATION", model: "NIKON D999") == (150_000, true))
        #expect(ShutterLife.expectancy(make: "FUJIFILM", model: "X-T5").count == nil)
        #expect(ShutterLife.expectancy(make: nil, model: nil).count == nil)
    }

    @Test("Parseo del JSON de exiftool")
    func parse() throws {
        let json = """
        [{"SourceFile":"x.NEF","ShutterCount":48213,"MechanicalShutterCount":40000,"Make":"NIKON CORPORATION","Model":"NIKON Z 6",
          "SerialNumber":"6012345","FirmwareVersion":"Ver.3.60","LensModel":"NIKKOR Z 50mm f/1.8 S","DateTimeOriginal":"2024:05:31 14:22:10",
          "ISO":400,"ExposureTime":0.004,"FNumber":2.8,"FocalLength":50,"ImageWidth":6048,"ImageHeight":4024}]
        """
        let result = try ShutterCountReader.parseExifToolJSON(Data(json.utf8))
        #expect(result.source == .exiftool)
        #expect(result.camera.displayName == "NIKON CORPORATION NIKON Z 6")
        #expect(result.camera.serial == "6012345" && result.camera.firmware == "Ver.3.60")
        #expect(result.shutter.count == 48213 && result.shutter.mechanicalCount == 40000)
        #expect(result.shutter.lifeExpectancy == 200_000 && result.shutter.isEstimate == false)
        #expect(result.shutter.percentUsed == 24.11)
        #expect(result.photo.iso == 400 && result.photo.fNumber == 2.8 && result.photo.width == 6048)
    }

    @Test("Respaldo con ImageIO sobre una foto sin MakerNote")
    func imageIO() throws {
        let folder = try TestImages.makeTempFolder()
        let url = try TestImages.makePhoto(in: folder, name: "c.jpg", width: 300, height: 200, date: "2023:01:02 03:04:05", make: "Canon", model: "Canon EOS R6", lens: "RF 50")
        let result = try ShutterCountReader.readWithImageIO(url)
        #expect(result.source == .imageIO)
        #expect(result.camera.displayName == "Canon EOS R6" && result.camera.lens == "RF 50")
        #expect(result.shutter.count == nil && result.shutter.lifeExpectancy == 300_000)
        #expect(result.photo.width == 300 && result.photo.dateTime == "2023:01:02 03:04:05")
    }

    @Test("exiftool del sistema, si está instalado")
    func systemExifTool() async throws {
        guard let location = ShutterCountReader.locateExifTool(bundleResources: nil) else { return }
        let folder = try TestImages.makeTempFolder()
        let url = try TestImages.makePhoto(in: folder, name: "e.jpg", make: "SONY", model: "ILCE-7M4")
        let result = try await ShutterCountReader.read(url, exifTool: location)
        #expect(result.source == .exiftool)
        #expect(result.camera.model == "ILCE-7M4")
        #expect(result.shutter.lifeExpectancy == 300_000)
    }
}
