import Foundation

/// Todo lo temporal va al directorio temporal del sistema, nunca a la carpeta
/// de fotos del usuario (uno de los problemas de la app antigua).
public enum TempFiles {
    /// Carpeta temporal propia de CAOBA, creada si no existe.
    public static func baseDirectory() throws -> URL {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("caoba", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    /// Carpeta temporal única para un trabajo concreto (frames, segmentos...).
    public static func makeJobDirectory(prefix: String) throws -> URL {
        let dir = try baseDirectory().appendingPathComponent("\(prefix)_\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    /// Ruta temporal para escribir un fichero antes de moverlo a su sitio definitivo.
    public static func makeFileURL(extension ext: String) throws -> URL {
        try baseDirectory().appendingPathComponent(UUID().uuidString).appendingPathExtension(ext)
    }

    /// Borra sin quejarse si no existe.
    public static func remove(_ url: URL) {
        try? FileManager.default.removeItem(at: url)
    }
}

/// Dónde y cómo se guarda el resultado de un trabajo por lotes.
public enum SaveMode: Sendable, Equatable {
    /// Crea copias nuevas. Si `outputFolder` es `nil` o la misma carpeta de
    /// origen, se añade un sufijo al nombre para no pisar el original.
    case newCopy(outputFolder: URL?)
    /// Sobrescribe el original (escribiendo primero en temporal y reemplazando).
    case overwrite
}

public extension SaveMode {
    /// Calcula la URL de salida para un fichero de entrada.
    /// - Parameters:
    ///   - input: fichero original.
    ///   - sameFolderSuffix: sufijo que se añade si se guarda en la misma carpeta (`_processed`...).
    ///   - newExtension: extensión de salida si cambia el formato; `nil` mantiene la original.
    func outputURL(for input: URL, sameFolderSuffix: String, newExtension: String? = nil) -> URL {
        let baseName = input.deletingPathExtension().lastPathComponent
        let ext = newExtension ?? input.pathExtension
        switch self {
        case .overwrite:
            return input.deletingLastPathComponent().appendingPathComponent(baseName).appendingPathExtension(ext)
        case .newCopy(let outputFolder):
            let sourceFolder = input.deletingLastPathComponent()
            let folder = outputFolder ?? sourceFolder
            let isSameFolder = folder.standardizedFileURL == sourceFolder.standardizedFileURL
            let name = isSameFolder ? baseName + sameFolderSuffix : baseName
            return folder.appendingPathComponent(name).appendingPathExtension(ext)
        }
    }

    var isOverwrite: Bool {
        if case .overwrite = self { return true }
        return false
    }
}

public enum FileOperations {
    /// Mueve un fichero recién escrito en temporal a su destino final. Si el
    /// destino existe se reemplaza de forma atómica; si está en otro volumen,
    /// `replaceItemAt` se encarga de copiar.
    public static func commit(temporary tempURL: URL, to destination: URL) throws {
        let fm = FileManager.default
        try fm.createDirectory(at: destination.deletingLastPathComponent(), withIntermediateDirectories: true)
        if fm.fileExists(atPath: destination.path) {
            _ = try fm.replaceItemAt(destination, withItemAt: tempURL)
        } else {
            do {
                try fm.moveItem(at: tempURL, to: destination)
            } catch {
                // Entre volúmenes distintos `moveItem` puede fallar: copiamos y borramos.
                try fm.copyItem(at: tempURL, to: destination)
                try? fm.removeItem(at: tempURL)
            }
        }
    }
}
