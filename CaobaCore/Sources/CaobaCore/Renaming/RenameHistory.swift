import Foundation

/// Historial de renombrados en sitio de una carpeta, para poder deshacerlos.
/// Vive en la sección `renameHistory` del `.caoba` de la carpeta, que es una
/// sección protegida: "Reiniciar" la configuración no la borra.
public struct RenameOperation: Codable, Sendable, Equatable, Identifiable {
    public struct Entry: Codable, Sendable, Equatable {
        public var from: String
        public var to: String
        public init(from: String, to: String) { self.from = from; self.to = to }
    }

    public var id: UUID
    public var date: Date
    /// Texto libre con el modo usado (patrón, autofix...), solo informativo.
    public var mode: String
    public var entries: [Entry]

    public init(id: UUID = UUID(), date: Date = Date(), mode: String, entries: [Entry]) {
        self.id = id
        self.date = date
        self.mode = mode
        self.entries = entries
    }

    private enum CodingKeys: String, CodingKey { case id, date, mode, entries }

    // La fecha va como texto ISO 8601 para que el .caoba siga siendo legible.
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        let raw = try c.decode(String.self, forKey: .date)
        date = ISO8601DateFormatter().date(from: raw) ?? Date()
        mode = try c.decodeIfPresent(String.self, forKey: .mode) ?? ""
        entries = try c.decode([Entry].self, forKey: .entries)
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(id, forKey: .id)
        try c.encode(ISO8601DateFormatter().string(from: date), forKey: .date)
        try c.encode(mode, forKey: .mode)
        try c.encode(entries, forKey: .entries)
    }
}

public enum RenameHistory {
    public static let sectionName = "renameHistory"

    /// Operaciones registradas, de la más antigua a la más reciente.
    public static func load(from folder: URL) -> [RenameOperation] {
        CaobaConfig.readSection(sectionName, as: [RenameOperation].self, from: folder) ?? []
    }

    static func save(_ operations: [RenameOperation], in folder: URL) throws {
        if operations.isEmpty {
            try CaobaConfig.removeSection(sectionName, in: folder)
        } else {
            try CaobaConfig.writeSection(sectionName, value: operations, in: folder)
        }
    }

    /// Añade una operación al final del historial.
    public static func record(_ operation: RenameOperation, in folder: URL) throws {
        guard !operation.entries.isEmpty else { return }
        var operations = load(from: folder)
        operations.append(operation)
        try save(operations, in: folder)
    }

    /// Última operación pendiente de deshacer.
    public static func last(in folder: URL) -> RenameOperation? { load(from: folder).last }

    /// Deshace la última operación: devuelve a cada fichero su nombre anterior.
    /// Los ficheros que ya no estén con el nombre nuevo se saltan y se informan.
    public static func undoLast(in folder: URL, progress: ProgressHandler? = nil) async throws -> BatchSummary {
        var operations = load(from: folder)
        guard let operation = operations.popLast() else { throw CaobaError.noFiles }
        let fm = FileManager.default

        var plan: [RenameEntry] = []
        var summary = BatchSummary()
        for entry in operation.entries.reversed() {
            let current = folder.appendingPathComponent(entry.to)
            if fm.fileExists(atPath: current.path) {
                plan.append(RenameEntry(from: current, newName: entry.from))
            } else {
                summary.failures.append("\(entry.to): \(String(localized: "ya no existe", bundle: .module))")
            }
        }
        // El plan inverso no se vuelve a registrar: deshacer no genera historial.
        let result = try await Renamer().execute(plan: plan, saveMode: .overwrite, recordHistory: false, progress: progress)
        summary.processed = result.processed
        summary.failures.append(contentsOf: result.failures)
        try save(operations, in: folder)
        return summary
    }
}
