import Foundation
import AVFoundation

/// Etiquetas que lleva el MP4 del slideshow: un comentario («Creado con
/// CAOBA — https://caobafoto.com»), la fecha de exportación y, si el usuario
/// lo ha puesto en Ajustes, quién es el autor.
///
/// Ojo: en un `.mp4`, AVAssetWriter solo guarda las etiquetas 3GPP (descripción,
/// autor, intérprete, fecha…) y descarta en silencio las demás (software,
/// comentario de iTunes…). Por eso el nombre de CAOBA va dentro de la descripción.
public struct VideoMetadata: Sendable, Equatable {
    /// Autor del vídeo. Vacío o nil = el vídeo sale sin autor.
    public var author: String?
    /// Descripción; la app la manda ya traducida.
    public var comment: String?

    public init(author: String? = nil, comment: String? = nil) {
        self.author = author
        self.comment = comment
    }

    /// Lista para `AVAssetWriter.metadata`, ya con los identificadores 3GPP que
    /// acaban en el fichero. La fecha se pasa para poder probarlo.
    func items(date: Date = Date()) -> [AVMetadataItem] {
        var items = [Self.item(.commonIdentifierCreationDate, ISO8601DateFormatter().string(from: date))]
        if let comment = Self.cleaned(comment) {
            items.append(Self.item(.identifier3GPUserDataDescription, comment))
        }
        if let author = Self.cleaned(author) {
            // Autor e intérprete: cada reproductor enseña uno distinto como «artista».
            items.append(Self.item(.identifier3GPUserDataAuthor, author))
            items.append(Self.item(.identifier3GPUserDataPerformer, author))
        }
        return items
    }

    /// Texto sin espacios sobrantes; vacío cuenta como «no hay».
    private static func cleaned(_ text: String?) -> String? {
        guard let text = text?.trimmingCharacters(in: .whitespacesAndNewlines), !text.isEmpty else { return nil }
        return text
    }

    private static func item(_ identifier: AVMetadataIdentifier, _ value: String) -> AVMetadataItem {
        let item = AVMutableMetadataItem()
        item.identifier = identifier
        item.value = value as NSString
        item.extendedLanguageTag = "und"
        return item
    }
}
