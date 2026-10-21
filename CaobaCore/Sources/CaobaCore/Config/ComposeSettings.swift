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

/// Lo que el modo Carrusel del Collage recuerda por carpeta. Todo opcional.
public struct CarouselSettings: Codable, Sendable, Equatable {
    /// «4x5», «1x1» o «3x4».
    public var format: String?
    /// Componer: «random» o «content», y si se pueden reordenar las fotos.
    public var mode: String?
    public var allowReorder: Bool?
    /// Tramos marcados para Componer, sin formato («pano_2»…).
    public var templates: [String]?

    public init(format: String? = nil, mode: String? = nil, allowReorder: Bool? = nil, templates: [String]? = nil) {
        self.format = format
        self.mode = mode
        self.allowReorder = allowReorder
        self.templates = templates
    }
}

/// Sección `collage` del `.caoba`: lo que el módulo Collage recuerda por carpeta.
public struct CollageFolderSettings: Codable, Sendable, Equatable {
    public static let sectionName = "collage"
    public var compose: ComposeSettings?
    /// Modo Carrusel: formato y ajustes de Componer (con los tramos marcados, sin formato).
    public var carousel: CarouselSettings?

    public init(compose: ComposeSettings? = nil, carousel: CarouselSettings? = nil) {
        self.compose = compose
        self.carousel = carousel
    }

    public static func load(from folder: URL) -> CollageFolderSettings? {
        CaobaConfig.readSection(sectionName, as: CollageFolderSettings.self, from: folder)
    }

    public func save(in folder: URL) throws {
        try CaobaConfig.writeSection(Self.sectionName, value: self, in: folder)
    }
}
