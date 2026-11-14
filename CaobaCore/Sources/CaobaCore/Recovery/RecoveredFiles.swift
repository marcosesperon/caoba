import Foundation

/// Ficheros que PhotoRec ha ido dejando en `recup_dir.1`, `recup_dir.2`… Se usa
/// mientras trabaja (para el progreso) y al acabar (para los resultados).
public enum RecoveredFiles {
    /// Recuento por grupo; los de «Otros archivos» van en `other`.
    public struct Counts: Sendable, Equatable {
        public var byGroup: [RecoveryFileGroup: Int] = [:]
        public var other = 0

        public init(byGroup: [RecoveryFileGroup: Int] = [:], other: Int = 0) {
            self.byGroup = byGroup
            self.other = other
        }

        public var total: Int { byGroup.values.reduce(other, +) }
    }

    /// Todos los ficheros recuperados, ordenados por carpeta y nombre (el orden en el que
    /// aparecen en la tarjeta). Deja fuera `report.xml` y las miniaturas `t*.jpg` que
    /// PhotoRec saca de cada JPG, que no son fotos sino copias pequeñas.
    public static func list(in outputFolder: URL) -> [URL] {
        blocks(in: outputFolder).flatMap(\.files)
    }

    /// Un bloque: una carpeta `recup_dir.N` de PhotoRec (hasta 500 ficheros) y lo que tiene.
    public struct Block: Sendable, Equatable, Identifiable {
        public var number: Int
        public var folder: URL
        public var files: [URL]
        public var id: Int { number }

        public init(number: Int, folder: URL, files: [URL]) {
            self.number = number
            self.folder = folder
            self.files = files
        }
    }

    /// Lo recuperado agrupado por bloque, en orden. Con `settledFor`, deja fuera los ficheros
    /// modificados hace menos de ese tiempo: mientras PhotoRec trabaja, así no sale el que
    /// está escribiendo (ni se puede borrar ni da una miniatura a medias).
    public static func blocks(in outputFolder: URL, settledFor: TimeInterval = 0, now: Date = Date()) -> [Block] {
        let fm = FileManager.default
        let keys: [URLResourceKey] = [.isRegularFileKey, .contentModificationDateKey]
        return blockFolders(in: outputFolder).map { number, folder in
            let files = ((try? fm.contentsOfDirectory(at: folder, includingPropertiesForKeys: keys)) ?? [])
                .filter { url in
                    guard isRecoveredFile(url), let values = try? url.resourceValues(forKeys: Set(keys)),
                          values.isRegularFile == true else { return false }
                    guard settledFor > 0, let modified = values.contentModificationDate else { return true }
                    return now.timeIntervalSince(modified) >= settledFor
                }
                .sorted { $0.lastPathComponent < $1.lastPathComponent }
            return Block(number: number, folder: folder, files: files)
        }
    }

    /// Borra para siempre los ficheros indicados y, de cada uno, la miniatura que deja PhotoRec
    /// (`t…` en lugar de `f…`), que no sale en la lista pero ocupa. Devuelve cuántos ha borrado
    /// y los que no ha podido; lo que ya no existe no cuenta como fallo.
    public static func delete(_ files: [URL]) -> (deleted: Int, failures: [String]) {
        let fm = FileManager.default
        var deleted = 0
        var failures: [String] = []
        for file in files {
            do {
                try fm.removeItem(at: file)
                deleted += 1
            } catch CocoaError.fileNoSuchFile {
                continue
            } catch {
                failures.append("\(file.lastPathComponent): \(error.localizedDescription)")
                continue
            }
            if let thumbnail = thumbnail(of: file) { try? fm.removeItem(at: thumbnail) }
        }
        return (deleted, failures)
    }

    /// Borra un bloque entero (la carpeta con todo lo que tenga). Devuelve cuántos ficheros
    /// recuperados había (sin contar miniaturas).
    public static func deleteBlock(_ block: Block) throws -> Int {
        let count = blocks(in: block.folder.deletingLastPathComponent()).first { $0.number == block.number }?.files.count ?? 0
        try FileManager.default.removeItem(at: block.folder)
        return count
    }

    /// Miniatura de un JPG recuperado (`f123.jpg` → `t123.jpg`), si existe.
    static func thumbnail(of file: URL) -> URL? {
        let name = file.lastPathComponent
        guard name.hasPrefix("f") else { return nil }
        let base = (name as NSString).deletingPathExtension
        let candidate = file.deletingLastPathComponent().appendingPathComponent("t" + base.dropFirst() + ".jpg")
        return FileManager.default.fileExists(atPath: candidate.path) ? candidate : nil
    }

    /// Lo que ocupa en disco todo lo que hay en la carpeta de salida (miniaturas y log incluidos).
    public static func diskUsage(of outputFolder: URL) -> Int64 {
        let keys: Set<URLResourceKey> = [.totalFileAllocatedSizeKey, .isRegularFileKey]
        guard let walker = FileManager.default.enumerator(at: outputFolder, includingPropertiesForKeys: Array(keys)) else { return 0 }
        var total: Int64 = 0
        for case let url as URL in walker {
            guard let values = try? url.resourceValues(forKeys: keys), values.isRegularFile == true else { continue }
            total += Int64(values.totalFileAllocatedSize ?? 0)
        }
        return total
    }

    /// Carpetas `recup_dir.N` que hay, con su número, en orden.
    static func blockFolders(in outputFolder: URL) -> [(Int, URL)] {
        ((try? FileManager.default.contentsOfDirectory(at: outputFolder, includingPropertiesForKeys: nil)) ?? [])
            .compactMap { url in folderNumber(url).map { ($0, url) } }
            .sorted { $0.0 < $1.0 }
    }

    public static func count(in outputFolder: URL) -> Counts {
        count(list(in: outputFolder))
    }

    public static func count(_ files: [URL]) -> Counts {
        var counts = Counts()
        for file in files {
            if let group = RecoveryFileGroup.group(of: file) { counts.byGroup[group, default: 0] += 1 } else { counts.other += 1 }
        }
        return counts
    }

    /// Número de `recup_dir.N`, o `nil` si la carpeta no es de PhotoRec.
    static func folderNumber(_ url: URL) -> Int? {
        let name = url.lastPathComponent
        let prefix = PhotoRecCommand.outputPrefix + "."
        guard name.hasPrefix(prefix) else { return nil }
        return Int(name.dropFirst(prefix.count))
    }

    /// Lo recuperado se llama `f<número>[_nombre].ext`; las miniaturas, `t<número>.jpg`.
    static func isRecoveredFile(_ url: URL) -> Bool {
        let name = url.lastPathComponent
        guard name != "report.xml", !name.hasPrefix(".") else { return false }
        let isThumbnail = name.hasPrefix("t") && name.dropFirst().prefix { $0 != "." }.allSatisfy(\.isNumber)
        return !isThumbnail
    }
}
