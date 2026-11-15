import Testing
import Foundation
@testable import CaobaCore

@Suite("Sesiones del estudio")
struct SessionLayoutTests {
    private let fm = FileManager.default
    private var calendar: Calendar {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "Europe/Madrid")!
        return c
    }

    private func day(_ y: Int, _ m: Int, _ d: Int) -> Date {
        calendar.date(from: DateComponents(year: y, month: m, day: d))!
    }

    private func layout(root: URL? = nil) -> SessionLayout {
        var layout = SessionLayout()
        layout.rootPath = root?.path
        return layout
    }

    // MARK: Nombres

    @Test("Escribe y reconoce el nombre de la sesión en cada formato y posición")
    func names() {
        var layout = layout()
        #expect(layout.folderName(date: day(2026, 11, 15), name: " ALEX y SOFIA ", calendar: calendar) == "2026-11-15 ALEX y SOFIA")
        let parsed = layout.parse(folderName: "2026-11-15 ALEX y SOFIA", calendar: calendar)
        #expect(parsed?.name == "ALEX y SOFIA")
        #expect(parsed?.date == day(2026, 11, 15))

        layout.dateFormat = .dayFirst
        layout.datePosition = .afterName
        #expect(layout.folderName(date: day(2026, 1, 5), name: "Boda: Ana/Luis", calendar: calendar) == "Boda- Ana-Luis 05-01-2026")
        #expect(layout.parse(folderName: "Comunión Pablo 05-01-2026", calendar: calendar)?.name == "Comunión Pablo")

        layout.dateFormat = .compact
        layout.datePosition = .beforeName
        #expect(layout.parse(folderName: "20261115 Navidad", calendar: calendar)?.date == day(2026, 11, 15))
    }

    @Test("Los 16 formatos de fecha escriben y reconocen la misma fecha, con el año corto en 20xx")
    func allFormats() {
        var layout = layout()
        let date = day(2069, 3, 7)
        for format in SessionDateFormat.allCases {
            layout.dateFormat = format
            let name = layout.folderName(date: date, name: "Sesión", calendar: calendar)
            #expect(layout.parse(folderName: name, calendar: calendar)?.date == date, "\(format.rawValue): \(name)")
        }
        #expect(SessionDateFormat.allCases.count == 16)
        layout.dateFormat = .dayFirstShortUnderscore
        #expect(layout.folderName(date: date, name: "Sesión", calendar: calendar) == "07_03_69 Sesión")
        layout.dateFormat = .shortCompact
        #expect(layout.parse(folderName: "691307 Mes imposible", calendar: calendar) == nil)
    }

    @Test("No confunde con sesiones las carpetas que no siguen el formato")
    func notSessions() {
        let layout = layout()
        for name in ["2026", "RAW", "2026-11-15", "2026-11-15 ", "2026-11-15_ALEX", "2026-02-31 Imposible", "Fotos 2026-11-15", "26-11-15 Corta"] {
            #expect(layout.parse(folderName: name, calendar: calendar) == nil, "\(name)")
        }
    }

    // MARK: Carpetas

    @Test("Crea la sesión con sus subcarpetas, en su año, sin fallar si ya existe")
    func create() throws {
        let root = try TestImages.makeTempFolder()
        var layout = layout(root: root)
        let session = try layout.createSession(date: day(2026, 11, 15), name: "ALEX y SOFIA", calendar: calendar)
        #expect(session.folder.path == root.appendingPathComponent("2026/2026-11-15 ALEX y SOFIA").path)
        for sub in ["RAW", "JPG", "Lightroom"] {
            #expect(fm.fileExists(atPath: session.folder.appendingPathComponent(sub).path))
        }
        // Repetir no falla y añade solo lo nuevo.
        try fm.createDirectory(at: layout.finals(of: session).appendingPathComponent("dentro"), withIntermediateDirectories: true)
        layout.subfolders.append("Vídeo")
        try layout.createSession(date: day(2026, 11, 15), name: "ALEX y SOFIA", calendar: calendar)
        #expect(fm.fileExists(atPath: session.folder.appendingPathComponent("Vídeo").path))
        #expect(fm.fileExists(atPath: layout.finals(of: session).appendingPathComponent("dentro").path))

        layout.folderPerYear = false
        let flat = try layout.createSession(date: day(2025, 3, 1), name: "Marta", calendar: calendar)
        #expect(flat.folder.deletingLastPathComponent().path == root.path)
        #expect(throws: (any Error).self) { try layout.createSession(date: day(2025, 3, 1), name: "  ", calendar: calendar) }
    }

    @Test("Lista las sesiones de los años y de la raíz, de la más reciente a la más antigua")
    func list() throws {
        let root = try TestImages.makeTempFolder()
        let layout = layout(root: root)
        for path in ["2025/2025-12-24 Navidad Pérez", "2026/2026-11-15 ALEX y SOFIA", "2026/2026-11-15 Boda Ana",
                     "2026/Varios", "2024-06-01 Suelta", "Plantillas"] {
            try fm.createDirectory(at: root.appendingPathComponent(path), withIntermediateDirectories: true)
        }
        fm.createFile(atPath: root.appendingPathComponent("2026/2026-10-01 Fichero.txt").path, contents: Data())
        let names = layout.sessions(calendar: calendar).map(\.title)
        #expect(names == ["2026-11-15 ALEX y SOFIA", "2026-11-15 Boda Ana", "2025-12-24 Navidad Pérez", "2024-06-01 Suelta"])
        #expect(SessionLayout().sessions(calendar: calendar).isEmpty) // sin raíz no hay lista
    }

    @Test("Encuentra la sesión que contiene una carpeta")
    func containing() {
        let layout = layout()
        let jpg = URL(fileURLWithPath: "/Volumes/Fotos/2026/2026-11-15 ALEX y SOFIA/JPG/Selección")
        #expect(layout.session(containing: jpg, calendar: calendar)?.name == "ALEX y SOFIA")
        #expect(layout.session(containing: URL(fileURLWithPath: "/Users/estudio/Descargas"), calendar: calendar) == nil)
    }

    @Test("Nombre corto para «Recientes»: con la sesión delante, o con la carpeta de encima")
    func displayName() {
        let layout = layout()
        func name(_ path: String) -> String { layout.displayName(of: URL(fileURLWithPath: path), calendar: calendar) }
        #expect(name("/Fotos/2026/2026-11-15 Nombre de la sesión/JPG") == "Nombre de la sesión › JPG")
        #expect(name("/Fotos/2026/2026-11-15 Nombre de la sesión/JPG/Selección") == "Nombre de la sesión › JPG › Selección")
        #expect(name("/Fotos/2026/2026-11-15 Nombre de la sesión") == "Nombre de la sesión")
        #expect(name("/Users/estudio/Fotos boda/BOOK") == "Fotos boda › BOOK")
        #expect(name("/Volumes") == "Volumes")
    }

    // MARK: Destinos

    @Test("Rellena el destino de cada módulo y no pisa un fichero que ya existe")
    func outputs() throws {
        let root = try TestImages.makeTempFolder()
        var layout = layout(root: root)
        let session = try layout.createSession(date: day(2026, 11, 15), name: "ALEX y SOFIA", calendar: calendar)
        #expect(layout.output(.processor, in: session, calendar: calendar).lastPathComponent == "JPG web")
        let video = layout.output(.slideshow, in: session, fileExtension: "mp4", calendar: calendar)
        #expect(video.lastPathComponent == "2026-11-15 ALEX y SOFIA - Slideshow.mp4")
        fm.createFile(atPath: video.path, contents: Data())
        #expect(layout.output(.slideshow, in: session, fileExtension: "mp4", calendar: calendar).lastPathComponent == "2026-11-15 ALEX y SOFIA - Slideshow 2.mp4")

        layout.outputs[.collage] = "{sesion} / collages"
        #expect(layout.output(.collage, in: session, calendar: calendar).lastPathComponent == "ALEX y SOFIA - collages")
        layout.outputs[.collage] = "   "
        #expect(layout.output(.collage, in: session, calendar: calendar).lastPathComponent == "Collages")
    }

    @Test("Lo guardado se lee aunque le falten datos de versiones anteriores")
    func codable() throws {
        var layout = SessionLayout()
        layout.rootPath = "/Fotos"
        layout.outputs[.watermark] = "Con marca"
        let data = try JSONEncoder().encode(layout)
        #expect(try JSONDecoder().decode(SessionLayout.self, from: data) == layout)

        let old = Data(#"{"rootPath":"/Fotos","outputs":{"processor":"Web","desconocido":"x"}}"#.utf8)
        let read = try JSONDecoder().decode(SessionLayout.self, from: old)
        #expect(read.rootPath == "/Fotos")
        #expect(read.outputs[.processor] == "Web")
        #expect(read.outputs[.collage] == "Collages")
        #expect(read.subfolders == ["RAW", "JPG", "Lightroom"])
    }
}
