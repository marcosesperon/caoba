import Foundation
import CaobaCore

/// Cómo está el disco de una carpeta: su nombre, lo que cabe en total y lo libre. Lo usa la
/// barra de ocupación del destino en Descargar tarjeta y Recuperar fotos.
struct DiskSpace: Equatable {
    /// Nombre del volumen («Macintosh HD», «SSD Fotos»…).
    var name: String
    var total: Int64
    /// Libre de verdad, sin contar lo que macOS podría liberar (cachés, copias de iCloud): es lo
    /// mismo que miran las pausas por espacio, así la barra se llena cuando ellas pararían.
    var free: Int64

    var used: Int64 { max(total - free, 0) }

    /// Mide el disco de `folder`. Si la carpeta aún no existe (la de fecha, la de una sesión
    /// recién creada…), mide la primera de encima que sí exista. `nil` si no se puede leer.
    static func of(_ folder: URL) -> DiskSpace? {
        // URL nueva a propósito: una URL guarda en caché sus valores y daría lo libre de antes.
        let url = URL(fileURLWithPath: folder.existingAncestor.path)
        guard let values = try? url.resourceValues(forKeys: [.volumeLocalizedNameKey, .volumeTotalCapacityKey, .volumeAvailableCapacityKey]),
              let total = values.volumeTotalCapacity, let free = values.volumeAvailableCapacity, total > 0 else { return nil }
        return DiskSpace(name: values.volumeLocalizedName ?? url.lastPathComponent, total: Int64(total), free: Int64(free))
    }
}
