import Foundation

/// Plantillas del Slideshow: un montaje sin lo que depende de las fotos, para usarlo en otra
/// sesión (la música, la portada y los textos de Navidad, por ejemplo). Es el mismo
/// `SlideshowPreset` que se guarda en cada carpeta, con esas partes vacías.
extension SlideshowPreset {
    /// Lo que no es de ninguna foto en las transiciones por elemento.
    static let fixedItems: Set<String> = ["cover", "credits"]

    /// Plantilla sacada de este montaje. Quita orden, excluidas, duraciones, efectos y focos por
    /// foto, secuencia de collages, pies por foto, transiciones por foto y ritmo. De las tarjetas
    /// de texto solo quedan las del principio y del final: `droppedCards` cuenta las que iban
    /// delante de una foto concreta, que en otra sesión no tendrían sitio.
    public func templated() -> (template: SlideshowPreset, droppedCards: Int) {
        var t = self
        t.sortMode = nil
        t.orientationFilter = nil
        t.fileOrder = nil
        t.excludedFiles = nil
        t.durations = nil
        t.beatsPerCut = nil
        t.rhythmItems = nil

        var dropped = 0
        if var text = t.text {
            text.captions = nil
            let cards = text.cards ?? []
            let kept = cards.filter(\.isAtEdge)
            dropped = cards.count - kept.count
            if text.cards != nil { text.cards = kept }
            t.text = text
        }
        // Transiciones propias: solo las de portada, créditos y las tarjetas que se quedan.
        let keptItems = Self.fixedItems.union((t.text?.cards ?? []).map(\.id.uuidString))
        t.transitionsByItem = t.transitionsByItem?.filter { keptItems.contains($0.key) }
        t.transitionDurationsByItem = t.transitionDurationsByItem?.filter { keptItems.contains($0.key) }

        if var kb = t.kenBurns {
            kb.perPhoto = nil; kb.points = nil; kb.byFile = nil; kb.pointsByFile = nil
            t.kenBurns = kb
        }
        if var cs = t.collage {
            cs.focusPoints = nil; cs.sequence = nil; cs.holdByRow = nil
            t.collage = cs
        }
        return (t, dropped)
    }

    /// Este montaje con una plantilla aplicada: lo general sale de la plantilla (y lo que ella no
    /// tenga vuelve a sus valores de partida) y lo de las fotos se queda como está. Las tarjetas
    /// del principio y del final pasan a ser las de la plantilla (con id nuevo, para no chocar si
    /// se aplica dos veces); las que van delante de una foto se quedan. Con `session`, sus
    /// `{sesion}` y `{fecha_sesion}` se cambian por el nombre y la fecha.
    public func applying(template: SlideshowPreset, session: RenameSession? = nil) -> SlideshowPreset {
        let general = template.templated().template
        var result = general

        // Lo de las fotos, del montaje.
        result.sortMode = sortMode
        result.orientationFilter = orientationFilter
        result.fileOrder = fileOrder
        result.excludedFiles = excludedFiles
        result.durations = durations
        result.beatsPerCut = beatsPerCut
        result.rhythmItems = rhythmItems

        // Tarjetas: las de la plantilla con id nuevo y las variables cambiadas.
        var newIDs: [String: String] = [:]
        let templateCards = (general.text?.cards ?? []).map { card -> TextCard in
            var copy = card
            copy.id = UUID()
            newIDs[card.id.uuidString] = copy.id.uuidString
            if let session {
                copy.text = Self.fill(copy.text, session)
                copy.subtitle = Self.fill(copy.subtitle, session)
            }
            return copy
        }
        let ownCards = (text?.cards ?? []).filter { !$0.isAtEdge }
        var text = general.text ?? TextSection()
        text.captions = self.text?.captions
        text.cards = templateCards.filter { $0.anchor == TextCard.startAnchor } + ownCards
            + templateCards.filter { $0.anchor == TextCard.endAnchor }
        result.text = text

        // Transiciones propias: las de las fotos y tarjetas que se quedan, más las de la plantilla.
        let replaced = Self.fixedItems.union((self.text?.cards ?? []).filter(\.isAtEdge).map(\.id.uuidString))
        func merged<V>(_ own: [String: V]?, _ fromTemplate: [String: V]?) -> [String: V]? {
            var out = (own ?? [:]).filter { !replaced.contains($0.key) }
            for (key, value) in fromTemplate ?? [:] { out[newIDs[key] ?? key] = value }
            return out
        }
        result.transitionsByItem = merged(transitionsByItem, general.transitionsByItem)
        result.transitionDurationsByItem = merged(transitionDurationsByItem, general.transitionDurationsByItem)

        var kb = general.kenBurns ?? KenBurnsSection()
        kb.perPhoto = kenBurns?.perPhoto; kb.points = kenBurns?.points
        kb.byFile = kenBurns?.byFile; kb.pointsByFile = kenBurns?.pointsByFile
        result.kenBurns = kb

        var cs = general.collage ?? CollageSection()
        cs.focusPoints = collage?.focusPoints; cs.sequence = collage?.sequence; cs.holdByRow = collage?.holdByRow
        result.collage = cs
        return result
    }

    /// Cambia `{sesion}` y `{fecha_sesion}` de un texto por los de la sesión.
    public static func fill(_ text: String, _ session: RenameSession) -> String {
        text.replacingOccurrences(of: "{fecha_sesion}", with: session.dateText)
            .replacingOccurrences(of: "{sesion}", with: session.name)
    }
}

private extension TextCard {
    /// Va al principio o al final del vídeo (no delante de una foto concreta).
    var isAtEdge: Bool { anchor == TextCard.startAnchor || anchor == TextCard.endAnchor }
}
