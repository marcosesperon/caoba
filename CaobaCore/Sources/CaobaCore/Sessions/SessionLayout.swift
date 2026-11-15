import Foundation

/// Cómo se escribe la fecha en el nombre de la carpeta de una sesión: separador (guion,
/// punto, guion bajo o nada), año delante o día delante, y año con 4 o 2 cifras.
/// El valor guardado es el formato de `DateFormatter`; los cuatro primeros son los de
/// la primera versión y no cambian de nombre para que lo guardado siga valiendo.
public enum SessionDateFormat: String, Sendable, Codable, CaseIterable {
    // Año delante
    case isoDash = "yyyy-MM-dd"
    case isoDot = "yyyy.MM.dd"
    case isoUnderscore = "yyyy_MM_dd"
    case compact = "yyyyMMdd"
    case shortDash = "yy-MM-dd"
    case shortDot = "yy.MM.dd"
    case shortUnderscore = "yy_MM_dd"
    case shortCompact = "yyMMdd"
    // Día delante
    case dayFirst = "dd-MM-yyyy"
    case dayFirstDot = "dd.MM.yyyy"
    case dayFirstUnderscore = "dd_MM_yyyy"
    case dayFirstCompact = "ddMMyyyy"
    case dayFirstShortDash = "dd-MM-yy"
    case dayFirstShortDot = "dd.MM.yy"
    case dayFirstShortUnderscore = "dd_MM_yy"
    case dayFirstShortCompact = "ddMMyy"

    /// Todas tienen ancho fijo: así se sabe dónde acaba la fecha y empieza el nombre.
    var length: Int { rawValue.count }

    /// Si el año va delante (para agrupar el desplegable de Ajustes).
    public var yearFirst: Bool { rawValue.hasPrefix("y") }
}

/// Si la fecha va delante o detrás del nombre: `2026-11-15 Nombre de la sesión` o `Nombre de la sesión 2026-11-15`.
public enum SessionDatePosition: String, Sendable, Codable, CaseIterable {
    case beforeName, afterName
}

/// Módulos que guardan su resultado dentro de la sesión, cada uno con su nombre en Ajustes.
public enum SessionOutput: String, Sendable, Codable, CaseIterable {
    case processor, watermark, collage, slideshow, contactSheet
}

/// Una sesión de fotos: una carpeta con fecha y nombre, p. ej. `2026/2026-11-15 Nombre de la sesión`.
public struct StudioSession: Sendable, Equatable, Hashable, Identifiable {
    public var folder: URL
    public var date: Date
    public var name: String

    public init(folder: URL, date: Date, name: String) {
        self.folder = folder
        self.date = date
        self.name = name
    }

    public var id: String { folder.standardizedFileURL.path }
    /// El nombre de la carpeta tal cual («2026-11-15 Nombre de la sesión»).
    public var title: String { folder.lastPathComponent }
}

/// La estructura de carpetas del estudio, tal como se configura en Ajustes.
///
/// Por defecto la de CAOBA: una carpeta por año y dentro una por sesión
/// (`2026/2026-11-15 Nombre de la sesión`) con `RAW`, `JPG` y `Lightroom`.
public struct SessionLayout: Sendable, Equatable, Codable {
    /// Carpeta donde están los años (o las sesiones, si no se separan por año).
    public var rootPath: String?
    public var folderPerYear = true
    public var dateFormat: SessionDateFormat = .isoDash
    public var datePosition: SessionDatePosition = .beforeName
    /// Subcarpetas que se crean en cada sesión nueva.
    public var subfolders = ["RAW", "JPG", "Lightroom"]
    /// Dónde se descargan las tarjetas.
    public var downloadsFolder = "RAW"
    /// Dónde están las fotos finales: el origen de los módulos.
    public var finalsFolder = "JPG"
    /// Nombre de lo que guarda cada módulo dentro de la sesión. Admite `{sesion}` y `{fecha_sesion}`.
    public var outputs: [SessionOutput: String] = Self.defaultOutputs

    public static let defaultOutputs: [SessionOutput: String] = [
        .processor: "JPG web",
        .watermark: "JPG marca",
        .collage: "Collages",
        .slideshow: "{fecha_sesion} {sesion} - Slideshow",
        .contactSheet: "{fecha_sesion} {sesion} - Contact Sheet",
    ]

    public init() {}

    /// Lee lo guardado siendo tolerante: lo que falte (de versiones anteriores) se queda por defecto.
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let base = SessionLayout()
        rootPath = try c.decodeIfPresent(String.self, forKey: .rootPath)
        folderPerYear = try c.decodeIfPresent(Bool.self, forKey: .folderPerYear) ?? base.folderPerYear
        dateFormat = (try? c.decodeIfPresent(SessionDateFormat.self, forKey: .dateFormat)) ?? base.dateFormat
        datePosition = (try? c.decodeIfPresent(SessionDatePosition.self, forKey: .datePosition)) ?? base.datePosition
        subfolders = try c.decodeIfPresent([String].self, forKey: .subfolders) ?? base.subfolders
        downloadsFolder = try c.decodeIfPresent(String.self, forKey: .downloadsFolder) ?? base.downloadsFolder
        finalsFolder = try c.decodeIfPresent(String.self, forKey: .finalsFolder) ?? base.finalsFolder
        // Los nombres se guardan con la clave en texto, para que un módulo nuevo no rompa lo guardado.
        let saved = try c.decodeIfPresent([String: String].self, forKey: .outputs) ?? [:]
        outputs = base.outputs.merging(saved.compactMapKeys(SessionOutput.init(rawValue:))) { _, new in new }
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encodeIfPresent(rootPath, forKey: .rootPath)
        try c.encode(folderPerYear, forKey: .folderPerYear)
        try c.encode(dateFormat, forKey: .dateFormat)
        try c.encode(datePosition, forKey: .datePosition)
        try c.encode(subfolders, forKey: .subfolders)
        try c.encode(downloadsFolder, forKey: .downloadsFolder)
        try c.encode(finalsFolder, forKey: .finalsFolder)
        try c.encode(Dictionary(uniqueKeysWithValues: outputs.map { ($0.key.rawValue, $0.value) }), forKey: .outputs)
    }

    private enum CodingKeys: String, CodingKey {
        case rootPath, folderPerYear, dateFormat, datePosition, subfolders, downloadsFolder, finalsFolder, outputs
    }

    public var root: URL? { rootPath.map { URL(fileURLWithPath: $0, isDirectory: true) } }

    // MARK: - Nombres

    private func formatter(_ calendar: Calendar) -> DateFormatter {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.calendar = calendar
        f.timeZone = calendar.timeZone
        f.dateFormat = dateFormat.rawValue
        // Con el año en 2 cifras, siempre 20xx (si no, «69» sería 1969).
        f.twoDigitStartDate = calendar.date(from: DateComponents(year: 2000, month: 1, day: 1))
        return f
    }

    /// La fecha escrita como en las carpetas («2026-11-15»).
    public func dateText(_ date: Date, calendar: Calendar = .current) -> String {
        formatter(calendar).string(from: date)
    }

    /// Nombre de la carpeta de una sesión: fecha y nombre en el orden elegido.
    public func folderName(date: Date, name: String, calendar: Calendar = .current) -> String {
        let clean = Self.cleanName(name)
        let day = dateText(date, calendar: calendar)
        return datePosition == .beforeName ? "\(day) \(clean)" : "\(clean) \(day)"
    }

    /// Fecha y nombre de una carpeta de sesión, o `nil` si el nombre no sigue el formato.
    public func parse(folderName: String, calendar: Calendar = .current) -> (date: Date, name: String)? {
        let length = dateFormat.length
        guard folderName.count > length + 1 else { return nil }
        let datePart: Substring
        let separator: Character
        let namePart: Substring
        switch datePosition {
        case .beforeName:
            datePart = folderName.prefix(length)
            separator = folderName[folderName.index(folderName.startIndex, offsetBy: length)]
            namePart = folderName.dropFirst(length + 1)
        case .afterName:
            datePart = folderName.suffix(length)
            separator = folderName[folderName.index(folderName.endIndex, offsetBy: -length - 1)]
            namePart = folderName.dropLast(length + 1)
        }
        let name = namePart.trimmingCharacters(in: .whitespaces)
        let f = formatter(calendar)
        // Se vuelve a escribir la fecha para descartar las que el formateador «arregla» (31-02…).
        guard separator == " ", !name.isEmpty, let date = f.date(from: String(datePart)),
              f.string(from: date) == datePart else { return nil }
        return (date, name)
    }

    /// Quita lo que no puede ir en un nombre de carpeta y los espacios de sobra.
    static func cleanName(_ name: String) -> String {
        name.replacingOccurrences(of: "/", with: "-").replacingOccurrences(of: ":", with: "-")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    // MARK: - Carpetas

    /// Dónde va (o está) la carpeta de una sesión; `nil` sin carpeta raíz.
    public func sessionFolder(date: Date, name: String, calendar: Calendar = .current) -> URL? {
        guard var folder = root else { return nil }
        if folderPerYear { folder.appendPathComponent(String(calendar.component(.year, from: date)), isDirectory: true) }
        return folder.appendingPathComponent(folderName(date: date, name: name, calendar: calendar), isDirectory: true)
    }

    /// Las sesiones de la carpeta raíz, de la más reciente a la más antigua. Mira en la raíz
    /// y en las carpetas de año (`2026`), así encuentra las dos formas de organizarlas.
    public func sessions(calendar: Calendar = .current) -> [StudioSession] {
        guard let root else { return [] }
        var found: [StudioSession] = []
        for folder in Self.subdirectories(of: root) {
            if let session = session(at: folder, calendar: calendar) {
                found.append(session)
            } else if folder.lastPathComponent.count == 4, Int(folder.lastPathComponent) != nil {
                found += Self.subdirectories(of: folder).compactMap { session(at: $0, calendar: calendar) }
            }
        }
        return found.sorted { ($0.date, $1.name) > ($1.date, $0.name) }
    }

    /// Crea la carpeta de la sesión y sus subcarpetas. Si ya existía, solo añade las que falten.
    @discardableResult
    public func createSession(date: Date, name: String, calendar: Calendar = .current) throws -> StudioSession {
        let clean = Self.cleanName(name)
        guard !clean.isEmpty, let folder = sessionFolder(date: date, name: clean, calendar: calendar) else {
            throw CocoaError(.fileWriteInvalidFileName)
        }
        let fm = FileManager.default
        try fm.createDirectory(at: folder, withIntermediateDirectories: true)
        for sub in subfolders.map(Self.cleanName) where !sub.isEmpty {
            try fm.createDirectory(at: folder.appendingPathComponent(sub, isDirectory: true), withIntermediateDirectories: true)
        }
        return StudioSession(folder: folder, date: calendar.startOfDay(for: date), name: clean)
    }

    /// La sesión que contiene `url` (o que es `url`), mirando hacia arriba. Vale para cualquier
    /// carpeta con nombre de sesión, esté o no en la raíz configurada.
    public func session(containing url: URL, calendar: Calendar = .current) -> StudioSession? {
        var current = url.standardizedFileURL
        while current.pathComponents.count > 1 {
            if let session = session(at: current, calendar: calendar) { return session }
            current = current.deletingLastPathComponent()
        }
        return nil
    }

    /// Nombre corto de una carpeta para listas como «Recientes», donde muchas se llaman igual
    /// (`JPG`): dentro de una sesión, «nombre de la sesión › ruta dentro de ella»; fuera,
    /// «carpeta de encima › carpeta».
    public func displayName(of url: URL, calendar: Calendar = .current) -> String {
        let folder = url.standardizedFileURL
        if let session = session(containing: folder, calendar: calendar) {
            let inside = Array(folder.pathComponents.dropFirst(session.folder.pathComponents.count))
            return ([session.name] + inside).joined(separator: " › ")
        }
        let parent = folder.deletingLastPathComponent()
        guard parent.pathComponents.count > 1 else { return folder.lastPathComponent }
        return parent.lastPathComponent + " › " + folder.lastPathComponent
    }

    private func session(at folder: URL, calendar: Calendar) -> StudioSession? {
        parse(folderName: folder.lastPathComponent, calendar: calendar).map { StudioSession(folder: folder, date: $0.date, name: $0.name) }
    }

    private static func subdirectories(of folder: URL) -> [URL] {
        let items = (try? FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: [.isDirectoryKey], options: [.skipsHiddenFiles])) ?? []
        return items.filter { (try? $0.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true }
    }

    // MARK: - Dentro de una sesión

    public func downloads(of session: StudioSession) -> URL {
        session.folder.appendingPathComponent(downloadsFolder, isDirectory: true)
    }

    public func finals(of session: StudioSession) -> URL {
        session.folder.appendingPathComponent(finalsFolder, isDirectory: true)
    }

    /// Rellena `{sesion}` y `{fecha_sesion}` con los datos de la sesión.
    public func fill(_ template: String, with session: StudioSession, calendar: Calendar = .current) -> String {
        template.replacingOccurrences(of: "{sesion}", with: session.name)
            .replacingOccurrences(of: "{fecha_sesion}", with: dateText(session.date, calendar: calendar))
    }

    /// Dónde guarda un módulo dentro de la sesión. Con `fileExtension` es un fichero y,
    /// si ya existe, se le pone « 2», « 3»… para no pisar uno anterior sin preguntar.
    public func output(_ output: SessionOutput, in session: StudioSession, fileExtension: String? = nil,
                       calendar: Calendar = .current) -> URL {
        let template = outputs[output] ?? Self.defaultOutputs[output] ?? output.rawValue
        var name = Self.cleanName(fill(template, with: session, calendar: calendar))
        if name.isEmpty { name = Self.cleanName(fill(Self.defaultOutputs[output] ?? output.rawValue, with: session, calendar: calendar)) }
        guard let fileExtension else { return session.folder.appendingPathComponent(name, isDirectory: true) }
        var candidate = session.folder.appendingPathComponent(name).appendingPathExtension(fileExtension)
        var number = 2
        while FileManager.default.fileExists(atPath: candidate.path) {
            candidate = session.folder.appendingPathComponent("\(name) \(number)").appendingPathExtension(fileExtension)
            number += 1
        }
        return candidate
    }
}

private extension Dictionary {
    func compactMapKeys<T: Hashable>(_ transform: (Key) -> T?) -> [T: Value] {
        var result: [T: Value] = [:]
        for (key, value) in self { if let newKey = transform(key) { result[newKey] = value } }
        return result
    }
}
