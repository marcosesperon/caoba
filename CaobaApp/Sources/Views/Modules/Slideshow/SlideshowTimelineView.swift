import SwiftUI
import CaobaCore

/// Timeline del slideshow: regla de tiempo, tarjetas proporcionales a su
/// duración (portada, fotos o collages, créditos) y carriles de música.
struct SlideshowTimelineView: View {
    @Bindable var doc: SlideshowDocument

    private let cardHeight: CGFloat = 96
    private let laneHeight: CGFloat = 26

    private var pps: CGFloat { CGFloat(doc.pixelsPerSecond) }
    private var totalWidth: CGFloat { max(200, CGFloat(doc.timelineExtent) * pps) }

    var body: some View {
        VStack(spacing: 4) {
            header
            ScrollView(.horizontal) {
                VStack(alignment: .leading, spacing: 6) {
                    ruler
                    cards
                    lanes
                }
                // Sin contenido no hay vídeo que termine: la marca sobra.
                .overlay(alignment: .topLeading) { if doc.totalDuration > 0 { videoEndMarker } }
                .padding(.vertical, 6)
                .padding(.horizontal, 8)
                .padding(.trailing, 60)
                .frame(minWidth: totalWidth + 76, alignment: .leading)
                .contentShape(Rectangle())
                .onTapGesture { doc.selection = .none }
            }
        }
        .caobaPanel(padding: 0, fill: Color(nsColor: .controlBackgroundColor).opacity(0.5))
        .overlay {
            if doc.items.isEmpty {
                ContentUnavailableView(doc.mode == .photos ? "Sin fotos" : "Sin collages", systemImage: "film",
                                       description: Text(doc.mode == .photos ? "Elige una carpeta para montar el slideshow." : "Pulsa Componer o Añadir para empezar."))
            }
        }
    }

    /// Cabecera del timeline: duración total y zoom.
    private var header: some View {
        HStack(spacing: 8) {
            Label("Timeline", systemImage: "film.stack").font(.headline)
            Text("· \(SlideshowDocument.formatDuration(doc.totalDuration))").monospacedDigit().foregroundStyle(.secondary)
            Spacer()
            Image(systemName: "minus.magnifyingglass").foregroundStyle(.secondary)
            Slider(value: $doc.pixelsPerSecond, in: 12...120).frame(width: 140)
            Image(systemName: "plus.magnifyingglass").foregroundStyle(.secondary)
        }
        .padding(.horizontal, 10)
        .padding(.top, 6)
    }

    /// Línea vertical donde termina el vídeo; lo que quede a la derecha es audio que no sonará.
    private var videoEndMarker: some View {
        let x = CGFloat(doc.totalDuration) * pps
        return VStack(alignment: .leading, spacing: 0) {
            Text("Fin del vídeo").font(.caption2).foregroundStyle(Color.accentColor).padding(.leading, 3)
            Rectangle().fill(Color.accentColor).frame(width: 1.5)
        }
        .frame(height: 18 + 6 + cardHeight + 6 + CGFloat(doc.tracks.count) * (laneHeight + 3))
        .offset(x: x)
        .allowsHitTesting(false)
    }

    // MARK: Regla

    private var ruler: some View {
        let step: Double = pps >= 60 ? 1 : (pps >= 30 ? 5 : 10)
        let total = doc.timelineExtent
        return ZStack(alignment: .topLeading) {
            Rectangle().fill(.quaternary).frame(height: 1).offset(y: 14)
            ForEach(Array(stride(from: 0.0, through: total, by: step)), id: \.self) { t in
                VStack(spacing: 1) {
                    Text(SlideshowDocument.formatDuration(t)).font(.caption2.monospacedDigit()).foregroundStyle(.secondary)
                    Rectangle().fill(.secondary).frame(width: 1, height: 4)
                }
                .offset(x: CGFloat(t) * pps)
            }
            // Golpes de la música (solo tras «Ajustar al ritmo»): marcas finas bajo la regla.
            ForEach(Array(doc.videoBeats.enumerated()), id: \.offset) { _, beat in
                Rectangle().fill(Color.accentColor.opacity(0.55)).frame(width: 1, height: 5)
                    .offset(x: CGFloat(beat.time) * pps, y: 13)
            }
        }
        .frame(width: totalWidth, height: 18, alignment: .topLeading)
    }

    // MARK: Tarjetas

    private var cards: some View {
        ZStack(alignment: .topLeading) {
            ForEach(doc.items) { item in
                TimelineCard(doc: doc, item: item, height: cardHeight)
                    .frame(width: max(24, CGFloat(item.duration) * pps - 2), height: cardHeight)
                    .offset(x: CGFloat(item.start) * pps)
            }
        }
        .frame(width: totalWidth, height: cardHeight, alignment: .topLeading)
    }

    // MARK: Música

    /// Un carril por pista: el bloque principal mide lo que dura la canción
    /// recortada; lo que la rellena (la propia canción repitiéndose o las
    /// vueltas de la lista) se dibuja atenuado y no se puede tocar.
    private var lanes: some View {
        let total = doc.totalDuration
        let segments = doc.audioSegments
        return VStack(alignment: .leading, spacing: 3) {
            ForEach(doc.tracks) { track in
                let effective = trackLength(track)
                let primaryStart = doc.effectiveStart(of: track)
                ZStack(alignment: .leading) {
                    Rectangle().fill(.quaternary.opacity(0.4)).frame(height: laneHeight)
                    ForEach(Array(fillerRanges(for: track, segments: segments, effective: effective, primaryStart: primaryStart).enumerated()), id: \.offset) { _, range in
                        RoundedRectangle(cornerRadius: 4).fill(Color.accentColor.opacity(0.15))
                            .frame(width: max(3, CGFloat(range.upperBound - range.lowerBound) * pps), height: laneHeight)
                            .offset(x: CGFloat(range.lowerBound) * pps)
                            .allowsHitTesting(false)
                    }
                    TrackBlock(doc: doc, track: track, start: primaryStart, length: effective, videoEnd: total, height: laneHeight)
                        .frame(width: max(12, CGFloat(effective) * pps))
                        .offset(x: CGFloat(primaryStart) * pps)
                }
                .frame(width: totalWidth, height: laneHeight, alignment: .leading)
            }
            Button {
                addTracks()
            } label: {
                Label("Añadir pista", systemImage: "music.note.list")
            }
            .buttonStyle(.link)
            .padding(.top, 2)
        }
    }

    /// Duración real de la canción recortada (o la del vídeo si aún no se sabe).
    private func trackLength(_ track: AudioTrack) -> Double {
        doc.trackDurations[track.id].map { track.effectiveDuration(assetDuration: $0) } ?? doc.totalDuration
    }

    /// Tramos de relleno: dentro de cada segmento de esta pista, todo lo que va
    /// más allá de una vuelta de la canción, troceado por vueltas; y los
    /// segmentos posteriores al principal (repetición de la lista).
    private func fillerRanges(for track: AudioTrack, segments: [AudioSegment], effective: Double, primaryStart: Double) -> [ClosedRange<Double>] {
        var ranges: [ClosedRange<Double>] = []
        let own = segments.filter { $0.url == track.url && $0.trimStart == track.trimStart }
        for (n, segment) in own.enumerated() {
            var cursor = segment.start + (n == 0 ? effective : 0)
            while cursor < segment.end - 0.05 {
                let end = min(segment.end, cursor + effective)
                ranges.append(cursor...end)
                cursor = end + 0.0001
            }
        }
        return ranges
    }

    private func addTracks() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.mp3, .mpeg4Audio, .wav, .aiff, .audio]
        panel.allowsMultipleSelection = true
        guard panel.runModal() == .OK else { return }
        doc.addTracks(panel.urls)
    }
}

/// Tarjeta de portada, foto, collage o créditos.
struct TimelineCard: View {
    @Bindable var doc: SlideshowDocument
    let item: TimelineItem
    let height: CGFloat
    @State private var hovering = false
    @State private var stretchStart: Double?

    private var isSelected: Bool { doc.selection == item.selection }
    private var pps: CGFloat { CGFloat(doc.pixelsPerSecond) }

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .topLeading) {
                thumbnail(size: geo.size)
                LinearGradient(colors: [.clear, .black.opacity(0.6)], startPoint: .center, endPoint: .bottom)
                VStack(alignment: .leading) {
                    HStack {
                        if case .photo(let url) = item.kind, hovering || isSelected {
                            Toggle("", isOn: Binding(get: { true }, set: { _ in doc.toggleExcluded(url) }))
                                .toggleStyle(.checkbox).labelsHidden().help("Quitar del vídeo")
                        }
                        Spacer()
                        if let badge = badge {
                            Text(badge).font(.caption2.bold()).padding(.horizontal, 5).padding(.vertical, 2)
                                .background(Color.accentColor.opacity(0.85)).clipShape(Capsule()).foregroundStyle(.white)
                        }
                    }
                    Spacer()
                    HStack {
                        Text(label).font(.caption2).lineLimit(1).foregroundStyle(.white.opacity(0.9))
                        Spacer()
                        Text("\(item.duration, specifier: "%.1f") s").font(.caption2.monospacedDigit()).foregroundStyle(.white)
                    }
                }
                .padding(4)
                // Asa para estirar la duración: solo los 6 px del borde derecho
                // responden; el resto de la tarjeta queda libre para reordenar.
                if canStretch {
                    HStack(spacing: 0) {
                        Spacer(minLength: 0)
                        Rectangle().fill(isSelected || hovering ? Color.accentColor : .clear)
                            .frame(width: 6)
                            .contentShape(Rectangle().inset(by: -3))
                            .highPriorityGesture(DragGesture(minimumDistance: 1)
                                .onChanged { value in
                                    if stretchStart == nil { stretchStart = item.duration }
                                    doc.setDuration((stretchStart ?? item.duration) + Double(value.translation.width / pps), for: item)
                                }
                                .onEnded { _ in stretchStart = nil })
                            .onHover { inside in if inside { NSCursor.resizeLeftRight.push() } else { NSCursor.pop() } }
                    }
                }
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 6))
        .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(isSelected ? Color.accentColor : Color.white.opacity(0.15), lineWidth: isSelected ? 2 : 1))
        .contentShape(Rectangle())
        .onTapGesture { doc.selection = item.selection }
        .onHover { hovering = $0 }
        .contextMenu { contextMenu }
        .modifier(ReorderModifier(doc: doc, item: item))
    }

    private var canStretch: Bool { true }

    private var badge: String? {
        if case .photo(let url) = item.kind { return doc.choice(for: url).badge }
        return nil
    }

    private var label: String {
        switch item.kind {
        case .cover: return String(localized: "Portada")
        case .credits: return String(localized: "Créditos")
        case .photo(let url): return url.lastPathComponent
        case .collage(let row): return row.template.name
        case .text: return String(localized: "Texto")
        }
    }

    @ViewBuilder
    private func thumbnail(size: CGSize) -> some View {
        switch item.kind {
        case .text(let card):
            // Tarjeta de texto: su fondo (o rayada si va superpuesta al siguiente) y el texto en Doto.
            ZStack {
                if let background = card.background {
                    Color(cgColor: background.fill)
                } else {
                    Color.secondary.opacity(0.25)
                    Image(systemName: "textformat").font(.title2).foregroundStyle(.secondary).offset(y: -10)
                }
                Text(card.text.isEmpty ? "…" : card.text).font(.caobaTitle(12)).lineLimit(2).multilineTextAlignment(.center)
                    .foregroundStyle(card.background.map { Color(cgColor: $0.text) } ?? .primary).padding(6)
            }
            .frame(width: size.width, height: size.height)
        case .cover(let url), .credits(let url):
            CellPhotoView(url: url, focus: CGPoint(x: 0.5, y: 0.5), size: size)
        case .photo(let url):
            let points = doc.kbPoints[url.lastPathComponent]
            CellPhotoView(url: url, focus: points?.startFocus ?? CGPoint(x: 0.5, y: 0.5), size: size, zoom: points?.startZoom ?? 1)
        case .collage(let row):
            TemplateView(template: row.template, files: row.files, focusPoints: row.focusPoints, gap: 1)
                .frame(width: size.width, height: size.height)
                .background(Color.secondary.opacity(0.2))
        }
    }

    @ViewBuilder
    private var contextMenu: some View {
        switch item.kind {
        case .photo(let url):
            Button("Quitar del vídeo") { doc.toggleExcluded(url) }
            Menu("Efecto") {
                ForEach(EffectChoice.all, id: \.self) { choice in Button(choice.title) { doc.setChoice(choice, for: url) } }
            }
        case .collage(let row):
            Button("Quitar", role: .destructive) { doc.removeCollage(row.id) }
        case .cover:
            Button("Quitar portada") { doc.coverURL = nil }
        case .credits:
            Button("Quitar créditos") { doc.creditsURL = nil }
        case .text(let card):
            Button("Quitar texto", role: .destructive) { doc.removeTextCard(card.id) }
        }
        Divider()
        Button("Añadir texto antes") { doc.selection = item.selection; doc.addTextCard() }
        Button("Añadir texto después") { doc.selection = item.selection; doc.addTextCard(after: true) }
    }
}

/// Arrastrar y soltar para reordenar fotos y collages.
private struct ReorderModifier: ViewModifier {
    @Bindable var doc: SlideshowDocument
    let item: TimelineItem

    /// Una tarjeta de texto soltada sobre cualquier elemento se coloca delante de él.
    private func dropText(_ payload: String) -> Bool {
        guard payload.hasPrefix("text:"), let id = UUID(uuidString: String(payload.dropFirst(5))) else { return false }
        if case .text(let card) = item.kind { doc.moveTextCard(id, beforeCard: card.id) } else { doc.moveTextCard(id, beforeElement: item.id) }
        return true
    }

    func body(content: Content) -> some View {
        switch item.kind {
        case .photo(let url):
            content
                .draggable("photo:" + url.lastPathComponent)
                .dropDestination(for: String.self) { items, _ in
                    guard let payload = items.first else { return false }
                    if dropText(payload) { return true }
                    guard payload.hasPrefix("photo:") else { return false }
                    doc.movePhoto(named: String(payload.dropFirst(6)), before: url.lastPathComponent)
                    return true
                }
        case .collage(let row):
            content
                .draggable("collage:" + row.id.uuidString)
                .dropDestination(for: String.self) { items, _ in
                    guard let payload = items.first else { return false }
                    if dropText(payload) { return true }
                    guard payload.hasPrefix("collage:"), let id = UUID(uuidString: String(payload.dropFirst(8))) else { return false }
                    doc.moveCollage(id, before: row.id)
                    return true
                }
        case .text(let card):
            content
                .draggable("text:" + card.id.uuidString)
                .dropDestination(for: String.self) { items, _ in items.first.map(dropText) ?? false }
        default:
            content
                .dropDestination(for: String.self) { items, _ in items.first.map(dropText) ?? false }
        }
    }
}

/// Bloque de una pista en su carril: se arrastra para el inicio (con imán) y
/// se estira por los bordes para el recorte.
struct TrackBlock: View {
    @Bindable var doc: SlideshowDocument
    let track: AudioTrack
    let start: Double
    let length: Double
    /// Fin del vídeo: la parte del bloque que quede después se dibuja apagada.
    let videoEnd: Double
    let height: CGFloat
    @State private var dragOrigin: Double?
    @State private var trimAccumulated: Double = 0

    private var pps: CGFloat { CGFloat(doc.pixelsPerSecond) }
    private var isSelected: Bool { doc.selection == .track(track.id) }

    var body: some View {
        ZStack {
            // Cuerpo: mover el inicio. El gesto va en esta vista y no en el
            // contenedor, para que las asas (hermanas por encima) reciban los suyos.
            RoundedRectangle(cornerRadius: 5)
                .fill(Color.accentColor.opacity(isSelected ? 0.55 : 0.35))
                .overlay(RoundedRectangle(cornerRadius: 5).strokeBorder(isSelected ? Color.accentColor : .clear, lineWidth: 1.5))
                .overlay(alignment: .leading) {
                    HStack(spacing: 4) {
                        Image(systemName: "music.note").font(.caption2)
                        Text(track.url.deletingPathExtension().lastPathComponent).font(.caption2).lineLimit(1)
                        Text(TimecodeField.format(length)).font(.caption2.monospacedDigit()).opacity(0.8)
                    }
                    .padding(.horizontal, 10)
                    .foregroundStyle(.white)
                }
                .overlay(alignment: .trailing) {
                    // Tramo que no se oirá porque el vídeo ya ha terminado.
                    let silent = max(0, min(length, start + length - videoEnd))
                    if silent > 0 {
                        Rectangle().fill(.black.opacity(0.45))
                            .frame(width: CGFloat(silent) * pps)
                            .clipShape(RoundedRectangle(cornerRadius: 5))
                            .allowsHitTesting(false)
                    }
                }
                .contentShape(Rectangle())
                .onTapGesture { doc.selection = .track(track.id) }
                .highPriorityGesture(moveGesture)
                .help("Arrastra para mover el inicio; estira los bordes para recortar")
            HStack {
                handle(isLeading: true)
                Spacer()
                handle(isLeading: false)
            }
        }
        .frame(height: height)
    }

    private var moveGesture: some Gesture {
        DragGesture(minimumDistance: 2)
            .onChanged { value in
                if dragOrigin == nil { dragOrigin = start; doc.selection = .track(track.id) }
                let candidate = (dragOrigin ?? start) + Double(value.translation.width / pps)
                doc.setStart(snapped(candidate), for: track.id)
            }
            .onEnded { _ in dragOrigin = nil }
    }

    /// Imán a los inicios de foto, al final de la pista anterior y al 0, dentro de 8 píxeles.
    private func snapped(_ t: Double) -> Double {
        let threshold = 8 / Double(pps)
        let points = doc.snapPoints
        if let near = points.min(by: { abs($0 - t) < abs($1 - t) }), abs(near - t) <= threshold { return near }
        return max(0, t)
    }

    private func handle(isLeading: Bool) -> some View {
        RoundedRectangle(cornerRadius: 2)
            .fill(Color.white.opacity(isSelected ? 0.7 : 0.4))
            .frame(width: 6, height: height - 8)
            .padding(.horizontal, 2)
            .contentShape(Rectangle().inset(by: -4))
            .highPriorityGesture(DragGesture(minimumDistance: 1)
                .onChanged { value in
                    let delta = Double(value.translation.width / pps) - trimAccumulated
                    trimAccumulated += delta
                    if isLeading { doc.trimLeading(by: delta, for: track.id) } else { doc.trimTrailing(by: delta, for: track.id) }
                }
                .onEnded { _ in trimAccumulated = 0 })
            .onHover { inside in if inside { NSCursor.resizeLeftRight.push() } else { NSCursor.pop() } }
            .help(isLeading ? "Desde (recorte del principio)" : "Hasta (recorte del final)")
    }
}
