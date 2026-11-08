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
        let fm = FileManager.default
        let folders = ((try? fm.contentsOfDirectory(at: outputFolder, includingPropertiesForKeys: nil)) ?? [])
            .filter { folderNumber($0) != nil }
            .sorted { folderNumber($0)! < folderNumber($1)! }
        return folders.flatMap { folder in
            ((try? fm.contentsOfDirectory(at: folder, includingPropertiesForKeys: [.isRegularFileKey])) ?? [])
                .filter { (try? $0.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile) == true && isRecoveredFile($0) }
                .sorted { $0.lastPathComponent < $1.lastPathComponent }
        }
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
