import Foundation

/// Ordena lo recuperado por fecha de captura **copiando** (nunca moviendo) a una
/// carpeta nueva: `AAAA/MM-DD/AAAA-MM-DD_HHMMSS.ext`. Lo que no tiene fecha va a
/// `sin_fecha/` con su nombre de siempre. Los originales no se tocan.
public enum PhotoOrganizer {
    /// Carpeta para lo que no tiene fecha. Va en español también con la app en inglés:
    /// es el nombre que se pidió y un nombre de carpeta no se traduce después.
    public static let undatedFolder = "sin_fecha"

    public struct Summary: Sendable, Equatable {
        /// Copiados en su carpeta de fecha.
        public var dated = 0
        /// Copiados a `sin_fecha/`.
        public var undated = 0
        /// Los que no se pudieron copiar, con el motivo.
        public var failures: [String] = []

        public init(dated: Int = 0, undated: Int = 0, failures: [String] = []) {
            self.dated = dated
            self.undated = undated
            self.failures = failures
        }

        public var copied: Int { dated + undated }
    }

    /// Copia `files` a `destination` ordenados por fecha. Si un nombre ya existe (dos
    /// fotos del mismo segundo, o una carpeta que ya tenía cosas), añade `_2`, `_3`…
    public static func organize(_ files: [URL], into destination: URL,
                                progress: ProgressHandler? = nil) async throws -> Summary {
        let fm = FileManager.default
        var summary = Summary()
        for (index, file) in files.enumerated() {
            try Task.checkCaobaCancellation()
            progress?(.step(index, of: files.count, phase: .organizingFiles, file: file.lastPathComponent))
            let date = await CaptureDateReader.captureDate(of: file)
            let target = availableURL(destination.appendingPathComponent(relativePath(for: file, date: date)))
            do {
                try fm.createDirectory(at: target.deletingLastPathComponent(), withIntermediateDirectories: true)
                try fm.copyItem(at: file, to: target)
                if date == nil { summary.undated += 1 } else { summary.dated += 1 }
            } catch {
                summary.failures.append("\(file.lastPathComponent): \(error.localizedDescription)")
            }
        }
        progress?(.step(files.count, of: files.count, phase: .organizingFiles))
        return summary
    }

    /// Ruta dentro del destino: `2024/05-31/2024-05-31_142210.jpg`, o `sin_fecha/f0002051.jpg`.
    /// La fecha se escribe en la hora local, que es como la guardan las cámaras.
    public static func relativePath(for file: URL, date: Date?, calendar: Calendar = .current) -> String {
        guard let date else { return undatedFolder + "/" + file.lastPathComponent }
        let c = calendar.dateComponents([.year, .month, .day, .hour, .minute, .second], from: date)
        let year = String(format: "%04d", c.year ?? 0)
        let monthDay = String(format: "%02d-%02d", c.month ?? 0, c.day ?? 0)
        let time = String(format: "%02d%02d%02d", c.hour ?? 0, c.minute ?? 0, c.second ?? 0)
        let ext = file.pathExtension.lowercased()
        let name = "\(year)-\(monthDay)_\(time)" + (ext.isEmpty ? "" : "." + ext)
        return "\(year)/\(monthDay)/\(name)"
    }

    /// `url` si no existe; si no, el primero libre de `nombre_2.ext`, `nombre_3.ext`…
    static func availableURL(_ url: URL) -> URL {
        let fm = FileManager.default
        guard fm.fileExists(atPath: url.path) else { return url }
        let base = url.deletingPathExtension().lastPathComponent
        let ext = url.pathExtension
        let folder = url.deletingLastPathComponent()
        var n = 2
        while true {
            let name = "\(base)_\(n)" + (ext.isEmpty ? "" : "." + ext)
            let candidate = folder.appendingPathComponent(name)
            if !fm.fileExists(atPath: candidate.path) { return candidate }
            n += 1
        }
    }
}
