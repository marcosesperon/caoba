import SwiftUI

/// Texto de ejemplo de uso para cada proporción ("16:9" → "TV, YouTube"), el mismo
/// en todos los selectores de la app para que el usuario sepa para qué sirve cada una.
enum AspectUsage {
    static func hint(for label: String) -> LocalizedStringKey? {
        switch label {
        case "16:9": return "TV, YouTube"
        case "9:16": return "Reels, Shorts, TikTok, Stories"
        case "4:5": return "Publicación de Instagram"
        case "5:4": return "Publicación apaisada"
        case "3:2": return "Foto clásica horizontal (15×10)"
        case "2:3": return "Foto clásica vertical (10×15)"
        case "1:1": return "Cuadrado, Instagram"
        case "3:1", "2:1": return "Panorámica"
        case "1:3": return "Tira vertical"
        default: return nil
        }
    }

    /// "16:9 · TV, YouTube" para los selectores; solo la proporción si no hay texto.
    static func text(for label: String) -> Text {
        guard let hint = hint(for: label) else { return Text(label) }
        return Text(label) + Text(" · ") + Text(hint)
    }
}
