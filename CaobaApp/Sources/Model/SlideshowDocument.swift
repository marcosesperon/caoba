import SwiftUI
import Observation
import CaobaCore

/// Efecto elegido para una foto en la interfaz: ninguno, al azar o uno concreto.
/// Transición elegida para la entrada de un elemento: una concreta o «Aleatorio».
enum TransitionChoice: Hashable, Codable {
    case kind(TransitionKind)
    case random

    var rawValue: String {
        switch self {
        case .kind(let k): return k.rawValue
        case .random: return "random"
        }
    }

    init(rawValue: String) {
        if rawValue == "random" { self = .random } else { self = TransitionKind(rawValue: rawValue).map { .kind($0) } ?? .kind(.crossfade) }
    }

    var title: LocalizedStringKey {
        switch self {
        case .random: return "Aleatorio"
        case .kind(let k):
            switch k {
            case .crossfade: return "Fundido cruzado"
            case .fadeToBlack: return "Fundido a negro"
            case .cut: return "Corte seco"
            case .slideLeft: return "Deslizar a la izquierda"
            case .slideRight: return "Deslizar a la derecha"
            case .slideUp: return "Deslizar hacia arriba"
            case .slideDown: return "Deslizar hacia abajo"
            case .zoomCross: return "Zoom cruzado"
            case .wipeLeft: return "Barrido a la izquierda"
            case .wipeRight: return "Barrido a la derecha"
            }
        }
    }

    /// El corte no tiene duración.
    var hasDuration: Bool { self != .kind(.cut) }

    static let all: [TransitionChoice] = TransitionKind.allCases.map { .kind($0) } + [.random]
}

enum EffectChoice: Hashable, Codable {
    case none, random
    case effect(KenBurnsEffect)

    var rawValue: String {
        switch self {
        case .none: return "none"
        case .random: return "random"
        case .effect(let e): return e.rawValue
        }
    }

    init(rawValue: String) {
        switch rawValue {
        case "none", "default": self = .none
        case "random": self = .random
        default: self = KenBurnsEffect(rawValue: rawValue).map { .effect($0) } ?? .none
        }
    }

    var title: LocalizedStringKey {
        switch self {
        case .none: return "Ninguno"
        case .random: return "Aleatorio"
        case .effect(let e):
            switch e {
            case .zoomIn: return "Zoom in"
            case .zoomOut: return "Zoom out"
            case .panLeft: return "Pan izquierda"
            case .panRight: return "Pan derecha"
            case .panUp: return "Pan arriba"
            case .panDown: return "Pan abajo"
            case .panUpLeft: return "Pan arriba-izq."
            case .panUpRight: return "Pan arriba-der."
            case .panDownLeft: return "Pan abajo-izq."
            case .panDownRight: return "Pan abajo-der."
            case .custom: return "Personalizado"
            }
        }
    }

    /// Etiqueta corta para la tarjeta del timeline.
    var badge: String? {
        switch self {
        case .none: return nil
        case .random: return "?"
        case .effect(let e):
            switch e {
            case .zoomIn: return "Z+"
            case .zoomOut: return "Z−"
            case .panLeft: return "←"
            case .panRight: return "→"
            case .panUp: return "↑"
            case .panDown: return "↓"
            case .panUpLeft: return "↖"
            case .panUpRight: return "↗"
            case .panDownLeft: return "↙"
            case .panDownRight: return "↘"
            case .custom: return "✎"
            }
        }
    }

    static let all: [EffectChoice] = [.none, .random] + KenBurnsEffect.allCases.map { .effect($0) }
}

extension VideoFormat {
    /// Para qué sirve cada formato, como lo describía la app antigua.
    var usageTitle: LocalizedStringKey {
        switch self {
        case .landscape16x9: return "Horizontal panorámico · TV, YouTube"
        case .portrait9x16: return "Vertical · Reels, Shorts, TikTok, Stories"
        case .portrait4x5: return "Vertical · Publicación de Instagram"
        case .landscape5x4: return "Horizontal · Publicación apaisada"
        case .portrait2x3: return "Vertical clásico"
        case .landscape3x2: return "Horizontal clásico"
        }
    }
}

/// Qué hay seleccionado en el timeline.
enum TimelineSelection: Equatable {
    case none
    case cover
    case credits
    case text(UUID)
    case photo(String)
    case track(UUID)
    case collage(UUID)
}

/// Un elemento del timeline con su posición en el tiempo.
struct TimelineItem: Identifiable, Equatable {
    enum Kind: Equatable {
        case cover(URL)
        case credits(URL)
        case photo(URL)
        case collage(CollageRow)
        /// Tarjeta de texto: pantalla propia o texto superpuesto al elemento siguiente.
        case text(TextCard)
    }

    var id: String
    var kind: Kind
    var start: Double
    var duration: Double

    var end: Double { start + duration }

    var selection: TimelineSelection {
        switch kind {
        case .cover: return .cover
        case .credits: return .credits
        case .photo(let url): return .photo(url.lastPathComponent)
        case .collage(let row): return .collage(row.id)
        case .text(let card): return .text(card.id)
        }
    }

    var isText: Bool { kind.isTextKind }
}

extension TimelineItem.Kind {
    var isTextKind: Bool { if case .text = self { return true } else { return false } }
}

/// Estado y lógica de la pantalla de Slideshow. Las vistas solo pintan y
/// llaman aquí; también gestiona la carga y el guardado del `.caoba`.
@MainActor
@Observable
final class SlideshowDocument {
    enum Mode: String, CaseIterable, Identifiable {
        case photos, collage
        var id: String { rawValue }
    }

    unowned let app: AppState

    // Vídeo
    var mode: Mode = .photos
    var format: VideoFormat = .landscape16x9 {
        didSet {
            // Los filtros de proporción que seguían al formato anterior pasan al nuevo.
            if composeSheet.filters.aspect == oldValue.label { composeSheet.filters.aspect = format.label }
            if addFilters.aspect == oldValue.label { addFilters.aspect = format.label }
        }
    }
    var durationPerPhoto = 4.0
    /// Transición por defecto y su duración; y las propias por elemento (nombre de foto, id de collage, "cover", "credits").
    var transitionChoice: TransitionChoice = .kind(.crossfade)
    var transitionDuration = SlideshowSpec.transitionSeconds
    var itemTransitions: [String: TransitionChoice] = [:]
    var itemTransitionDurations: [String: Double] = [:]
    // Texto
    /// Tarjetas de texto del timeline (título, cierre, títulos de sección…).
    var textCards: [TextCard] = []
    var captionStyle: TextStyle = .caption
    /// Patrón de pie para todas las fotos; vacío = sin pies.
    var captionPattern = ""
    /// Pie propio por elemento; cadena vacía = sin pie para ese elemento.
    var itemCaptions: [String: String] = [:]
    var coverURL: URL?
    var coverDuration = 4.0
    var creditsURL: URL?
    var creditsDuration = 4.0
    var watermarkURL: URL?
    var wmPosition: OverlayPosition = .bottomRight
    var wmSize = 30.0
    var wmOpacity = 80.0
    /// Duración propia por nombre de fichero.
    var photoDurations: [String: Double] = [:]
    // Música
    var tracks: [AudioTrack] = []
    var trackDurations: [UUID: Double] = [:]
    // Ritmo (bajo demanda: nada se analiza hasta pulsar «Ajustar al ritmo»)
    /// Golpes de cada pista, por ruta del fichero.
    var beatTracks: [String: BeatTrack] = [:]
    /// Golpes por foto elegidos; `nil` = automático por tramo.
    var beatsPerCut: Int?
    /// Elementos cuya duración la fijó el ritmo: si el usuario los toca, pasan a propios.
    var rhythmItems: Set<String> = []
    var isAnalyzingRhythm = false
    var rhythmMessage: String?
    var fadeOut = true
    var normalize = false
    var loopPlaylist = true
    // Ken Burns (por nombre de fichero)
    var kbSettings = KenBurnsSettings()
    var kbChoices: [String: EffectChoice] = [:]
    var kbPoints: [String: KenBurnsPoints] = [:]
    // Collages
    var sequence: [SequenceItem] = []
    var selectedTemplates: Set<String> = [] { didSet { if selectedTemplates != oldValue { scheduleSave() } } }
    /// Reparto, reordenar y filtros de la hoja de Componer; se guardan en el preset de la carpeta.
    var composeSheet = ComposeSheetState() { didSet { if composeSheet != oldValue { scheduleSave() } } }
    /// Filtros de la hoja de Añadir (no se guardan).
    var addFilters = TemplateFilterState()
    var composeProgress: ComposeProgress?
    private var composeTask: Task<Void, Never>?
    var reveal = 1.5
    var hold = 3.0
    var csBackground: CanvasBackground = .white
    var csGap = 10.0
    var csRadius = 0.0
    var csShadow = 50.0
    // Pantalla
    var selection: TimelineSelection = .none
    var pixelsPerSecond = 40.0
    var showPhotoPanel = false
    var isAssigning = false
    var previewURL: URL?
    private var pendingPreviewURL: URL?
    private var saveTask: Task<Void, Never>?
    private var suppressSave = false
    private var loadedFolder: URL?
    let detector = FocusDetector()

    init(app: AppState) {
        self.app = app
    }

    // MARK: - Derivados

    var files: [URL] { app.checkedFiles }

    func duration(of url: URL) -> Double {
        photoDurations[url.lastPathComponent] ?? durationPerPhoto
    }

    var rows: [CollageRow] { CollageSequenceEditor.rows(from: sequence, files: files) }

    var collageOptions: CollageSlideshow.Options {
        let longest = max(format.size.width, format.size.height)
        return CollageSlideshow.Options(reveal: reveal, hold: hold,
                                        collage: CollageOptions(longestSide: longest, gap: csGap, background: csBackground, cornerRadius: csRadius, shadowIntensity: csShadow, quality: 95))
    }

    /// Elementos del timeline en orden, sin tiempos todavía.
    private var orderedKinds: [(id: String, kind: TimelineItem.Kind, duration: Double)] {
        var base: [(String, TimelineItem.Kind, Double)] = []
        if let coverURL { base.append(("cover", .cover(coverURL), coverDuration)) }
        switch mode {
        case .photos:
            for url in files { base.append((url.lastPathComponent, .photo(url), duration(of: url))) }
        case .collage:
            for row in rows {
                base.append((row.id.uuidString, .collage(row), CollageSlideshow.duration(of: row, options: collageOptions)))
            }
        }
        if let creditsURL { base.append(("credits", .credits(creditsURL), creditsDuration)) }
        // Las tarjetas de texto se intercalan ante el elemento al que están ancladas;
        // las que estén ante un elemento que ya no existe van al final.
        let knownIds = Set(base.map(\.0))
        func cards(at anchor: String) -> [(String, TimelineItem.Kind, Double)] {
            textCards.filter { $0.anchor == anchor }.map { ($0.id.uuidString, .text($0), $0.background == nil ? 0 : $0.duration) }
        }
        var result = cards(at: TextCard.startAnchor)
        for element in base {
            result.append(contentsOf: cards(at: element.0))
            result.append(element)
        }
        result.append(contentsOf: textCards.filter { $0.anchor != TextCard.startAnchor && !knownIds.contains($0.anchor) }
            .map { ($0.id.uuidString, .text($0), $0.background == nil ? 0 : $0.duration) })
        return result
    }

    // MARK: - Tarjetas de texto

    func textCard(_ id: UUID) -> TextCard? { textCards.first { $0.id == id } }

    func updateTextCard(_ card: TextCard) {
        guard let i = textCards.firstIndex(where: { $0.id == card.id }) else { return }
        textCards[i] = card
    }

    /// Nueva tarjeta antes o después del elemento seleccionado (si lo hay) o al final; queda seleccionada.
    @discardableResult
    func addTextCard(after: Bool = false) -> UUID {
        var card = TextCard(text: L("Título"), anchor: TextCard.endAnchor)
        let list = items
        if let index = list.firstIndex(where: { $0.selection == selection }) {
            let item = list[index]
            if after {
                // Ante el siguiente elemento que no sea tarjeta; si no hay, al final.
                card.anchor = list[(index + 1)...].first { !$0.isText }?.id ?? TextCard.endAnchor
            } else if case .text(let selected) = item.kind {
                card.anchor = selected.anchor   // en el mismo sitio que la tarjeta seleccionada
            } else {
                card.anchor = item.id
            }
        }
        if after, case .text(let selected) = list.first(where: { $0.selection == selection })?.kind {
            // Tras otra tarjeta: mismo ancla, justo detrás de ella.
            card.anchor = selected.anchor
            textCards.append(card)
            moveTextCard(card.id, afterCard: selected.id)
        } else {
            textCards.append(card)
        }
        // Cada tarjeta lleva su estilo: la nueva copia el de la tarjeta de texto vecina.
        if let i = textCards.firstIndex(where: { $0.id == card.id }) { textCards[i].style = inheritedStyle(for: card.id) }
        selection = .text(card.id)
        return card.id
    }

    /// Estilo de la tarjeta de texto anterior en el timeline, si no de la siguiente, y si no hay
    /// ninguna, el de la app.
    private func inheritedStyle(for id: UUID) -> TextStyle {
        let texts = items.compactMap { item -> TextCard? in if case .text(let c) = item.kind { return c } else { return nil } }
        guard let index = texts.firstIndex(where: { $0.id == id }) else { return .title }
        let previous = texts[..<index].last { $0.style != nil }
        let next = texts[(index + 1)...].first { $0.style != nil }
        return previous?.style ?? next?.style ?? .title
    }

    /// Copia el estilo de una tarjeta (letra, colocación y animaciones) a todas las demás.
    func applyStyleToAllCards(from id: UUID) {
        guard let style = textCard(id)?.style else { return }
        for i in textCards.indices { textCards[i].style = style }
    }

    /// Coloca la tarjeta justo después de otra tarjeta (mismo ancla, detrás de ella).
    func moveTextCard(_ id: UUID, afterCard targetId: UUID) {
        guard id != targetId, let from = textCards.firstIndex(where: { $0.id == id }), let target = textCards.first(where: { $0.id == targetId }) else { return }
        var card = textCards.remove(at: from)
        card.anchor = target.anchor
        let to = (textCards.firstIndex(where: { $0.id == targetId }) ?? textCards.count - 1) + 1
        textCards.insert(card, at: min(to, textCards.count))
    }

    func removeTextCard(_ id: UUID) {
        textCards.removeAll { $0.id == id }
        if selection == .text(id) { selection = .none }
    }

    /// Coloca la tarjeta ante un elemento del timeline (foto, collage, portada o créditos).
    func moveTextCard(_ id: UUID, beforeElement elementId: String) {
        guard let i = textCards.firstIndex(where: { $0.id == id }) else { return }
        textCards[i].anchor = elementId
        textCards.append(textCards.remove(at: i))   // la última ante ese elemento
    }

    /// Coloca la tarjeta justo antes de otra tarjeta (mismo ancla, delante de ella).
    func moveTextCard(_ id: UUID, beforeCard targetId: UUID) {
        guard id != targetId, let from = textCards.firstIndex(where: { $0.id == id }), let target = textCards.first(where: { $0.id == targetId }) else { return }
        var card = textCards.remove(at: from)
        card.anchor = target.anchor
        let to = textCards.firstIndex(where: { $0.id == targetId }) ?? textCards.count
        textCards.insert(card, at: to)
    }

    // MARK: - Texto

    /// Pie de un elemento: propio, del patrón, o ninguno.
    func caption(for id: String, index: Int, total: Int, info: RenameSourceInfo?, name: String? = nil) -> String? {
        if let own = itemCaptions[id] { return own.isEmpty ? nil : own }
        let pattern = captionPattern.trimmingCharacters(in: .whitespaces)
        guard !pattern.isEmpty else { return nil }
        var text = pattern.replacingOccurrences(of: "{total}", with: String(total))
        if let info {
            let date = info.date.map { Self.captionDateFormatter.string(from: $0) } ?? ""
            text = text.replacingOccurrences(of: "{fecha}", with: date)
            text = Renamer.expand(pattern: text, info: info, sequence: String(index))
        } else {
            // Collages: no hay fichero; {nombre} es la plantilla y el resto se queda vacío.
            text = text.replacingOccurrences(of: "{fecha}", with: "").replacingOccurrences(of: "{n}", with: String(index))
            text = text.replacingOccurrences(of: "{nombre}", with: name ?? "").replacingOccurrences(of: "{camara}", with: "").replacingOccurrences(of: "{objetivo}", with: "")
        }
        // Sin separadores colgando por variables vacías ("1 de 10 ·").
        var clean = text.trimmingCharacters(in: .whitespaces)
        while let last = clean.last, "·-–—|,;:/".contains(last) { clean = String(clean.dropLast()).trimmingCharacters(in: .whitespaces) }
        while let first = clean.first, "·-–—|,;:/".contains(first) { clean = String(clean.dropFirst()).trimmingCharacters(in: .whitespaces) }
        return clean.isEmpty ? nil : clean
    }

    private static let captionDateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "dd/MM/yyyy"
        return f
    }()

    /// Fondo liso de una tarjeta de título o cierre como imagen temporal; el texto
    /// va aparte, como texto superpuesto, para poder animarlo.
    private func renderCardBackground(_ background: CanvasBackground) throws -> URL {
        let image = try TextRenderer.card(lines: [], style: .title, background: background.fill, canvas: format.size)
        let url = try TempFiles.makeFileURL(extension: "jpg")
        try ImageWriter.write(image, to: url, encoding: ImageEncoding(format: .jpeg, quality: 95))
        return url
    }

    /// «Aleatorio» se convierte en una animación concreta al generar.
    private func resolved(_ style: TextStyle, generator: inout some RandomNumberGenerator) -> TextStyle {
        var copy = style
        if copy.animation == .random { copy.animation = TextAnimation.randomPool.randomElement(using: &generator) ?? .fade }
        if copy.exitAnimation == .random { copy.exitAnimation = TextAnimation.randomPool.randomElement(using: &generator) ?? .fade }
        return copy
    }

    /// Tarjeta de título o cierre: fondo liso y el texto entrando cuando la tarjeta ya está en pantalla
    /// (tras su transición de entrada) y saliendo antes de que la tarjeta se vaya.
    private func textCardPhoto(lines: [String], duration: Double, id: String, background: CanvasBackground, style: TextStyle, delayed: Bool, generator: inout some RandomNumberGenerator) throws -> SlideshowPhoto {
        let entry = entryDuration(for: id)
        let delay = (delayed && entry < duration) ? entry : 0
        // Sin salida, el texto debe seguir mientras la tarjeta se funde con lo siguiente: se alarga más que cualquier transición.
        let extra = style.resolvedExit == .none ? Self.carryOverExtra : 0
        var photo = SlideshowPhoto(url: try renderCardBackground(background), duration: duration,
                                   transition: resolvedTransition(for: id, generator: &generator), transitionDuration: entry,
                                   overlay: TextOverlay(lines: lines, style: style, duration: duration - delay + extra, delay: delay))
        // El fondo es un fichero temporal: en el progreso se enseña el texto de la tarjeta.
        photo.label = lines.first.map { L("Texto · \($0)") } ?? L("Texto")
        return photo
    }

    /// Margen con el que se alarga un texto sin salida para que siga durante la transición al elemento siguiente.
    private static let carryOverExtra = 5.0

    /// Mismo estilo sin animación de entrada (el texto ya estaba) o sin salida (sigue en el siguiente elemento).
    private func style(_ base: TextStyle, entry: Bool, exit: Bool) -> TextStyle {
        var copy = base
        if !entry { copy.animation = .none }
        if !exit { copy.exitAnimation = .none }
        return copy
    }

    /// Pone un texto superpuesto sobre un grupo de fotos consecutivas (los pasos de un collage), encadenando el desfase.
    private func spread(_ overlay: TextOverlay, over photos: inout [SlideshowPhoto], range: Range<Int>) {
        var offset = 0.0
        for i in range {
            var copy = overlay
            copy.offset = offset
            photos[i].overlay = copy
            offset += photos[i].duration
        }
    }


    /// Transición de entrada de un elemento (propia o por defecto).
    func transitionChoice(for id: String) -> TransitionChoice { itemTransitions[id] ?? transitionChoice }

    /// Duración de entrada efectiva de un elemento (0 si es un corte).
    func entryDuration(for id: String) -> Double {
        guard transitionChoice(for: id).hasDuration else { return 0 }
        return itemTransitionDurations[id] ?? transitionDuration
    }

    /// Resuelve «Aleatorio» a una transición concreta.
    func resolvedTransition(for id: String, generator: inout some RandomNumberGenerator) -> TransitionKind {
        switch transitionChoice(for: id) {
        case .kind(let k): return k
        case .random: return TransitionKind.randomPool.randomElement(using: &generator) ?? .crossfade
        }
    }

    var timeline: SlideshowTimeline {
        let kinds = orderedKinds
        return SlideshowTimeline(durations: kinds.map(\.duration), transitions: kinds.map { entryDuration(for: $0.id) })
    }

    var items: [TimelineItem] {
        let tl = timeline
        return orderedKinds.enumerated().map { index, entry in
            TimelineItem(id: entry.id, kind: entry.kind, start: tl.startTime(ofPhoto: index), duration: entry.duration)
        }
    }

    var totalDuration: Double { timeline.totalDuration }

    /// Hasta dónde llega el audio (la pista que más tarde termina), aunque el
    /// vídeo acabe antes. El timeline se dibuja hasta aquí para ver las pistas enteras.
    var audioExtent: Double {
        tracks.map { track in
            let length = trackDurations[track.id].map { track.effectiveDuration(assetDuration: $0) } ?? 0
            return effectiveStart(of: track) + length
        }.max() ?? 0
    }

    var timelineExtent: Double { max(totalDuration, audioExtent) }

    /// Segmentos de audio tal como los calculará el motor (para dibujar los carriles).
    var audioSegments: [AudioSegment] {
        let durations = tracks.map { trackDurations[$0.id] ?? totalDuration }
        return AudioPlan.build(tracks: tracks, durations: durations, gains: nil, timeline: timeline, fadeOutAtEnd: false, loopPlaylist: loopPlaylist)
    }

    /// Inicio efectivo de una pista (resolviendo "tras la anterior").
    func effectiveStart(of track: AudioTrack) -> Double {
        audioSegments.first { $0.url == track.url && $0.trimStart == track.trimStart }?.start ?? 0
    }

    /// Puntos a los que se imanta un bloque de música al arrastrarlo.
    var snapPoints: [Double] {
        var points: [Double] = [0, totalDuration]
        points.append(contentsOf: items.map(\.start))
        for track in tracks {
            let start = effectiveStart(of: track)
            let duration = trackDurations[track.id].map { track.effectiveDuration(assetDuration: $0) } ?? 0
            points.append(start + duration)
        }
        return points
    }

    var canGenerate: Bool {
        guard app.destinationFile != nil else { return false }
        switch mode {
        case .photos: return !files.isEmpty
        case .collage: return !rows.isEmpty
        }
    }

    var canPreview: Bool {
        switch mode {
        case .photos: return !files.isEmpty
        case .collage: return !rows.isEmpty
        }
    }

    // MARK: - Edición

    func setDuration(_ seconds: Double, for item: TimelineItem) {
        // Un cambio a mano convierte la duración en propia: el ritmo ya no la pisa.
        rhythmItems.remove(item.id)
        let value = max(0.5, min(60, (seconds * 2).rounded() / 2))
        switch item.kind {
        case .cover: coverDuration = value
        case .credits: creditsDuration = value
        case .text(let card):
            if var updated = textCard(card.id) { updated.duration = value; updateTextCard(updated) }
        case .photo(let url): photoDurations[url.lastPathComponent] = value
        case .collage(let row):
            // La duración total de un collage se ajusta a través de su "mantener":
            // lo que no es aparición de fotos ni lienzo vacío.
            let fixed = CollageSlideshow.emptyFrameSeconds + reveal * Double(row.template.photos)
            setHold(max(0, value - fixed), for: row.id)
        }
    }

    func setHold(_ seconds: Double?, for id: UUID) {
        guard let i = sequence.firstIndex(where: { $0.id == id }) else { return }
        sequence[i].hold = seconds.map { max(0, min(60, ($0 * 2).rounded() / 2)) }
    }

    func equalizeDurations() {
        photoDurations = [:]
        for i in sequence.indices { sequence[i].hold = nil }
        rhythmItems = []
    }

    // MARK: - Ritmo

    /// Golpes en el tiempo del vídeo según lo que suena en cada momento (para la regla y el ajuste).
    var videoBeats: [VideoBeat] {
        guard !beatTracks.isEmpty else { return [] }
        return RhythmPlanner.videoBeats(segments: audioSegments, tracks: beatTracks)
    }

    /// Analiza las pistas que falten y ajusta las duraciones para que cada
    /// cambio caiga en un golpe. Respeta las duraciones propias del usuario.
    func adjustToRhythm() async {
        guard !tracks.isEmpty else { rhythmMessage = L("Añade una pista de música para ajustar al ritmo."); return }
        isAnalyzingRhythm = true
        rhythmMessage = nil
        defer { isAnalyzingRhythm = false }
        let pending = Array(Set(tracks.map(\.url.path))).filter { beatTracks[$0] == nil }
        if !pending.isEmpty {
            await withTaskGroup(of: (String, BeatTrack?).self) { group in
                for path in pending {
                    group.addTask { (path, try? await BeatDetector.analyze(url: URL(fileURLWithPath: path))) }
                }
                for await (path, track) in group { if let track { beatTracks[path] = track } }
            }
        }
        guard tracks.contains(where: { beatTracks[$0.url.path]?.isReliable == true }) else {
            rhythmMessage = L("No se ha encontrado un ritmo claro en la música.")
            return
        }
        // Dos pasadas: las pistas que empiezan en una foto se mueven con las duraciones nuevas.
        applyRhythm()
        applyRhythm()
    }

    private func applyRhythm() {
        let beats = videoBeats
        let entries = orderedKinds
        let items: [RhythmItem] = entries.map { entry in
            switch entry.kind {
            case .cover, .credits, .text:
                return RhythmItem(fixedDuration: entry.duration)
            case .photo(let url):
                let own = photoDurations[url.lastPathComponent] != nil && !rhythmItems.contains(entry.id)
                return RhythmItem(fixedDuration: own ? entry.duration : nil, minimum: 1, maximum: 15)
            case .collage(let row):
                let own = row.hold != nil && !rhythmItems.contains(entry.id)
                // Un collage no puede durar menos que su aparición de fotos.
                let fixed = CollageSlideshow.emptyFrameSeconds + reveal * Double(row.template.photos)
                return RhythmItem(fixedDuration: own ? entry.duration : nil, minimum: max(1, fixed), maximum: max(15, fixed + 15))
            }
        }
        let target = mode == .collage ? CollageSlideshow.emptyFrameSeconds + reveal * 3 + hold : durationPerPhoto
        let durations = RhythmPlanner.plan(beats: beats, items: items, target: target, beatsPerCut: beatsPerCut,
                                           entryTransitions: entries.map { entryDuration(for: $0.id) })
        for (entry, duration) in zip(entries, durations) where items[entries.firstIndex { $0.id == entry.id }!].fixedDuration == nil {
            switch entry.kind {
            case .photo(let url):
                photoDurations[url.lastPathComponent] = (duration * 100).rounded() / 100
            case .collage(let row):
                let fixed = CollageSlideshow.emptyFrameSeconds + reveal * Double(row.template.photos)
                if let i = sequence.firstIndex(where: { $0.id == row.id }) { sequence[i].hold = max(0, ((duration - fixed) * 100).rounded() / 100) }
            case .cover, .credits, .text:
                break
            }
            rhythmItems.insert(entry.id)
        }
        scheduleSave()
    }

    func toggleExcluded(_ url: URL) {
        if let file = app.files.first(where: { $0.url == url }) { app.toggle(file) }
    }

    func movePhoto(named moved: String, before target: String) {
        guard let from = app.files.firstIndex(where: { $0.name == moved }), let to = app.files.firstIndex(where: { $0.name == target }) else { return }
        app.moveFiles(from: IndexSet(integer: from), to: to > from ? to + 1 : to)
    }

    func choice(for url: URL) -> EffectChoice { kbChoices[url.lastPathComponent] ?? .none }

    func setChoice(_ choice: EffectChoice, for url: URL) { kbChoices[url.lastPathComponent] = choice }

    func assignAll(_ choice: EffectChoice) {
        for url in files { kbChoices[url.lastPathComponent] = choice }
    }

    /// Efecto según la proporción de cada foto y foco detectado con Vision.
    func assignAuto(_ focusMode: FocusMode) {
        isAssigning = true
        let snapshot = files
        let videoAspect = format.aspectRatio
        Task {
            var generator = SystemRandomNumberGenerator()
            for url in snapshot {
                let name = url.lastPathComponent
                let aspect = ImageIOHelpers.displaySize(of: url)?.aspectRatio ?? 1
                let focus = await detector.focus(for: url, mode: focusMode).point
                kbChoices[name] = .effect(KenBurns.suggestedEffect(imageAspect: aspect, videoAspect: videoAspect, generator: &generator))
                var points = kbPoints[name] ?? KenBurnsPoints()
                points.startFocus = focus
                points.endFocus = focus
                kbPoints[name] = points
            }
            isAssigning = false
        }
    }

    // MARK: Música

    func addTracks(_ urls: [URL]) {
        for url in urls {
            let track = AudioTrack(url: url)
            tracks.append(track)
            Task { if let d = try? await AudioPlan.duration(of: url) { trackDurations[track.id] = d } }
        }
    }

    func removeTrack(_ id: UUID) {
        tracks.removeAll { $0.id == id }
        if case .track(let selected) = selection, selected == id { selection = .none }
    }

    func setStart(_ seconds: Double, for id: UUID) {
        guard let i = tracks.firstIndex(where: { $0.id == id }) else { return }
        tracks[i].startMode = .atTime(max(0, min(totalDuration, seconds)))
    }

    /// Arrastre del borde izquierdo: cambia el punto de entrada de la canción y
    /// mueve el inicio para que el borde derecho se quede donde estaba.
    func trimLeading(by delta: Double, for id: UUID) {
        guard let i = tracks.firstIndex(where: { $0.id == id }), let asset = trackDurations[id] else { return }
        let track = tracks[i]
        let maxStart = (track.trimEnd ?? asset) - 1
        let newTrim = max(0, min(maxStart, track.trimStart + delta))
        let applied = newTrim - track.trimStart
        let currentStart = effectiveStart(of: track)
        tracks[i].trimStart = newTrim
        tracks[i].startMode = .atTime(max(0, currentStart + applied))
    }

    func trimTrailing(by delta: Double, for id: UUID) {
        guard let i = tracks.firstIndex(where: { $0.id == id }), let asset = trackDurations[id] else { return }
        let track = tracks[i]
        let current = track.trimEnd ?? asset
        let newEnd = max(track.trimStart + 1, min(asset, current + delta))
        tracks[i].trimEnd = newEnd >= asset - 0.25 ? nil : newEnd
    }

    // MARK: Collages

    var visibleTemplatesForAdd: [CollageTemplate] {
        let assigned = rows.reduce(0) { $0 + $1.files.count }
        return CollageTemplates.filter(includeOverlap: true).filter { $0.photos <= files.count - assigned }
    }

    func compose() {
        let templates = selectedTemplates.compactMap(CollageTemplates.template(id:))
        selection = .none
        guard composeSheet.mode == .content else {
            let (grouped, _) = CollageRenderer.group(files: files, templates: templates, mode: .random)
            sequence = grouped.map { SequenceItem(templateID: $0.template.id, focusPoints: $0.focusPoints) }
            return
        }
        // Según el contenido: analiza, reordena la lista de la app y deja el foco puesto.
        composeTask?.cancel()
        let snapshot = files
        composeProgress = ComposeProgress(done: 0, total: snapshot.count)
        composeTask = Task {
            defer { composeProgress = nil; composeTask = nil }
            do {
                let result = try await ContentComposition.compose(files: snapshot, templates: templates, allowReorder: composeSheet.allowReorder, detector: detector) { done in
                    self.composeProgress = ComposeProgress(done: done, total: snapshot.count)
                }
                app.reorderCheckedFiles(to: result.order)
                sequence = result.sequence
            } catch {
                // Cancelado: se deja todo como estaba.
            }
        }
    }

    func cancelCompose() { composeTask?.cancel() }

    func addTemplate(_ template: CollageTemplate) {
        let item = SequenceItem(templateID: template.id, focusPoints: Array(repeating: nil, count: template.photos))
        sequence.append(item)
        selection = .collage(item.id)
    }

    func removeCollage(_ id: UUID) {
        sequence.removeAll { $0.id == id }
        if case .collage(let selected) = selection, selected == id { selection = .none }
    }

    func moveCollage(_ moved: UUID, before target: UUID) {
        guard let from = sequence.firstIndex(where: { $0.id == moved }), let to = sequence.firstIndex(where: { $0.id == target }) else { return }
        sequence.move(fromOffsets: IndexSet(integer: from), toOffset: to > from ? to + 1 : to)
    }

    func pruneSequence() {
        var count = 0
        sequence = sequence.filter { item in
            guard let t = item.template, count + t.photos <= files.count else { return false }
            count += t.photos
            return true
        }
    }

    func adjustFocus(_ focusMode: FocusMode) {
        let snapshot = rows
        isAssigning = true
        Task {
            for row in snapshot {
                guard let itemIndex = sequence.firstIndex(where: { $0.id == row.id }) else { continue }
                for (cell, url) in row.files.enumerated() where !sequence[itemIndex].manualCells.contains(cell) {
                    let result = await detector.focus(for: url, mode: focusMode)
                    if sequence.indices.contains(itemIndex), sequence[itemIndex].focusPoints.indices.contains(cell) {
                        sequence[itemIndex].focusPoints[cell] = focusMode == .center ? nil : result.point
                    }
                }
            }
            isAssigning = false
        }
    }

    // MARK: Teclado

    func deleteSelection() {
        switch selection {
        case .none: break
        case .cover: coverURL = nil; selection = .none
        case .credits: creditsURL = nil; selection = .none
        case .text(let id): removeTextCard(id)
        case .photo(let name): if let url = files.first(where: { $0.lastPathComponent == name }) { toggleExcluded(url) }; selection = .none
        case .track(let id): removeTrack(id)
        case .collage(let id): removeCollage(id)
        }
    }

    func moveSelection(_ delta: Int) {
        let list = items
        guard !list.isEmpty else { return }
        let current = list.firstIndex { $0.selection == selection } ?? (delta > 0 ? -1 : list.count)
        let next = min(list.count - 1, max(0, current + delta))
        selection = list[next].selection
    }

    // MARK: - Generación

    /// Fotos del vídeo (modo fotos) y, en paralelo, el id del elemento del timeline al que pertenece cada una.
    private func makePhotos(limit: Int? = nil) -> (photos: [SlideshowPhoto], owners: [String]) {
        var generator = SystemRandomNumberGenerator()
        var list = files
        if let limit { list = Array(list.prefix(limit)) }
        // Datos de cada foto solo si el patrón de pie los necesita.
        let infos = captionPattern.isEmpty ? [] : Renamer.gatherInfo(files: list, pattern: captionPattern.replacingOccurrences(of: "{fecha}", with: "YYYY"), needsDates: captionPattern.contains("{fecha}"))
        var photos: [SlideshowPhoto] = list.enumerated().map { index, url in
            let name = url.lastPathComponent
            let effect: KenBurnsEffect?
            switch kbChoices[name] ?? .none {
            case .none: effect = nil
            case .random: effect = KenBurnsEffect.randomPool.randomElement(using: &generator)
            case .effect(let e): effect = e
            }
            return SlideshowPhoto(url: url, duration: duration(of: url), kenBurns: effect, points: kbPoints[name],
                                  transition: resolvedTransition(for: name, generator: &generator), transitionDuration: entryDuration(for: name),
                                  caption: caption(for: name, index: index + 1, total: list.count, info: infos.indices.contains(index) ? infos[index] : nil))
        }
        var owners = list.map(\.lastPathComponent)
        if let coverURL { photos.insert(coverPhoto(coverURL, duration: coverDuration, id: "cover", generator: &generator), at: 0); owners.insert("cover", at: 0) }
        if let creditsURL { photos.append(coverPhoto(creditsURL, duration: creditsDuration, id: "credits", generator: &generator)); owners.append("credits") }
        return (photos, owners)
    }

    /// Tarjetas de texto sobre la lista ya montada (fotos o collages).
    /// `owners[i]` es el id del elemento del timeline al que pertenece `photos[i]` (los pasos
    /// de un collage comparten dueño). Devuelve la lista final con las tarjetas intercaladas.
    private func applyText(to photos: [SlideshowPhoto], owners: [String], generator: inout some RandomNumberGenerator) throws -> [SlideshowPhoto] {
        var photos = photos
        // Rango de fotos de cada elemento.
        var ranges: [String: Range<Int>] = [:]
        for (i, owner) in owners.enumerated() {
            if let r = ranges[owner] { ranges[owner] = r.lowerBound..<(i + 1) } else { ranges[owner] = i..<(i + 1) }
        }
        let kinds = orderedKinds
        func available(_ r: Range<Int>) -> Double { photos[r].reduce(0) { $0 + $1.duration } }

        var cardPhotos: [UUID: SlideshowPhoto] = [:]
        for (i, kind) in kinds.enumerated() {
            guard case .text(let card) = kind.kind, !card.lines.isEmpty else { continue }
            let style = resolved(card.style ?? .title, generator: &generator)
            let next = kinds[(i + 1)...].first { !$0.kind.isTextKind }.flatMap { ranges[$0.id] }
            let previous = kinds[..<i].last { !$0.kind.isTextKind }.flatMap { ranges[$0.id] }
            guard let background = card.background else {
                // Sin pantalla propia: el texto va sobre el elemento siguiente (o el anterior si es la última).
                guard let r = next ?? previous else { continue }
                let total = min(TextPhase.totalDuration(style: style, hold: card.duration), available(r))
                spread(TextOverlay(lines: card.lines, style: style, duration: total), over: &photos, range: r)
                continue
            }
            let carryNext = card.carryNext && next != nil
            let carryPrevious = card.carryPrevious && previous != nil
            cardPhotos[card.id] = try textCardPhoto(lines: card.lines, duration: card.duration, id: card.id.uuidString, background: background,
                                                    style: self.style(style, entry: !carryPrevious, exit: !carryNext), delayed: !carryPrevious, generator: &generator)
            if carryNext, let r = next {
                // El texto no sale de la tarjeta: sigue quieto mientras se funde con el siguiente y sale después sobre él.
                let continued = self.style(style, entry: false, exit: true)
                let total = min(TextPhase.totalDuration(style: continued, hold: card.carryNextSeconds), available(r))
                spread(TextOverlay(lines: card.lines, style: continued, duration: total), over: &photos, range: r)
            }
            if carryPrevious, let r = previous {
                // El texto aparece sobre el anterior y se queda mientras este se funde con la tarjeta.
                let starting = self.style(style, entry: true, exit: false)
                let wanted = (starting.animation != .none ? starting.animationDuration : 0) + card.carryPreviousSeconds
                let delay = max(0, available(r) - wanted)
                spread(TextOverlay(lines: card.lines, style: starting, duration: available(r) - delay + Self.carryOverExtra, delay: delay), over: &photos, range: r)
            }
        }

        // Lista final: cada elemento con sus fotos y cada tarjeta con pantalla en su sitio
        // (en la vista previa solo entran las tarjetas pegadas a algún elemento incluido).
        var result: [SlideshowPhoto] = []
        for (i, kind) in kinds.enumerated() {
            if case .text(let card) = kind.kind {
                let next = kinds[(i + 1)...].first { !$0.kind.isTextKind }.flatMap { ranges[$0.id] }
                let previous = kinds[..<i].last { !$0.kind.isTextKind }.flatMap { ranges[$0.id] }
                if let photo = cardPhotos[card.id], next != nil || previous != nil { result.append(photo) }
            } else if let r = ranges[kind.id] {
                result.append(contentsOf: photos[r])
            }
        }
        // Pies con animación aleatoria: una distinta por foto (o por collage: sus pasos comparten la del primero).
        if captionStyle.animation == .random {
            var current: TextAnimation?
            for i in result.indices where result[i].caption != nil && result[i].captionAnimation == nil {
                if result[i].captionEntry || current == nil { current = TextAnimation.randomPool.randomElement(using: &generator) }
                result[i].captionAnimation = current
            }
        }
        return result
    }

    /// Portada o créditos como foto del vídeo, con su transición resuelta.
    private func coverPhoto(_ url: URL, duration: Double, id: String, generator: inout some RandomNumberGenerator) -> SlideshowPhoto {
        SlideshowPhoto(url: url, duration: duration, transition: resolvedTransition(for: id, generator: &generator), transitionDuration: entryDuration(for: id))
    }

    private func makeSpec(output: URL, preview: Bool) -> SlideshowSpec {
        var audio = AudioOptions(tracks: tracks, fadeOut: fadeOut, normalize: normalize, loopPlaylist: loopPlaylist)
        if preview { audio.normalize = false }
        var spec = SlideshowSpec(photos: [], format: format, transition: transitionChoice.hasDuration,
                                 watermark: watermarkURL.map { VideoWatermark(url: $0, position: wmPosition, sizePercent: wmSize, opacity: wmOpacity) },
                                 audio: audio, kenBurns: kbSettings, output: output, preview: preview)
        // Cada foto lleva ya su transición resuelta; esto cubre lo que no la tenga (p. ej. pasos de collage).
        if case .kind(let k) = transitionChoice { spec.defaultTransition = k }
        spec.defaultTransitionDuration = transitionDuration
        spec.captionStyle = captionStyle
        spec.metadata = VideoMetadata(author: Preferences.author, comment: L("Creado con CAOBA — https://caobafoto.com"))
        if spec.captionStyle.animation == .random { spec.captionStyle.animation = .fade }   // las fotos llevan la suya resuelta
        if spec.captionStyle.exitAnimation == .random { spec.captionStyle.exitAnimation = TextAnimation.randomPool.randomElement() ?? .fade }
        return spec
    }

    func preview() {
        guard let url = try? TempFiles.makeFileURL(extension: "mp4") else { return }
        pendingPreviewURL = url
        launch(output: url, preview: true)
    }

    func generate() {
        guard let output = app.destinationFile else { return }
        launch(output: output, preview: false)
    }

    /// Solo para pruebas desde línea de comandos: vista previa a un fichero concreto.
    func generateForTest(to url: URL) {
        launch(output: url, preview: true)
    }

    private func launch(output: URL, preview: Bool) {
        let mode = mode
        let fixedRows = rows
        let csOptions = collageOptions
        let (photoList, photoOwners) = makePhotos(limit: preview ? 10 : nil)
        let coverURL = coverURL, creditsURL = creditsURL, coverDuration = coverDuration, creditsDuration = creditsDuration
        let baseSpec = makeSpec(output: output, preview: preview)
        // Transiciones de entrada de cada collage, portada y créditos, resueltas aquí (estado del documento).
        var generator = SystemRandomNumberGenerator()
        let collageEntries = fixedRows.map { (resolvedTransition(for: $0.id.uuidString, generator: &generator), entryDuration(for: $0.id.uuidString)) }
        let coverEntry = (resolvedTransition(for: "cover", generator: &generator), entryDuration(for: "cover"))
        let creditsEntry = (resolvedTransition(for: "credits", generator: &generator), entryDuration(for: "credits"))
        let collageLabels = fixedRows.enumerated().map { L("Collage \($0 + 1) · \($1.template.name)") }
        let collageCaptions = fixedRows.enumerated().map { caption(for: $1.id.uuidString, index: $0 + 1, total: fixedRows.count, info: nil, name: $1.template.name) }
        // Las tarjetas de texto se resuelven en el hilo principal cuando la lista está montada.
        let textApplier: @Sendable ([SlideshowPhoto], [String]) async throws -> [SlideshowPhoto] = { list, owners in
            try await MainActor.run {
                var generator = SystemRandomNumberGenerator()
                return try self.applyText(to: list, owners: owners, generator: &generator)
            }
        }
        app.jobRunner.run(openURL: preview ? nil : output, quietOnSuccess: preview) { progress in
            var photos = photoList
            var owners = photoOwners
            var frameDir: URL?
            if mode == .collage {
                let dir = try TempFiles.makeJobDirectory(prefix: "csshow")
                frameDir = dir
                let limited = preview ? Array(fixedRows.prefix(3)) : fixedRows
                photos = try await CollageSlideshow.makePhotos(rows: limited, options: csOptions, directory: dir, progress: progress)
                owners = limited.flatMap { row in Array(repeating: row.id.uuidString, count: row.template.photos + 1) }
                // El primer paso de cada collage entra con la transición del collage.
                var index = 0
                for (r, row) in limited.enumerated() where photos.indices.contains(index) {
                    photos[index].transition = collageEntries[r].0
                    photos[index].transitionDuration = collageEntries[r].1
                    index += row.template.photos + 1
                }
                // Pie de cada collage en todos sus pasos: entra en el primero y sale en el último.
                // Cada paso es un fichero temporal: en el progreso sale «Collage n · plantilla».
                var step = 0
                for (r, row) in limited.enumerated() {
                    let text = collageCaptions[r]
                    let label = collageLabels[r]
                    let steps = row.template.photos + 1
                    for k in 0..<steps where photos.indices.contains(step) {
                        photos[step].label = label
                        photos[step].caption = text
                        photos[step].captionEntry = k == 0
                        photos[step].captionExit = k == steps - 1
                        step += 1
                    }
                }
                if let coverURL { photos.insert(SlideshowPhoto(url: coverURL, duration: coverDuration, transition: coverEntry.0, transitionDuration: coverEntry.1), at: 0); owners.insert("cover", at: 0) }
                if let creditsURL { photos.append(SlideshowPhoto(url: creditsURL, duration: creditsDuration, transition: creditsEntry.0, transitionDuration: creditsEntry.1)); owners.append("credits") }
            }
            photos = try await textApplier(photos, owners)
            defer { if let frameDir { TempFiles.remove(frameDir) } }
            var spec = baseSpec
            spec.photos = photos
            try await SlideshowRenderer.generate(spec, progress: progress)
            return BatchSummary(processed: photos.count)
        }
    }

    /// La vista lo llama cuando termina el trabajo, para abrir la preview si la había.
    func jobFinished() {
        if let url = pendingPreviewURL, FileManager.default.fileExists(atPath: url.path) {
            previewURL = url
        }
        pendingPreviewURL = nil
    }

    static func formatDuration(_ seconds: Double) -> String {
        let s = Int(seconds.rounded())
        return String(format: "%d:%02d", s / 60, s % 60)
    }

    // MARK: - Persistencia .caoba

    /// Todo lo que se guarda, en un valor comparable para detectar cambios.
    struct Snapshot: Equatable {
        var mode: Mode; var format: VideoFormat; var duration: Double
        var transition: TransitionChoice; var transitionDuration: Double; var itemTransitions: [String: TransitionChoice]; var itemTransitionDurations: [String: Double]
        var cover: URL?; var coverDuration: Double; var credits: URL?; var creditsDuration: Double
        var textCards: [TextCard]
        var captionStyle: TextStyle; var captionPattern: String; var itemCaptions: [String: String]
        var watermark: URL?; var wmPosition: OverlayPosition; var wmSize: Double; var wmOpacity: Double
        var durations: [String: Double]
        var tracks: [AudioTrack]; var fadeOut: Bool; var normalize: Bool; var loopPlaylist: Bool
        var kb: KenBurnsSettings; var choices: [String: EffectChoice]; var points: [String: KenBurnsPoints]
        var sequence: [SequenceItem]; var reveal: Double; var hold: Double; var bg: CanvasBackground; var gap: Double; var radius: Double; var shadow: Double
        var sortMode: SortMode; var orientation: OrientationFilter; var order: [String]; var excluded: Set<String>
    }

    var snapshot: Snapshot {
        Snapshot(mode: mode, format: format, duration: durationPerPhoto, transition: transitionChoice, transitionDuration: transitionDuration,
                 itemTransitions: itemTransitions, itemTransitionDurations: itemTransitionDurations, cover: coverURL, coverDuration: coverDuration,
                 credits: creditsURL, creditsDuration: creditsDuration,
                 textCards: textCards,
                 captionStyle: captionStyle, captionPattern: captionPattern, itemCaptions: itemCaptions,
                 watermark: watermarkURL, wmPosition: wmPosition, wmSize: wmSize, wmOpacity: wmOpacity,
                 durations: photoDurations, tracks: tracks, fadeOut: fadeOut, normalize: normalize, loopPlaylist: loopPlaylist,
                 kb: kbSettings, choices: kbChoices, points: kbPoints,
                 sequence: sequence, reveal: reveal, hold: hold, bg: csBackground, gap: csGap, radius: csRadius, shadow: csShadow,
                 sortMode: app.sortMode, orientation: app.orientationFilter, order: app.files.map(\.name), excluded: app.excludedNames)
    }

    func scheduleSave() {
        guard !suppressSave, let folder = app.sourceFolder, loadedFolder == folder else { return }
        saveTask?.cancel()
        let preset = makePreset()
        saveTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(2))
            guard !Task.isCancelled else { return }
            if (try? preset.save(in: folder)) != nil { self?.app.markFolderConfigSaved() }
        }
    }

    private func makePreset() -> SlideshowPreset {
        var p = SlideshowPreset()
        p.mode = mode.rawValue
        p.sortMode = app.sortMode.rawValue
        p.orientationFilter = app.orientationFilter.rawValue
        p.fileOrder = app.files.map(\.name)
        p.excludedFiles = Array(app.excludedNames).sorted()
        p.videoFormat = format.rawValue
        p.durationPerPhoto = durationPerPhoto
        p.durations = photoDurations
        var text = SlideshowPreset.TextSection()
        text.cards = textCards
        text.captionStyle = captionStyle; text.captionPattern = captionPattern; text.captions = itemCaptions
        p.text = text
        p.beatsPerCut = beatsPerCut
        p.rhythmItems = rhythmItems.sorted()
        p.useTransition = transitionChoice.hasDuration
        p.transitionKind = transitionChoice.rawValue
        p.transitionDuration = transitionDuration
        p.transitionsByItem = itemTransitions.mapValues(\.rawValue)
        p.transitionDurationsByItem = itemTransitionDurations
        p.cover = coverURL.map { SlideshowPreset.ImageWithDuration(path: $0.path, duration: coverDuration) }
        p.credits = creditsURL.map { SlideshowPreset.ImageWithDuration(path: $0.path, duration: creditsDuration) }
        p.watermark = watermarkURL.map { SlideshowPreset.Watermark(path: $0.path, position: wmPosition.rawValue, size: wmSize, opacity: wmOpacity) }
        p.audio = SlideshowPreset.Audio(fadeout: fadeOut, normalize: normalize, loopPlaylist: loopPlaylist)
        p.musicTracks = tracks.map { t in
            switch t.startMode {
            case .atTime(let s): return SlideshowPreset.MusicTrack(path: t.url.path, mode: "time", trimStart: t.trimStart, trimEnd: t.trimEnd, startTime: s)
            case .atPhoto(let i): return SlideshowPreset.MusicTrack(path: t.url.path, mode: "manual", startPhoto: i, trimStart: t.trimStart, trimEnd: t.trimEnd)
            case .automatic: return SlideshowPreset.MusicTrack(path: t.url.path, mode: "auto", trimStart: t.trimStart, trimEnd: t.trimEnd)
            }
        }
        var kb = SlideshowPreset.KenBurnsSection()
        kb.intensity = kbSettings.intensity.rawValue
        kb.easing = kbSettings.easing.rawValue
        kb.durationPct = kbSettings.durationPercent
        kb.byFile = kbChoices.mapValues(\.rawValue)
        kb.pointsByFile = kbPoints.mapValues { SlideshowPreset.Points($0) }
        p.kenBurns = kb
        var cs = SlideshowPreset.CollageSection()
        cs.templateMode = "sequential"
        cs.revealDuration = reveal
        cs.holdDuration = hold
        cs.bgColor = csBackground.rawValue
        cs.gap = csGap
        cs.borderRadius = csRadius
        cs.shadowIntensity = csShadow
        cs.sequence = sequence.compactMap { $0.template?.id }
        var holds: [String: Double] = [:]
        for (i, item) in sequence.enumerated() { if let h = item.hold { holds[String(i)] = h } }
        cs.holdByRow = holds
        var focus: [String: [SlideshowPreset.FocusPoint]] = [:]
        for (i, row) in rows.enumerated() {
            focus[String(i)] = row.files.enumerated().map { cell, url in
                SlideshowPreset.FocusPoint(file: url.lastPathComponent, fx: row.focusPoints[cell].map { Double($0.x) }, fy: row.focusPoints[cell].map { Double($0.y) })
            }
        }
        cs.focusPoints = focus
        cs.compose = composeSheet.settings(selectedTemplates: selectedTemplates)
        p.collage = cs
        return p
    }

    func loadPresetIfNeeded() {
        guard let folder = app.sourceFolder, folder != loadedFolder else { return }
        loadedFolder = folder
        selection = .none
        guard let preset = SlideshowPreset.load(from: folder) else { resetToDefaults(); return }
        suppressSave = true
        defer { Task { @MainActor [weak self] in self?.suppressSave = false } }
        resetToDefaults()
        if let m = preset.mode.flatMap(Mode.init(rawValue:)) { mode = m }
        if let s = preset.sortMode.flatMap(SortMode.init(rawValue:)) { app.sortMode = s }
        if let o = preset.orientationFilter.flatMap(OrientationFilter.init(rawValue:)) { app.orientationFilter = o }
        if let f = preset.videoFormat.flatMap(VideoFormat.init(rawValue:)) { format = f }
        if let d = preset.durationPerPhoto { durationPerPhoto = d }
        photoDurations = preset.durations ?? [:]
        if let t = preset.text {
            captionStyle = t.captionStyle ?? .caption
            captionPattern = t.captionPattern ?? ""; itemCaptions = t.captions ?? [:]
            if let cards = t.cards {
                textCards = cards
            } else {
                // Proyectos anteriores: el título y el cierre fijos pasan a tarjetas al principio y al final.
                var migrated: [TextCard] = []
                let background = t.background.flatMap(CanvasBackground.init(rawValue:)) ?? .black
                if let mode = t.titleMode, mode != "none", let title = t.title, !title.isEmpty {
                    let isCard = mode == "card"
                    migrated.append(TextCard(text: title, subtitle: t.subtitle ?? "", background: isCard ? background : nil,
                                             duration: isCard ? (t.titleDuration ?? 4) : (t.overlaySeconds ?? 4),
                                             carryNext: isCard && (t.titleCarryOver ?? false), carryNextSeconds: t.overlaySeconds ?? 4,
                                             anchor: TextCard.startAnchor))
                }
                if t.closingEnabled == true, let closing = t.closingText, !closing.isEmpty {
                    migrated.append(TextCard(text: closing, subtitle: t.closingSubtitle ?? "", background: background, duration: t.closingDuration ?? 4,
                                             carryPrevious: t.closingCarryOver ?? false, carryPreviousSeconds: t.closingOverlaySeconds ?? 3,
                                             anchor: TextCard.endAnchor))
                }
                textCards = migrated
            }
            // Ya no hay estilo común de títulos: las tarjetas que lo usaban se quedan con una
            // copia del que tenía guardado el proyecto, así se ven igual que antes.
            let legacyTitleStyle = t.titleStyle ?? .title
            for i in textCards.indices where textCards[i].style == nil { textCards[i].style = legacyTitleStyle }
        }
        beatsPerCut = preset.beatsPerCut
        rhythmItems = Set(preset.rhythmItems ?? [])
        if let kind = preset.transitionKind {
            transitionChoice = TransitionChoice(rawValue: kind)
            transitionDuration = preset.transitionDuration ?? SlideshowSpec.transitionSeconds
            itemTransitions = (preset.transitionsByItem ?? [:]).mapValues(TransitionChoice.init(rawValue:))
            itemTransitionDurations = preset.transitionDurationsByItem ?? [:]
        } else if let t = preset.useTransition {
            // Proyectos antiguos: interruptor activo → fundido de 1 s; apagado → corte.
            transitionChoice = t ? .kind(.crossfade) : .kind(.cut)
        }
        if let c = preset.cover, let path = c.path, FileManager.default.fileExists(atPath: path) { coverURL = URL(fileURLWithPath: path); coverDuration = c.duration ?? 4 }
        if let c = preset.credits, let path = c.path, FileManager.default.fileExists(atPath: path) { creditsURL = URL(fileURLWithPath: path); creditsDuration = c.duration ?? 4 }
        if let w = preset.watermark, let path = w.path, FileManager.default.fileExists(atPath: path) {
            watermarkURL = URL(fileURLWithPath: path)
            wmPosition = w.position.flatMap(OverlayPosition.init(rawValue:)) ?? .bottomRight
            wmSize = w.size ?? 30
            wmOpacity = w.opacityPercent ?? 80
        }
        fadeOut = preset.audio?.fadeout ?? true
        normalize = preset.audio?.normalize ?? false
        loopPlaylist = preset.audio?.loopPlaylist ?? true
        if let order = preset.fileOrder { app.applyOrder(names: order) }
        if let excluded = preset.excludedFiles { app.excludedNames = Set(excluded).intersection(app.files.map(\.name)) }
        if let kb = preset.kenBurns {
            kbSettings = KenBurnsSettings(intensity: kb.intensity.flatMap(KenBurnsIntensity.init(rawValue:)) ?? .normal,
                                          easing: kb.easing.flatMap(KenBurnsEasing.init(rawValue:)) ?? .easeInOut,
                                          durationPercent: kb.durationPct ?? 50)
            if let byFile = kb.byFile {
                kbChoices = byFile.mapValues(EffectChoice.init(rawValue:))
            } else if let perPhoto = kb.perPhoto, let order = preset.fileOrder {
                for (key, value) in perPhoto { if let i = Int(key), order.indices.contains(i) { kbChoices[order[i]] = EffectChoice(rawValue: value) } }
            }
            if let byFile = kb.pointsByFile {
                kbPoints = byFile.mapValues(\.kenBurnsPoints)
            } else if let points = kb.points, let order = preset.fileOrder {
                for (key, value) in points { if let i = Int(key), order.indices.contains(i) { kbPoints[order[i]] = value.kenBurnsPoints } }
            }
        }
        if let cs = preset.collage {
            reveal = cs.revealDuration ?? 1.5
            hold = cs.holdDuration ?? 3
            csBackground = cs.bgColor.flatMap(CanvasBackground.init(rawValue:)) ?? .white
            csGap = cs.gap ?? 10
            csRadius = cs.borderRadius ?? 0
            csShadow = cs.shadowIntensity ?? 50
            composeSheet = ComposeSheetState(cs.compose)
            if cs.compose == nil { composeSheet.filters.aspect = format.label }
            selectedTemplates = Set(cs.compose?.selectedTemplates ?? [])
            sequence = (cs.sequence ?? []).compactMap { id in
                CollageTemplates.template(id: id).map { SequenceItem(templateID: $0.id, focusPoints: Array(repeating: nil, count: $0.photos)) }
            }
            if let holds = cs.holdByRow {
                for (key, value) in holds { if let i = Int(key), sequence.indices.contains(i) { sequence[i].hold = value } }
            }
            if let focus = cs.focusPoints {
                for (key, cells) in focus {
                    guard let i = Int(key), sequence.indices.contains(i) else { continue }
                    for (cell, fp) in cells.enumerated() where sequence[i].focusPoints.indices.contains(cell) {
                        if let fx = fp.fx, let fy = fp.fy { sequence[i].focusPoints[cell] = CGPoint(x: fx, y: fy); sequence[i].manualCells.insert(cell) }
                    }
                }
            }
        }
        // Pistas: el inicio por foto de los ficheros antiguos se convierte a tiempo del vídeo.
        let tl = timeline
        let photoOffset = coverURL != nil ? 1 : 0
        tracks = (preset.musicTracks ?? []).compactMap { t in
            guard FileManager.default.fileExists(atPath: t.path) else { return nil }
            let startMode: AudioTrack.StartMode
            if let s = t.startTime, t.mode == "time" { startMode = .atTime(s) }
            else if t.mode == "manual", let p = t.startPhoto { startMode = .atTime(tl.startTime(ofPhoto: p + photoOffset)) }
            else { startMode = .automatic }
            return AudioTrack(url: URL(fileURLWithPath: t.path), startMode: startMode, trimStart: t.trimStart ?? 0, trimEnd: t.trimEnd)
        }
        for track in tracks { Task { if let d = try? await AudioPlan.duration(of: track.url) { trackDurations[track.id] = d } } }
    }

    func resetToDefaults() {
        mode = .photos; format = .landscape16x9; durationPerPhoto = 4; photoDurations = [:]
        transitionChoice = .kind(.crossfade); transitionDuration = SlideshowSpec.transitionSeconds; itemTransitions = [:]; itemTransitionDurations = [:]
        coverURL = nil; coverDuration = 4; creditsURL = nil; creditsDuration = 4
        textCards = []
        captionStyle = .caption; captionPattern = ""; itemCaptions = [:]
        watermarkURL = nil; wmPosition = .bottomRight; wmSize = 30; wmOpacity = 80
        tracks = []; trackDurations = [:]; fadeOut = true; normalize = false; loopPlaylist = true
        beatTracks = [:]; beatsPerCut = nil; rhythmItems = []; rhythmMessage = nil
        kbSettings = KenBurnsSettings(); kbChoices = [:]; kbPoints = [:]
        sequence = []; reveal = 1.5; hold = 3; csBackground = .white; csGap = 10; csRadius = 0; csShadow = 50
        composeSheet = ComposeSheetState(); selectedTemplates = []; addFilters = TemplateFilterState()
        // Por defecto, plantillas de la proporción del vídeo.
        composeSheet.filters.aspect = format.label; addFilters.aspect = format.label
        selection = .none
    }
}
