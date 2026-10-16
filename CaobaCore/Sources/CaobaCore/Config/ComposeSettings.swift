import Foundation

/// Ajustes de la hoja «Componer secuencia» tal como se guardan en el `.caoba`:
/// reparto, reordenar, filtros y plantillas marcadas. Todo opcional para que
/// los ficheros antiguos sigan leyéndose.
public struct ComposeSettings: Codable, Sendable, Equatable {
    /// "random" o "content".
    public var mode: String?
    public var allowReorder: Bool?
    public var photosFilter: Int?
    public var aspectFilter: String?
    /// "basic" u "overlap".
    public var typeFilter: String?
    public var selectedTemplates: [String]?

    public init(mode: String? = nil, allowReorder: Bool? = nil, photosFilter: Int? = nil, aspectFilter: String? = nil,
                typeFilter: String? = nil, selectedTemplates: [String]? = nil) {
        self.mode = mode
        self.allowReorder = allowReorder
        self.photosFilter = photosFilter
        self.aspectFilter = aspectFilter
        self.typeFilter = typeFilter
        self.selectedTemplates = selectedTemplates
    }
}

/// Sección `collage` del `.caoba`: lo que el módulo Collage recuerda por carpeta.
public struct CollageFolderSettings: Codable, Sendable, Equatable {
    public static let sectionName = "collage"
    public var compose: ComposeSettings?

    public init(compose: ComposeSettings? = nil) {
        self.compose = compose
    }

    public static func load(from folder: URL) -> CollageFolderSettings? {
        CaobaConfig.readSection(sectionName, as: CollageFolderSettings.self, from: folder)
    }

    public func save(in folder: URL) throws {
        try CaobaConfig.writeSection(Self.sectionName, value: self, in: folder)
    }
}
