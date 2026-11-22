import SwiftUI

/// Barra de ocupación del disco de destino, como la de Finder: lo ocupado en gris, encima lo
/// que se va a guardar (en rojo, o rayado si es solo un máximo) y lo libre que queda. Si no
/// cabe, el tramo llega hasta el final y se pinta en naranja.
///
///     Macintosh HD  [██████████▓▓░░░░░░]  182 GB libres de 1 TB · esta descarga 10,1 GB
struct DiskSpaceBar: View {
    /// La carpeta de destino. Su disco se mide cada vez que se dibuja la barra (es una consulta
    /// rápida al sistema), así lo libre está al día al marcar, cambiar de destino o volver.
    let folder: URL
    /// Lo que se va a guardar; `nil` si aún no se sabe (sin tarjeta, nada marcado…).
    var incoming: Int64?
    /// `incoming` es lo máximo que puede salir, no lo que saldrá seguro (Recuperar fotos).
    var isEstimate = false
    /// Lo que va detrás de lo libre: «esta descarga 10,1 GB», «puede ocupar hasta 58 GB».
    var detail: String?
    /// No cabe. Lo decide quien la usa, con la misma cuenta que su aviso, para que digan lo mismo.
    var overflows = false

    var body: some View {
        if let space = DiskSpace.of(folder) {
            HStack(spacing: 10) {
                Label(space.name, systemImage: "internaldrive")
                    .lineLimit(1)
                    .fixedSize()
                bar(space)
                    .frame(minWidth: 120, maxWidth: .infinity)
                Text(text(space))
                    .lineLimit(1)
                    .foregroundStyle(overflows ? Color.orange : .secondary)
                    .fixedSize()
            }
            .font(.caption)
        }
    }

    private func bar(_ space: DiskSpace) -> some View {
        GeometryReader { geo in
            let width = geo.size.width
            let total = Double(space.total)
            let usedWidth = width * Double(space.used) / total
            // Lo que se guarda, sin pasarse de lo libre; si no cabe, todo lo que queda.
            let incomingWidth = overflows ? width - usedWidth
                : width * Double(min(incoming ?? 0, space.free)) / total
            let color = overflows ? Color.orange : Color.accentColor
            ZStack(alignment: .leading) {
                Capsule().fill(Color.secondary.opacity(0.18))
                HStack(spacing: 0) {
                    Rectangle().fill(Color.secondary.opacity(0.55)).frame(width: usedWidth)
                    if incomingWidth > 0 {
                        Group {
                            if isEstimate {
                                Stripes(color: color, fillOpacity: 0.3, strokeOpacity: 0.9)
                            } else {
                                Rectangle().fill(color)
                            }
                        }
                        // Aunque sea poco, que se vea.
                        .frame(width: max(incomingWidth, 3))
                    }
                }
                .clipShape(Capsule())
            }
        }
        .frame(height: 8)
        .accessibilityHidden(true)
    }

    /// «182 GB libres de 1 TB · esta descarga 10,1 GB».
    private func text(_ space: DiskSpace) -> String {
        let free = L("\(Self.bytes(space.free)) libres de \(Self.bytes(space.total))")
        guard let detail else { return free }
        return "\(free) · \(detail)"
    }

    static func bytes(_ count: Int64) -> String {
        ByteCountFormatter.string(fromByteCount: count, countStyle: .file)
    }
}
