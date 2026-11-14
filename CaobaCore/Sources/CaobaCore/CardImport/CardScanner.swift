import Foundation

/// Un fichero de la tarjeta: dónde está, cuánto ocupa y su fecha (la que pone la cámara al
/// hacer la foto, guardada como fecha de modificación).
public struct CardFile: Sendable, Equatable {
    public var url: URL
    public var size: Int64
    public var date: Date

    public init(url: URL, size: Int64, date: Date) {
        self.url = url
        self.size = size
        self.date = date
    }
}

/// Una foto o vídeo con sus acompañantes (mismo nombre, otra extensión: ajustes, notas de
/// voz, miniaturas de vídeo). Se descargan juntos y con el mismo nombre final.
public struct CardItem: Sendable, Equatable {
    public var file: CardFile
    public var group: RecoveryFileGroup
    public var companions: [CardFile]

    public init(file: CardFile, group: RecoveryFileGroup, companions: [CardFile] = []) {
        self.file = file
        self.group = group
        self.companions = companions
    }

    public var totalSize: Int64 { companions.reduce(file.size) { $0 + $1.size } }
}

/// Lee qué fotos y vídeos hay en una tarjeta montada. Solo lee: nunca escribe en ella.
public enum CardScanner {
    /// Extensiones de los ficheros que acompañan a una foto o vídeo (`IMG_0001.XMP`,
    /// `IMG_0001.WAV`, `C0001.THM`, `DJI_0001.LRF`).
    public static let companionExtensions: Set<String> = ["xmp", "wav", "thm", "lrf"]

    /// Dónde guardan las cámaras fotos y vídeos: `DCIM` siempre; Sony y Panasonic dejan
    /// el vídeo aparte (XAVC en `PRIVATE/M4ROOT/CLIP`, AVCHD en `PRIVATE/AVCHD/BDMV/STREAM`).
    public static let mediaFolders = ["DCIM", "PRIVATE/M4ROOT/CLIP", "PRIVATE/AVCHD/BDMV/STREAM"]

    /// Fotos y vídeos de los tipos pedidos, con sus acompañantes, en el orden de la tarjeta
    /// (carpeta y nombre). Lo oculto (`._*`, `.DS_Store`, `.Trashes`…) y lo que no es de esos
    /// tipos (ficheros de la cámara como `.CTG`) se ignora.
    public static func scan(volume: URL, groups: Set<RecoveryFileGroup>) -> [CardItem] {
        let files = mediaFolders.flatMap { listFiles(in: volume.appendingPathComponent($0)) }
        // Los acompañantes se buscan por carpeta y nombre sin extensión, sin distinguir mayúsculas.
        var companionsByStem: [String: [CardFile]] = [:]
        for file in files where companionExtensions.contains(file.url.pathExtension.lowercased()) {
            companionsByStem[stemKey(file.url), default: []].append(file)
        }
        return files.compactMap { file in
            guard let group = RecoveryFileGroup.group(of: file.url), groups.contains(group) else { return nil }
            let companions = (companionsByStem[stemKey(file.url)] ?? []).sorted { $0.url.lastPathComponent < $1.url.lastPathComponent }
            return CardItem(file: file, group: group, companions: companions)
        }
    }

    /// Ficheros visibles de una carpeta y sus subcarpetas, ordenados por ruta.
    static func listFiles(in folder: URL) -> [CardFile] {
        let keys: [URLResourceKey] = [.isRegularFileKey, .fileSizeKey, .contentModificationDateKey]
        guard let walker = FileManager.default.enumerator(at: folder, includingPropertiesForKeys: keys,
                                                          options: [.skipsHiddenFiles, .skipsPackageDescendants]) else { return [] }
        var files: [CardFile] = []
        for case let url as URL in walker {
            guard let values = try? url.resourceValues(forKeys: Set(keys)), values.isRegularFile == true,
                  !url.lastPathComponent.hasPrefix("._") else { continue }
            files.append(CardFile(url: url, size: Int64(values.fileSize ?? 0), date: values.contentModificationDate ?? .distantPast))
        }
        return files.sorted { $0.url.path.localizedStandardCompare($1.url.path) == .orderedAscending }
    }

    private static func stemKey(_ url: URL) -> String {
        url.deletingPathExtension().path.lowercased()
    }
}
