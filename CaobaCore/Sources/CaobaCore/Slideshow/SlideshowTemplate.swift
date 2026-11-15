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
    ///
    /// Con `session`, donde los textos digan su nombre o su fecha vuelven a ser `{sesion}` y
    /// `{fecha_sesion}`. Y las tarjetas que quedan llevan un id fijo según su posición: así una
    /// plantilla recién aplicada se reconoce como la misma (al aplicar, las tarjetas cambian de id).
    public func templated(session: RenameSession? = nil) -> (template: SlideshowPreset, droppedCards: Int) {
        var t = self
        t.sortMode = nil
        t.orientationFilter = nil
        t.fileOrder = nil
        t.excludedFiles = nil
        t.durations = nil
        t.beatsPerCut = nil
        t.rhythmItems = nil

        var dropped = 0
        var fixedIDs: [String: String] = [:]
        if var text = t.text {
            text.captions = nil
            let cards = text.cards ?? []
            var kept = cards.filter(\.isAtEdge)
            dropped = cards.count - kept.count
            for index in kept.indices {
                let fixed = Self.templateCardID(index)
                fixedIDs[kept[index].id.uuidString] = fixed.uuidString
                kept[index].id = fixed
                if let session {
                    kept[index].text = Self.unfill(kept[index].text, session)
                    kept[index].subtitle = Self.unfill(kept[index].subtitle, session)
                }
            }
            if text.cards != nil { text.cards = kept }
            t.text = text
        }
        // Transiciones propias: solo las de portada, créditos y las tarjetas que se quedan (con su id fijo).
        func kept<V>(_ items: [String: V]?) -> [String: V]? {
            items.map { dict in
                var out: [String: V] = [:]
                for (key, value) in dict {
                    if Self.fixedItems.contains(key) { out[key] = value } else if let fixed = fixedIDs[key] { out[fixed] = value }
                }
                return out
            }
        }
        t.transitionsByItem = kept(t.transitionsByItem)
        t.transitionDurationsByItem = kept(t.transitionDurationsByItem)

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
            if own == nil && fromTemplate == nil { return nil }
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

    /// Lo contrario de `fill`: donde el texto diga el nombre o la fecha de la sesión, vuelven
    /// las variables. Lo retocado a mano («Alex & Sofía») no coincide y se queda tal cual.
    public static func unfill(_ text: String, _ session: RenameSession) -> String {
        var result = text
        if !session.dateText.isEmpty { result = result.replacingOccurrences(of: session.dateText, with: "{fecha_sesion}") }
        if !session.name.isEmpty { result = result.replacingOccurrences(of: session.name, with: "{sesion}") }
        return result
    }

    /// Id fijo de la tarjeta número `index` de una plantilla.
    static func templateCardID(_ index: Int) -> UUID {
        UUID(uuidString: String(format: "00000000-0000-0000-0000-%012d", index + 1))!
    }
}

private extension TextCard {
    /// Va al principio o al final del vídeo (no delante de una foto concreta).
    var isAtEdge: Bool { anchor == TextCard.startAnchor || anchor == TextCard.endAnchor }
}
