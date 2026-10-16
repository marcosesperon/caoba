import Foundation

/// Valor JSON genérico, para guardar secciones de configuración sin atarlas a
/// un tipo concreto (cada módulo decodifica la suya).
public enum JSONValue: Sendable, Equatable, Codable {
    case string(String)
    case number(Double)
    case bool(Bool)
    case null
    case array([JSONValue])
    case object([String: JSONValue])

    public init(from decoder: Decoder) throws {
        let c = try decoder.singleValueContainer()
        if c.decodeNil() { self = .null }
        else if let b = try? c.decode(Bool.self) { self = .bool(b) }
        else if let n = try? c.decode(Double.self) { self = .number(n) }
        else if let s = try? c.decode(String.self) { self = .string(s) }
        else if let a = try? c.decode([JSONValue].self) { self = .array(a) }
        else if let o = try? c.decode([String: JSONValue].self) { self = .object(o) }
        else { throw DecodingError.dataCorruptedError(in: c, debugDescription: "JSON no reconocido") }
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.singleValueContainer()
        switch self {
        case .string(let s): try c.encode(s)
        case .number(let n): try c.encode(n)
        case .bool(let b): try c.encode(b)
        case .null: try c.encodeNil()
        case .array(let a): try c.encode(a)
        case .object(let o): try c.encode(o)
        }
    }
}

/// Fichero `.caoba` que vive en la carpeta de fotos y guarda la configuración
/// de cada módulo para esa carpeta. Mismo formato que la app antigua
/// (`{ "version": 1, "slideshow": {...} }`) para que los `.caoba` existentes
/// se sigan leyendo.
public struct CaobaConfig: Sendable, Equatable {
    public static let fileName = ".caoba"
    public static let currentVersion = 1
    /// Secciones que no son configuración y sobreviven a "Reiniciar"
    /// (por ejemplo, el historial de renombrados).
    public static let protectedSections: Set<String> = ["renameHistory"]
    /// Todas las lecturas-modificaciones-escrituras pasan por aquí para que dos
    /// módulos (el guardado automático del slideshow y el historial del
    /// renombrador) no se pisen al escribir el mismo fichero.
    private static let lock = NSLock()

    public var version: Int
    public var sections: [String: JSONValue]

    public init(version: Int = CaobaConfig.currentVersion, sections: [String: JSONValue] = [:]) {
        self.version = version
        self.sections = sections
    }

    public static func fileURL(in folder: URL) -> URL {
        folder.appendingPathComponent(fileName)
    }

    /// Lee la configuración de la carpeta. `nil` si no existe o no es válida.
    public static func read(from folder: URL) -> CaobaConfig? {
        let url = fileURL(in: folder)
        guard let data = try? Data(contentsOf: url),
              let root = try? JSONDecoder().decode([String: JSONValue].self, from: data) else { return nil }
        guard case .number(let v)? = root["version"] else { return nil }
        var sections = root
        sections.removeValue(forKey: "version")
        return CaobaConfig(version: Int(v), sections: sections)
    }

    /// Lee una sección decodificándola al tipo del módulo.
    public static func readSection<T: Decodable>(_ name: String, as type: T.Type, from folder: URL) -> T? {
        guard let config = read(from: folder), let value = config.sections[name] else { return nil }
        guard let data = try? JSONEncoder().encode(value) else { return nil }
        return try? JSONDecoder().decode(T.self, from: data)
    }

    /// Escribe (o sustituye) una sección conservando las demás.
    public static func writeSection<T: Encodable>(_ name: String, value: T, in folder: URL) throws {
        lock.lock()
        defer { lock.unlock() }
        var config = read(from: folder) ?? CaobaConfig()
        let data = try JSONEncoder().encode(value)
        config.sections[name] = try JSONDecoder().decode(JSONValue.self, from: data)
        config.version = currentVersion
        try config.save(in: folder)
    }

    /// Quita una sección; si el fichero queda vacío, lo elimina.
    public static func removeSection(_ name: String, in folder: URL) throws {
        lock.lock()
        defer { lock.unlock() }
        guard var config = read(from: folder) else { return }
        config.sections.removeValue(forKey: name)
        if config.sections.isEmpty {
            try? FileManager.default.removeItem(at: fileURL(in: folder))
        } else {
            try config.save(in: folder)
        }
    }

    /// Si la carpeta tiene configuración de verdad (sin contar las secciones protegidas).
    public static func hasSettings(in folder: URL) -> Bool {
        guard let config = read(from: folder) else { return false }
        return config.sections.keys.contains { !protectedSections.contains($0) }
    }

    /// "Reiniciar": borra la configuración pero conserva las secciones protegidas.
    /// Si no queda nada, elimina el fichero.
    public static func resetSettings(in folder: URL) {
        lock.lock()
        defer { lock.unlock() }
        guard var config = read(from: folder) else { return }
        config.sections = config.sections.filter { protectedSections.contains($0.key) }
        if config.sections.isEmpty {
            try? FileManager.default.removeItem(at: fileURL(in: folder))
        } else {
            try? config.save(in: folder)
        }
    }

    public func save(in folder: URL) throws {
        var root = sections
        root["version"] = .number(Double(version))
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(root)
        try data.write(to: Self.fileURL(in: folder), options: .atomic)
    }

    /// Borra el fichero de la carpeta (también las secciones protegidas).
    public static func delete(from folder: URL) {
        lock.lock()
        defer { lock.unlock() }
        try? FileManager.default.removeItem(at: fileURL(in: folder))
    }
}
