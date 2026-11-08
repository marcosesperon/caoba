import Foundation

/// Grupos de ficheros que se pueden recuperar, pensados para fotógrafos. Por defecto
/// van los cuatro; «Otros archivos» (todo lo demás que conoce PhotoRec) va aparte.
///
/// PhotoRec no filtra por extensión sino por **familias** (`fileopt` compara con la
/// extensión principal de cada una), y algunas familias traen de todo: `tif` incluye
/// CR2, NEF, ARW, DNG y PEF; `mov` incluye MP4, HEIC y CR3. Por eso cada grupo dice qué
/// familias activa y, aparte, qué extensiones le pertenecen al clasificar lo recuperado.
/// Familias comprobadas en el código de PhotoRec 7.2 (`src/file_*.c`).
public enum RecoveryFileGroup: String, CaseIterable, Sendable, Codable, Comparable {
    case jpeg, raw, heic, video

    /// Lo que se recupera si el usuario no toca nada.
    public static let photographerDefault: Set<RecoveryFileGroup> = Set(allCases)

    /// Familias de PhotoRec que hay que activar para este grupo.
    public var photoRecFamilies: [String] {
        switch self {
        case .jpeg: return ["jpg"]
        // `mov` por el CR3 de Canon; `raw` es el RAW de Contax.
        case .raw: return ["tif", "crw", "raf", "orf", "rw2", "mrw", "x3f", "raw", "mov"]
        case .heic: return ["mov"]
        // `riff` es AVI, `m2ts` y `ts` el AVCHD (MTS) y `mlv` el RAW de Magic Lantern.
        case .video: return ["mov", "m2ts", "ts", "riff", "mpg", "mkv", "mxf", "mlv", "r3d", "dv"]
        }
    }

    /// Extensiones (en minúsculas) de lo recuperado que cuentan como este grupo.
    /// TIFF va con RAW porque PhotoRec los saca de la misma familia.
    public var fileExtensions: Set<String> {
        switch self {
        case .jpeg: return ["jpg", "jpeg"]
        case .raw: return ["cr2", "cr3", "crw", "nef", "nrw", "arw", "sr2", "srf", "dng", "pef", "raf", "orf",
                           "rw2", "mrw", "x3f", "raw", "dcr", "tif", "tiff"]
        case .heic: return ["heic", "heif"]
        case .video: return ["mov", "mp4", "m4v", "3gp", "m2ts", "mts", "ts", "avi", "mpg", "mpeg", "mkv",
                             "mxf", "mlv", "r3d", "dv"]
        }
    }

    /// Grupo de un fichero recuperado según su extensión; `nil` si es de «Otros archivos».
    public static func group(of url: URL) -> RecoveryFileGroup? {
        let ext = url.pathExtension.lowercased()
        return allCases.first { $0.fileExtensions.contains(ext) }
    }

    /// Orden fijo (el de `allCases`) para que la orden de PhotoRec salga siempre igual.
    public static func < (lhs: RecoveryFileGroup, rhs: RecoveryFileGroup) -> Bool {
        allCases.firstIndex(of: lhs)! < allCases.firstIndex(of: rhs)!
    }
}
