import Foundation

/// Cómo se reparten las fotos en la carpeta de destino.
public enum CardImportLayout: String, Sendable, Codable, CaseIterable {
    /// Todo en la carpeta elegida.
    case flat
    /// En `AAAA/MM-DD/` según la fecha de la foto.
    case byDate
}

/// Una foto (o vídeo) que hay que copiar y a dónde, con sus acompañantes.
public struct CardImportTask: Sendable, Equatable {
    public var source: CardFile
    public var destination: URL
    public var companions: [(source: CardFile, destination: URL)]

    public var totalSize: Int64 { companions.reduce(source.size) { $0 + $1.source.size } }

    public static func == (lhs: CardImportTask, rhs: CardImportTask) -> Bool {
        lhs.source == rhs.source && lhs.destination == rhs.destination
            && lhs.companions.map(\.source) == rhs.companions.map(\.source)
            && lhs.companions.map(\.destination) == rhs.companions.map(\.destination)
    }
}

/// Qué hay que copiar de una tarjeta y qué ya estaba en el destino.
///
/// Una foto «ya está» si en su carpeta de destino hay un fichero con su nombre (o con su nombre
/// y un sufijo `_2`, `_3`…) del mismo tamaño y la misma fecha. Mirar también los sufijos es lo
/// que permite descargar varias tarjetas con nombres repetidos (dos cámaras con su `IMG_0001`)
/// y volver a descargarlas sin duplicar nada. Si solo coincide el nombre, es otra foto: va con
/// el primer sufijo libre. Nunca se sobrescribe nada.
public struct CardImportPlan: Sendable, Equatable {
    public var tasks: [CardImportTask]
    /// Fotos y vídeos de la tarjeta (de los tipos elegidos).
    public var totalItems: Int
    /// Los que ya estaban en el destino.
    public var alreadyThere: Int

    public var bytesToCopy: Int64 { tasks.reduce(0) { $0 + $1.totalSize } }

    /// Diferencia de fecha que se tolera al comparar con lo ya descargado: algunos sistemas de
    /// archivos (FAT) guardan la hora con 2 segundos de precisión.
    static let dateTolerance: TimeInterval = 2

    public static func make(items: [CardItem], destination: URL, layout: CardImportLayout,
                            calendar: Calendar = .current) -> CardImportPlan {
        let fm = FileManager.default
        var tasks: [CardImportTask] = []
        var alreadyThere = 0
        // Nombres que ya se van a usar en esta descarga (dos fotos iguales de nombre en la misma tarjeta).
        var reserved: Set<String> = []

        for item in items {
            let folder = layout == .flat ? destination
                : destination.appendingPathComponent(PhotoOrganizer.dateFolder(for: item.file.date, calendar: calendar), isDirectory: true)
            let name = item.file.url.lastPathComponent
            var suffix = 1
            var target: URL?
            while target == nil {
                let candidate = folder.appendingPathComponent(suffixed(name, suffix))
                let key = candidate.path.lowercased()
                if reserved.contains(key) {
                    suffix += 1
                } else if let values = try? candidate.resourceValues(forKeys: [.fileSizeKey, .contentModificationDateKey]),
                          fm.fileExists(atPath: candidate.path) {
                    // Ya hay algo con ese nombre: ¿es esta misma foto o es otra?
                    let sameSize = Int64(values.fileSize ?? -1) == item.file.size
                    let sameDate = abs((values.contentModificationDate ?? .distantPast).timeIntervalSince(item.file.date)) <= dateTolerance
                    if sameSize && sameDate { break }
                    suffix += 1
                } else {
                    target = candidate
                    reserved.insert(key)
                }
            }
            guard let target else {
                alreadyThere += 1
                continue
            }
            let stem = target.deletingPathExtension().lastPathComponent
            let companions = item.companions.map { companion in
                (source: companion, destination: folder.appendingPathComponent(stem + "." + companion.url.pathExtension))
            }
            tasks.append(CardImportTask(source: item.file, destination: target, companions: companions))
        }
        return CardImportPlan(tasks: tasks, totalItems: items.count, alreadyThere: alreadyThere)
    }

    /// `IMG_0001.CR3` con sufijo 1 → igual; con sufijo 2 → `IMG_0001_2.CR3`.
    static func suffixed(_ name: String, _ suffix: Int) -> String {
        guard suffix > 1 else { return name }
        let ext = (name as NSString).pathExtension
        let base = (name as NSString).deletingPathExtension
        return "\(base)_\(suffix)" + (ext.isEmpty ? "" : "." + ext)
    }
}
