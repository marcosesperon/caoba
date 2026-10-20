import Foundation

/// Sección `fileOrder` del `.caoba`: el orden manual de las fotos de la carpeta (por
/// nombre), común a Slideshow, Collage y Contact Sheet. Si no está, las fotos van por
/// nombre o por fecha. No es protegida: «Reiniciar» la quita con el resto.
public struct FileOrderSettings: Codable, Sendable, Equatable {
    public static let sectionName = "fileOrder"
    public var names: [String]

    public init(names: [String]) {
        self.names = names
    }

    public static func load(from folder: URL) -> FileOrderSettings? {
        CaobaConfig.readSection(sectionName, as: FileOrderSettings.self, from: folder)
    }

    public func save(in folder: URL) throws {
        try CaobaConfig.writeSection(Self.sectionName, value: self, in: folder)
    }

    /// Vuelta al orden por nombre o fecha.
    public static func remove(from folder: URL) throws {
        try CaobaConfig.removeSection(sectionName, in: folder)
    }
}
