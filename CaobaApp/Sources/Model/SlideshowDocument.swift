import SwiftUI
import Observation
import CaobaCore

/// Efecto elegido para una foto en la interfaz: ninguno, al azar o uno concreto.
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
        }
    }
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
    var transition = true
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
        var result: [(String, TimelineItem.Kind, Double)] = []
        if let coverURL { result.append(("cover", .cover(coverURL), coverDuration)) }
        switch mode {
        case .photos:
            for url in files { result.append((url.lastPathComponent, .photo(url), duration(of: url))) }
        case .collage:
            for row in rows {
                result.append((row.id.uuidString, .collage(row), CollageSlideshow.duration(of: row, options: collageOptions)))
            }
        }
        if let creditsURL { result.append(("credits", .credits(creditsURL), creditsDuration)) }
        return result
    }

    var timeline: SlideshowTimeline {
        SlideshowTimeline(durations: orderedKinds.map(\.duration), transition: transition ? SlideshowSpec.transitionSeconds : 0)
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
        let value = max(0.5, min(60, (seconds * 2).rounded() / 2))
        switch item.kind {
        case .cover: coverDuration = value
        case .credits: creditsDuration = value
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

    private func makePhotos(limit: Int? = nil) -> [SlideshowPhoto] {
        var generator = SystemRandomNumberGenerator()
        var list = files
        if let limit { list = Array(list.prefix(limit)) }
        var photos: [SlideshowPhoto] = list.map { url in
            let name = url.lastPathComponent
            let effect: KenBurnsEffect?
            switch kbChoices[name] ?? .none {
            case .none: effect = nil
            case .random: effect = KenBurnsEffect.randomPool.randomElement(using: &generator)
            case .effect(let e): effect = e
            }
            return SlideshowPhoto(url: url, duration: duration(of: url), kenBurns: effect, points: kbPoints[name])
        }
        if let coverURL { photos.insert(SlideshowPhoto(url: coverURL, duration: coverDuration), at: 0) }
        if let creditsURL { photos.append(SlideshowPhoto(url: creditsURL, duration: creditsDuration)) }
        return photos
    }

    private func makeSpec(output: URL, preview: Bool) -> SlideshowSpec {
        var audio = AudioOptions(tracks: tracks, fadeOut: fadeOut, normalize: normalize, loopPlaylist: loopPlaylist)
        if preview { audio.normalize = false }
        return SlideshowSpec(photos: [], format: format, transition: transition,
                             watermark: watermarkURL.map { VideoWatermark(url: $0, position: wmPosition, sizePercent: wmSize, opacity: wmOpacity) },
                             audio: audio, kenBurns: kbSettings, output: output, preview: preview)
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

    private func launch(output: URL, preview: Bool) {
        let mode = mode
        let fixedRows = rows
        let csOptions = collageOptions
        let photoList = makePhotos(limit: preview ? 10 : nil)
        let coverURL = coverURL, creditsURL = creditsURL, coverDuration = coverDuration, creditsDuration = creditsDuration
        let baseSpec = makeSpec(output: output, preview: preview)
        app.jobRunner.run(openURL: preview ? nil : output, quietOnSuccess: preview) { progress in
            var photos = photoList
            var frameDir: URL?
            if mode == .collage {
                let dir = try TempFiles.makeJobDirectory(prefix: "csshow")
                frameDir = dir
                let limited = preview ? Array(fixedRows.prefix(3)) : fixedRows
                photos = try await CollageSlideshow.makePhotos(rows: limited, options: csOptions, directory: dir, progress: progress)
                if let coverURL { photos.insert(SlideshowPhoto(url: coverURL, duration: coverDuration), at: 0) }
                if let creditsURL { photos.append(SlideshowPhoto(url: creditsURL, duration: creditsDuration)) }
            }
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
        var mode: Mode; var format: VideoFormat; var duration: Double; var transition: Bool
        var cover: URL?; var coverDuration: Double; var credits: URL?; var creditsDuration: Double
        var watermark: URL?; var wmPosition: OverlayPosition; var wmSize: Double; var wmOpacity: Double
        var durations: [String: Double]
        var tracks: [AudioTrack]; var fadeOut: Bool; var normalize: Bool; var loopPlaylist: Bool
        var kb: KenBurnsSettings; var choices: [String: EffectChoice]; var points: [String: KenBurnsPoints]
        var sequence: [SequenceItem]; var reveal: Double; var hold: Double; var bg: CanvasBackground; var gap: Double; var radius: Double; var shadow: Double
        var sortMode: SortMode; var orientation: OrientationFilter; var order: [String]; var excluded: Set<String>
    }

    var snapshot: Snapshot {
        Snapshot(mode: mode, format: format, duration: durationPerPhoto, transition: transition, cover: coverURL, coverDuration: coverDuration,
                 credits: creditsURL, creditsDuration: creditsDuration, watermark: watermarkURL, wmPosition: wmPosition, wmSize: wmSize, wmOpacity: wmOpacity,
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
        p.useTransition = transition
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
        if let t = preset.useTransition { transition = t }
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
        mode = .photos; format = .landscape16x9; durationPerPhoto = 4; transition = true; photoDurations = [:]
        coverURL = nil; coverDuration = 4; creditsURL = nil; creditsDuration = 4
        watermarkURL = nil; wmPosition = .bottomRight; wmSize = 30; wmOpacity = 80
        tracks = []; trackDurations = [:]; fadeOut = true; normalize = false; loopPlaylist = true
        kbSettings = KenBurnsSettings(); kbChoices = [:]; kbPoints = [:]
        sequence = []; reveal = 1.5; hold = 3; csBackground = .white; csGap = 10; csRadius = 0; csShadow = 50
        composeSheet = ComposeSheetState(); selectedTemplates = []; addFilters = TemplateFilterState()
        // Por defecto, plantillas de la proporción del vídeo.
        composeSheet.filters.aspect = format.label; addFilters.aspect = format.label
        selection = .none
    }
}
