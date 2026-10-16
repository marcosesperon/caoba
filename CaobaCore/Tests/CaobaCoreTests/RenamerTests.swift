import Testing
import Foundation
@testable import CaobaCore

@Suite("Renamer")
struct RenamerTests {

    private func urls(_ names: [String], in folder: URL = URL(fileURLWithPath: "/tmp/x")) -> [URL] {
        names.map { folder.appendingPathComponent($0) }
    }

    @Test("Patrón con {nombre}, {n} y fecha; los tokens se sustituyen todas las veces")
    func pattern() {
        let info = RenameSourceInfo(url: URL(fileURLWithPath: "/tmp/DSC_MM01.jpg"),
                                    date: ExifDate.parse("2024:05:31 14:22:10"), camera: "Nikon Z6",
                                    lens: "50mm", size: PixelSize(width: 600, height: 400))
        let out = Renamer.expand(pattern: "YYYY-MM-DD_{n}_{n}_{nombre}_{camara}_{orientacion}_{ancho}x{alto}", info: info, sequence: "007")
        // El "MM" del nombre original no se toca porque la fecha se sustituye antes.
        #expect(out == "2024-05-31_007_007_DSC_MM01_Nikon Z6_H_600x400")
    }

    @Test("Sin fecha los tokens quedan a cero")
    func patternNoDate() {
        let info = RenameSourceInfo(url: URL(fileURLWithPath: "/tmp/a.jpg"))
        #expect(Renamer.expand(pattern: "YYYYMMDD_hhmmss", info: info, sequence: "1") == "00000000_000000")
    }

    @Test("Plan de patrón: contador automático, extensión en minúsculas y colisiones")
    func patternPlan() {
        let files = urls(["b.JPG", "a.jpg", "c.jpg"])
        let plan = Renamer.patternPlan(files: files, options: PatternRenameOptions(pattern: "foto_{n}"))
        #expect(plan.map(\.newName) == ["foto_01.jpg", "foto_02.jpg", "foto_03.jpg"])

        let dup = Renamer.patternPlan(files: files, options: PatternRenameOptions(pattern: "igual"))
        #expect(dup.map(\.newName) == ["igual.jpg", "igual_2.jpg", "igual_3.jpg"])

        let fixed = Renamer.patternPlan(files: files, options: PatternRenameOptions(pattern: "{n}", sequenceDigits: 4, sequenceStart: 10))
        #expect(fixed.map(\.newName) == ["0010.jpg", "0011.jpg", "0012.jpg"])
    }

    @Test("Mayúsculas y saneado")
    func caseAndSanitize() {
        #expect(Renamer.applyCase("hola mundo", .capitalize) == "Hola Mundo")
        #expect(Renamer.applyCase("Hola", .uppercase) == "HOLA")
        let s = Renamer.sanitize("Fotó de  boda (2)", SanitizeOptions(removeAccents: true, removeSpaces: true, removeSpecialCharacters: true))
        #expect(s == "Foto_de_boda_2")
    }

    @Test("Autofix detecta la secuencia y rellena con ceros")
    func autofix() {
        let plan = Renamer.autofixPlan(files: urls(["Foto-1.jpg", "Foto-02.jpg", "Foto-100.jpg"]))
        #expect(plan.map(\.newName) == ["Foto-001.jpg", "Foto-002.jpg"])
        #expect(Renamer.autofixPlan(files: urls(["a-1.jpg", "b-2.jpg"])).isEmpty) // prefijos distintos
        #expect(Renamer.autofixPlan(files: urls(["a-01.jpg", "a-02.jpg"])).isEmpty) // ya está bien
        #expect(Renamer.autofixPlan(files: urls(["sin numero.jpg"])).isEmpty)
    }

    @Test("Buscar/reemplazar y prefijo/sufijo")
    func searchReplaceAndAffixes() {
        let files = urls(["IMG_001.jpg", "IMG_002.jpg", "otro.jpg"])
        let sr = Renamer.searchReplacePlan(files: files, search: "IMG_", replace: "boda-")
        #expect(sr.map(\.newName) == ["boda-001.jpg", "boda-002.jpg"])
        let ps = Renamer.prefixSuffixPlan(files: files, prefix: "2024_", suffix: "_web")
        #expect(ps.map(\.newName) == ["2024_IMG_001_web.jpg", "2024_IMG_002_web.jpg", "2024_otro_web.jpg"])
        #expect(Renamer.searchReplacePlan(files: files, search: "", replace: "x").isEmpty)
    }

    @Test("Ejecutar renombrado en sitio con nombres que se cruzan")
    func executeSwap() async throws {
        let folder = try TestImages.makeTempFolder()
        let a = try TestImages.makePhoto(in: folder, name: "a.jpg", width: 10, height: 10)
        let b = try TestImages.makePhoto(in: folder, name: "b.jpg", width: 20, height: 10)
        // a → b y b → a: sin dos pasadas se pisarían.
        let plan = [RenameEntry(from: a, newName: "b.jpg"), RenameEntry(from: b, newName: "a.jpg")]
        let summary = try await Renamer().execute(plan: plan, saveMode: .overwrite)
        #expect(summary.processed == 2)
        #expect(ImageIOHelpers.displaySize(of: folder.appendingPathComponent("b.jpg"))?.width == 10)
        #expect(ImageIOHelpers.displaySize(of: folder.appendingPathComponent("a.jpg"))?.width == 20)
        let leftovers = try FileManager.default.contentsOfDirectory(atPath: folder.path).filter { $0.hasPrefix("_caoba_") }
        #expect(leftovers.isEmpty)
    }

    @Test("Ejecutar como copias en otra carpeta")
    func executeCopy() async throws {
        let folder = try TestImages.makeTempFolder()
        let out = folder.appendingPathComponent("out")
        let a = try TestImages.makePhoto(in: folder, name: "a.jpg")
        let plan = Renamer.prefixSuffixPlan(files: [a], prefix: "x_", suffix: "")
        _ = try await Renamer().execute(plan: plan, saveMode: .newCopy(outputFolder: out))
        #expect(FileManager.default.fileExists(atPath: out.appendingPathComponent("x_a.jpg").path))
        #expect(FileManager.default.fileExists(atPath: a.path))
    }

    @Test("Plan con datos EXIF reales del fichero")
    func planReadsExif() throws {
        let folder = try TestImages.makeTempFolder()
        _ = try TestImages.makePhoto(in: folder, name: "z.jpg", width: 300, height: 400, date: "2023:07:08 09:10:11", make: "Canon", model: "Canon EOS R6", lens: "RF 50")
        _ = try TestImages.makePhoto(in: folder, name: "a.jpg", width: 400, height: 300, date: "2021:01:01 00:00:00")
        let files = try FolderScanner().listImageURLs(in: folder)
        let plan = Renamer.patternPlan(files: files, options: PatternRenameOptions(pattern: "YYYYMMDD_{camara}_{orientacion}_{n}", sortBy: .date))
        #expect(plan.map(\.newName) == ["20210101_unknown_H_01.jpg", "20230708_Canon EOS R6_V_02.jpg"])
    }

    @Test("CameraName no repite la marca")
    func cameraName() {
        #expect(CameraName.combine(make: "Canon", model: "Canon EOS R6") == "Canon EOS R6")
        #expect(CameraName.combine(make: "SONY", model: "ILCE-7M4") == "SONY ILCE-7M4")
        #expect(CameraName.combine(make: nil, model: nil) == nil)
    }
}

@Suite("RenameHistory")
struct RenameHistoryTests {
    @Test("Renombrar en sitio deja registro y se puede deshacer, incluso dos veces")
    func undo() async throws {
        let folder = try TestImages.makeTempFolder()
        let a = try TestImages.makePhoto(in: folder, name: "IMG_1.jpg", width: 10, height: 10)
        let b = try TestImages.makePhoto(in: folder, name: "IMG_2.jpg", width: 20, height: 10)
        // Primera operación: prefijo.
        let plan1 = Renamer.prefixSuffixPlan(files: [a, b], prefix: "boda_", suffix: "")
        _ = try await Renamer().execute(plan: plan1, saveMode: .overwrite, modeLabel: "prefijo")
        #expect(RenameHistory.load(from: folder).count == 1)
        #expect(FileManager.default.fileExists(atPath: folder.appendingPathComponent("boda_IMG_1.jpg").path))
        // Segunda: intercambio (dos pasadas).
        let x = folder.appendingPathComponent("boda_IMG_1.jpg"), y = folder.appendingPathComponent("boda_IMG_2.jpg")
        _ = try await Renamer().execute(plan: [RenameEntry(from: x, newName: "boda_IMG_2.jpg"), RenameEntry(from: y, newName: "boda_IMG_1.jpg")], saveMode: .overwrite)
        #expect(RenameHistory.load(from: folder).count == 2)
        #expect(ImageIOHelpers.displaySize(of: x)?.width == 20)

        let undo2 = try await RenameHistory.undoLast(in: folder)
        #expect(undo2.processed == 2 && ImageIOHelpers.displaySize(of: x)?.width == 10)
        #expect(RenameHistory.load(from: folder).count == 1)
        let undo1 = try await RenameHistory.undoLast(in: folder)
        #expect(undo1.processed == 2)
        #expect(FileManager.default.fileExists(atPath: a.path) && FileManager.default.fileExists(atPath: b.path))
        #expect(RenameHistory.load(from: folder).isEmpty)
    }

    @Test("El historial vive en el .caoba y sobrevive a Reiniciar")
    func survivesReset() async throws {
        let folder = try TestImages.makeTempFolder()
        let a = try TestImages.makePhoto(in: folder, name: "a.jpg")
        try CaobaConfig.writeSection("slideshow", value: ["mode": "photos"], in: folder)
        _ = try await Renamer().execute(plan: Renamer.prefixSuffixPlan(files: [a], prefix: "r_", suffix: ""), saveMode: .overwrite)
        let config = CaobaConfig.read(from: folder)!
        #expect(config.sections.keys.sorted() == ["renameHistory", "slideshow"])
        #expect(CaobaConfig.hasSettings(in: folder))
        CaobaConfig.resetSettings(in: folder)
        #expect(!CaobaConfig.hasSettings(in: folder))
        #expect(RenameHistory.load(from: folder).count == 1)
        _ = try await RenameHistory.undoLast(in: folder)
        // Sin historial ni configuración, el fichero desaparece.
        #expect(CaobaConfig.read(from: folder) == nil)
    }

    @Test("Si un fichero ya no está con el nombre nuevo, se avisa y se deshace el resto")
    func partial() async throws {
        let folder = try TestImages.makeTempFolder()
        let a = try TestImages.makePhoto(in: folder, name: "a.jpg")
        let b = try TestImages.makePhoto(in: folder, name: "b.jpg")
        _ = try await Renamer().execute(plan: Renamer.prefixSuffixPlan(files: [a, b], prefix: "x_", suffix: ""), saveMode: .overwrite)
        try FileManager.default.removeItem(at: folder.appendingPathComponent("x_b.jpg"))
        let summary = try await RenameHistory.undoLast(in: folder)
        #expect(summary.processed == 1 && summary.failures.count == 1)
        #expect(FileManager.default.fileExists(atPath: a.path))
    }

    @Test("Las copias nuevas y el escáner no se ven afectados por el registro")
    func copiesAndScanner() async throws {
        let folder = try TestImages.makeTempFolder()
        let a = try TestImages.makePhoto(in: folder, name: "a.jpg")
        _ = try await Renamer().execute(plan: Renamer.prefixSuffixPlan(files: [a], prefix: "c_", suffix: ""), saveMode: .newCopy(outputFolder: nil))
        #expect(RenameHistory.load(from: folder).isEmpty)
        _ = try await Renamer().execute(plan: Renamer.prefixSuffixPlan(files: [a], prefix: "r_", suffix: ""), saveMode: .overwrite)
        let scanned = try FolderScanner().listImageURLs(in: folder).map(\.lastPathComponent)
        #expect(!scanned.contains(CaobaConfig.fileName))
    }
}
