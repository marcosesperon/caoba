import Foundation

/// Sistema de archivos que el usuario dice que tiene la tarjeta. Solo cambia cómo
/// busca PhotoRec: con ext2/3/4 activa su modo especial (`options,mode_ext2`).
public enum RecoveryFileSystem: String, Sendable, Codable, CaseIterable {
    /// FAT, exFAT, NTFS, HFS+… (lo que PhotoRec llama «Other»). Casi todas las tarjetas.
    case other
    case ext
}

/// Dónde busca PhotoRec.
public enum RecoveryScope: String, Sendable, Codable, CaseIterable {
    /// Solo lo que el sistema de archivos marca como libre: lo borrado. Más rápido y
    /// no repite lo que sigue en la tarjeta. PhotoRec solo sabe hacerlo en FAT y exFAT
    /// (en NTFS y ext necesitaría librerías que no van en la app; HFS+ no lo admite).
    case freeSpace
    /// Toda la tarjeta, ocupada o no. Para tarjetas formateadas o dañadas.
    case wholeDisk
}

/// Lo que se le pide a PhotoRec.
public struct PhotoRecOptions: Sendable, Equatable {
    /// Dispositivo o imagen a leer (p. ej. `/dev/rdisk4`).
    public var device: String
    public var fileSystem: RecoveryFileSystem
    public var scope: RecoveryScope
    public var groups: Set<RecoveryFileGroup>
    /// «Otros archivos»: con esto, PhotoRec busca todo lo que conoce.
    public var includeOtherFiles: Bool

    public init(device: String, fileSystem: RecoveryFileSystem = .other, scope: RecoveryScope = .freeSpace,
                groups: Set<RecoveryFileGroup> = RecoveryFileGroup.photographerDefault, includeOtherFiles: Bool = false) {
        self.device = device
        self.fileSystem = fileSystem
        self.scope = scope
        self.groups = groups
        self.includeOtherFiles = includeOtherFiles
    }
}

/// Construye los argumentos de PhotoRec en modo sin interfaz. Sintaxis sacada del
/// código de PhotoRec 7.2 (`phmain.c`, `phcli.c`, `poptions.c`); ver docs/documentacion.md.
public enum PhotoRecCommand {
    /// Nombre del log que deja PhotoRec dentro de la carpeta de salida.
    public static let logFileName = "photorec.log"
    /// Prefijo de las carpetas de resultados: `recup_dir.1`, `recup_dir.2`…
    public static let outputPrefix = "recup_dir"

    /// Argumentos para lanzar PhotoRec (sin el ejecutable). `outputFolder` tiene que
    /// existir: PhotoRec crea dentro `recup_dir.N` pero no la carpeta de encima.
    public static func arguments(for options: PhotoRecOptions, outputFolder: URL) throws -> [String] {
        guard !options.device.isEmpty else { throw CaobaError.invalidParameters("device") }
        guard !options.groups.isEmpty || options.includeOtherFiles else { throw CaobaError.noFiles }
        return [
            // `/log` activa el log y `/logname` dice dónde; si no, va a la carpeta de trabajo.
            "/log", "/logname", outputFolder.appendingPathComponent(logFileName).path,
            "/d", outputFolder.appendingPathComponent(outputPrefix).path,
            "/cmd", options.device, script(for: options),
        ]
    }

    /// Las órdenes separadas por comas que van detrás del dispositivo.
    public static func script(for options: PhotoRecOptions) -> String {
        var parts: [String] = []
        if options.fileSystem == .ext { parts += ["options", "mode_ext2"] }
        parts.append("fileopt")
        if options.includeOtherFiles {
            parts += ["everything", "enable"]
        } else {
            parts += ["everything", "disable"]
            for family in families(for: options.groups) { parts += [family, "enable"] }
        }
        parts.append(options.scope == .freeSpace ? "freespace" : "wholespace")
        parts.append("search")
        return parts.joined(separator: ",")
    }

    /// Familias de los grupos elegidos, sin repetir y en un orden fijo.
    public static func families(for groups: Set<RecoveryFileGroup>) -> [String] {
        var seen = Set<String>()
        return groups.sorted().flatMap(\.photoRecFamilies).filter { seen.insert($0).inserted }
    }
}
