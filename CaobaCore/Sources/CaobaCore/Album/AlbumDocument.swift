import Foundation
import CoreGraphics

/// Lo que se sabe de una foto para maquetarla: su formato, sus caras y cuándo se disparó.
/// Se calcula una vez (las caras con Vision) y se guarda en el álbum.
public struct AlbumPhotoInfo: Codable, Sendable, Equatable {
    /// Ancho / alto de la foto tal como se ve (ya girada).
    public var aspect: Double
    public var captureDate: Date
    /// Caras encontradas, normalizadas (0-1, origen arriba-izquierda). `nil` = aún sin analizar.
    public var faces: [CGRect]?
    /// Punto donde centrar el encuadre (las caras o, si no hay, lo más llamativo).
    public var focus: CGPoint?

    public init(aspect: Double, captureDate: Date, faces: [CGRect]? = nil, focus: CGPoint? = nil) {
        self.aspect = aspect
        self.captureDate = captureDate
        self.faces = faces
        self.focus = focus
    }

    public var isAnalyzed: Bool { faces != nil }
    public var faceCount: Int { faces?.count ?? 0 }
    /// Alto de la cara más pequeña, en parte del alto de la foto (0-1).
    public var smallestFace: Double? { faces?.map { Double($0.height) }.min() }
    /// Caja que engloba todas las caras.
    public var facesBox: CGRect? {
        guard let faces, let first = faces.first else { return nil }
        return faces.dropFirst().reduce(first) { $0.union($1) }
    }
}

/// Un álbum de la sesión: sus medidas (copiadas del tipo al crearlo), la tira de fotos en orden
/// y los pliegos. Se guarda en `Álbum/<nombre>/<nombre>.caobaalbum`.
public struct AlbumDocument: Codable, Sendable, Equatable {
    public static let fileExtension = "caobaalbum"
    public static let currentVersion = 1

    public var version: Int
    /// Tipo del que salió (solo informativo: cambiar el tipo no toca el álbum).
    public var typeName: String
    public var spec: AlbumSpec
    /// La tira: nombres de fichero en el orden del álbum.
    public var photos: [String]
    public var spreads: [AlbumSpread]
    /// Análisis de cada foto de la tira (y de la portada), por nombre.
    public var info: [String: AlbumPhotoInfo]
    /// La portada (contraportada, lomo y tapa), maquetada como un pliego con `spec.coverSpec`.
    /// Sus fotos son libres: no cuentan para la tira ni para la cascada. `nil` = aún no se ha creado.
    public var cover: AlbumSpread?
    /// «Reparto automático»: cada cambio vuelve a repartir solo. Desmarcado (lo normal), lo
    /// maquetado no se mueve hasta pulsar «Repartir».
    public var autoLayout: Bool
    /// En manual, hay cambios (fotos que entran o salen, pliegos, números pedidos…) esperando al
    /// siguiente reparto.
    public var pendingLayout: Bool

    public init(typeName: String, spec: AlbumSpec, photos: [String] = [], spreads: [AlbumSpread] = [], info: [String: AlbumPhotoInfo] = [:]) {
        self.version = Self.currentVersion
        self.typeName = typeName
        self.spec = spec
        self.photos = photos
        self.spreads = spreads
        self.info = info
        // Un álbum nuevo se reparte solo mientras se eligen fotos (se ve cómo va quedando). Los
        // guardados sin este dato se abren en manual (ver `init(from:)`).
        self.autoLayout = true
        self.pendingLayout = false
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        version = try c.decodeIfPresent(Int.self, forKey: .version) ?? Self.currentVersion
        typeName = try c.decodeIfPresent(String.self, forKey: .typeName) ?? ""
        spec = try c.decodeIfPresent(AlbumSpec.self, forKey: .spec) ?? AlbumSpec()
        photos = try c.decodeIfPresent([String].self, forKey: .photos) ?? []
        spreads = try c.decodeIfPresent([AlbumSpread].self, forKey: .spreads) ?? []
        info = try c.decodeIfPresent([String: AlbumPhotoInfo].self, forKey: .info) ?? [:]
        cover = try c.decodeIfPresent(AlbumSpread.self, forKey: .cover)
        autoLayout = try c.decodeIfPresent(Bool.self, forKey: .autoLayout) ?? false
        pendingLayout = try c.decodeIfPresent(Bool.self, forKey: .pendingLayout) ?? false
    }

    /// Fotos de la tira que no están en ningún pliego (en manual, hasta el siguiente reparto).
    public var unplacedPhotos: Set<String> {
        Set(photos).subtracting(spreads.flatMap(\.photos))
    }

    /// Qué página se usa en el pliego `index` si es de una sola página (el primero, la derecha; el
    /// último, la izquierda). `nil` si es un pliego normal.
    public func singleSide(ofSpread index: Int) -> AlbumPageSide? {
        guard spec.singleFirstLast, spreads.indices.contains(index) else { return nil }
        if index == 0 { return .right }
        if index == spreads.count - 1 { return .left }
        return nil
    }

    /// La portada con la que empezar: la primera foto del álbum a sangre en la tapa.
    public static func initialCover(photo: String?) -> AlbumSpread {
        AlbumSpread(layout: .pages(left: nil, right: AlbumBlock(node: .cell(AlbumCell(photo: photo, bleed: true)))))
    }

    /// Todas las fotos que se usan (tira y portada), para analizarlas.
    public var allPhotos: [String] {
        photos + (cover?.photos.filter { !photos.contains($0) } ?? [])
    }

    // MARK: - Ficheros

    public func save(to url: URL) throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try encoder.encode(self).write(to: url, options: .atomic)
    }

    public static func load(from url: URL) throws -> AlbumDocument {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode(AlbumDocument.self, from: Data(contentsOf: url))
    }
}

/// Dónde viven los álbumes de una sesión: una carpeta por álbum dentro de la carpeta de álbumes
/// (`Álbum`), con su fichero `.caobaalbum` y, en la fase 3, los pliegos exportados.
public struct AlbumLibrary: Sendable, Equatable {
    /// La carpeta de álbumes (`<sesión>/Álbum`, o `<carpeta suelta>/Álbum`).
    public var folder: URL

    public init(folder: URL) {
        self.folder = folder
    }

    /// Carpeta de un álbum.
    public func folder(of name: String) -> URL {
        folder.appendingPathComponent(name, isDirectory: true)
    }

    /// Fichero de un álbum.
    public func file(of name: String) -> URL {
        folder(of: name).appendingPathComponent(name).appendingPathExtension(AlbumDocument.fileExtension)
    }

    /// Nombres de los álbumes que hay, por orden alfabético.
    public func albumNames() -> [String] {
        let fm = FileManager.default
        guard let items = try? fm.contentsOfDirectory(at: folder, includingPropertiesForKeys: [.isDirectoryKey], options: [.skipsHiddenFiles]) else { return [] }
        return items
            .filter { (try? $0.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true }
            .map(\.lastPathComponent)
            .filter { fm.fileExists(atPath: file(of: $0).path) }
            .sorted { $0.localizedStandardCompare($1) == .orderedAscending }
    }

    /// Nombre válido para una carpeta: sin barras ni dos puntos, sin espacios sobrantes.
    public static func cleanName(_ name: String) -> String {
        name.replacingOccurrences(of: "/", with: "-").replacingOccurrences(of: ":", with: "-")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// `name` si está libre; si no, «name 2», «name 3»…
    public func uniqueName(_ name: String) -> String {
        let base = Self.cleanName(name)
        let taken = Set(albumNames().map { $0.lowercased() })
        guard taken.contains(base.lowercased()) else { return base }
        var number = 2
        while taken.contains("\(base) \(number)".lowercased()) { number += 1 }
        return "\(base) \(number)"
    }

    /// Cambia el nombre de un álbum: su carpeta y su fichero.
    public func rename(_ old: String, to new: String) throws {
        let fm = FileManager.default
        let target = Self.cleanName(new)
        // Si solo cambian mayúsculas, en un disco que no las distingue «Boda» y «boda» son el
        // mismo sitio: se pasa por un nombre intermedio.
        let viaTemp = old.lowercased() == target.lowercased()
        let temp = ".caoba-renombrando-\(UUID().uuidString)"
        try fm.moveItem(at: file(of: old), to: folder(of: old).appendingPathComponent(viaTemp ? temp : target).appendingPathExtension(AlbumDocument.fileExtension))
        if viaTemp {
            try fm.moveItem(at: folder(of: old).appendingPathComponent(temp).appendingPathExtension(AlbumDocument.fileExtension), to: file(of: old).deletingLastPathComponent().appendingPathComponent(target).appendingPathExtension(AlbumDocument.fileExtension))
            try fm.moveItem(at: folder(of: old), to: folder.appendingPathComponent(temp, isDirectory: true))
            try fm.moveItem(at: folder.appendingPathComponent(temp, isDirectory: true), to: folder(of: target))
        } else {
            try fm.moveItem(at: folder(of: old), to: folder(of: target))
        }
    }
}
