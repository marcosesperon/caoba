import SwiftUI
import UniformTypeIdentifiers
import CaobaCore

/// Pestaña contextual con lo seleccionado en el timeline.
struct SelectionTab: View {
    @Bindable var doc: SlideshowDocument
    @Binding var expandedFraming: URL?

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            switch doc.selection {
            case .none:
                Text("Selecciona una tarjeta o una pista en el timeline.").foregroundStyle(.secondary)
            case .cover: ImageSlotInspector(doc: doc, isCover: true)
            case .credits: ImageSlotInspector(doc: doc, isCover: false)
            case .photo(let name):
                if let url = doc.files.first(where: { $0.lastPathComponent == name }) {
                    PhotoInspector(doc: doc, url: url, expandedFraming: $expandedFraming)
                }
            case .track(let id):
                if let track = doc.tracks.first(where: { $0.id == id }) { TrackInspector(doc: doc, track: track) }
            case .collage(let id):
                if let row = doc.rows.first(where: { $0.id == id }) { CollageInspector(doc: doc, row: row) }
            }
        }
    }
}

/// Pestaña Vídeo: formato, ritmo, fundido y ajustes globales de Ken Burns o del aspecto de los collages.
struct VideoTab: View {
    @Bindable var doc: SlideshowDocument
    @State private var showAdvanced = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            OptionGroup(title: "Formato y ritmo") {
                LabeledRow("Formato") {
                    Picker("", selection: $doc.format) {
                        ForEach(VideoFormat.allCases) { f in Text("\(Text(f.usageTitle)) (\(f.label)) · \(f.size.width)×\(f.size.height)").tag(f) }
                    }
                    .labelsHidden()
                }
                if doc.mode == .photos {
                    LabeledSlider(title: "Segundos por foto", value: $doc.durationPerPhoto, in: 1...15, step: 0.5) { Text("\(doc.durationPerPhoto, specifier: "%.1f") s") }
                    if !doc.photoDurations.isEmpty {
                        HStack {
                            Text("\(doc.photoDurations.count) fotos con duración propia").font(.caption).foregroundStyle(.secondary)
                            Spacer()
                            Button("Igualar duraciones") { doc.equalizeDurations() }.controlSize(.small)
                        }
                    }
                } else {
                    LabeledSlider(title: "Aparición", value: $doc.reveal, in: 0.3...5, step: 0.1) { Text("\(doc.reveal, specifier: "%.1f") s") }
                    LabeledSlider(title: "Mantener", value: $doc.hold, in: 0...15, step: 0.5) { Text("\(doc.hold, specifier: "%.1f") s") }
                    if doc.sequence.contains(where: { $0.hold != nil }) {
                        HStack {
                            Text("\(doc.sequence.filter { $0.hold != nil }.count) collages con duración propia").font(.caption).foregroundStyle(.secondary)
                            Spacer()
                            Button("Igualar duraciones") { doc.equalizeDurations() }.controlSize(.small)
                        }
                    }
                }
                Toggle("Fundido entre fotos (1 s)", isOn: $doc.transition)
            }
            if doc.mode == .photos {
                OptionGroup(title: "Ken Burns") {
                    LabeledRow("Velocidad") {
                        Picker("", selection: $doc.kbSettings.intensity) {
                            Text("Lenta").tag(KenBurnsIntensity.slow)
                            Text("Normal").tag(KenBurnsIntensity.normal)
                            Text("Rápida").tag(KenBurnsIntensity.fast)
                        }
                        .labelsHidden()
                    }
                    DisclosureGroup("Avanzado", isExpanded: $showAdvanced) {
                        LabeledRow("Curva") {
                            Picker("", selection: $doc.kbSettings.easing) {
                                Text("Lineal").tag(KenBurnsEasing.linear)
                                Text("Ease in").tag(KenBurnsEasing.easeIn)
                                Text("Ease out").tag(KenBurnsEasing.easeOut)
                                Text("Ease in-out").tag(KenBurnsEasing.easeInOut)
                            }
                            .labelsHidden()
                        }
                        LabeledSlider(title: "Duración del efecto", value: $doc.kbSettings.durationPercent, in: 20...100, step: 5) { Text("\(Int(doc.kbSettings.durationPercent)) %") }
                    }
                    Text("Selecciona una foto del timeline para elegir su efecto y encuadre.").font(.caption).foregroundStyle(.secondary)
                }
            } else {
                OptionGroup(title: "Aspecto de los collages") {
                    LabeledRow("Fondo") {
                        Picker("", selection: $doc.csBackground) {
                            Text("Blanco").tag(CanvasBackground.white)
                            Text("Negro").tag(CanvasBackground.black)
                            Text("Gris").tag(CanvasBackground.gray)
                        }
                        .labelsHidden()
                    }
                    LabeledSlider(title: "Separación", value: $doc.csGap, in: 0...60, step: 1) { Text("\(Int(doc.csGap)) px") }
                    LabeledSlider(title: "Esquinas", value: $doc.csRadius, in: 0...100, step: 1) { Text("\(Int(doc.csRadius)) px") }
                    LabeledSlider(title: "Sombra", value: $doc.csShadow, in: 0...100, step: 5) { Text("\(Int(doc.csShadow)) %") }
                }
            }
        }
    }
}

/// Pestaña Portada y marca: portada, créditos y marca de agua.
struct ExtrasTab: View {
    @Bindable var doc: SlideshowDocument

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            OptionGroup(title: "Portada y créditos") {
                slotRow(title: "Portada", url: $doc.coverURL, duration: $doc.coverDuration)
                slotRow(title: "Créditos", url: $doc.creditsURL, duration: $doc.creditsDuration)
                Text("Aparecen como primera y última tarjeta del timeline; selecciónalas allí para cambiar la imagen o la duración.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            OptionGroup(title: "Marca de agua") {
                HStack {
                    Text(doc.watermarkURL?.lastPathComponent ?? String(localized: "Ningún PNG elegido"))
                        .lineLimit(1).truncationMode(.middle).frame(maxWidth: .infinity, alignment: .leading)
                    if doc.watermarkURL != nil { Button("Quitar") { doc.watermarkURL = nil } }
                    Button("Elegir PNG…") { if let url = pickImage(types: [.png]) { doc.watermarkURL = url } }
                }
                if doc.watermarkURL != nil {
                    LabeledRow("Posición") {
                        Picker("", selection: $doc.wmPosition) {
                            Text("Abajo derecha").tag(OverlayPosition.bottomRight)
                            Text("Abajo izquierda").tag(OverlayPosition.bottomLeft)
                            Text("Arriba derecha").tag(OverlayPosition.topRight)
                            Text("Arriba izquierda").tag(OverlayPosition.topLeft)
                            Text("Centro").tag(OverlayPosition.center)
                        }
                        .labelsHidden()
                    }
                    LabeledSlider(title: "Tamaño", value: $doc.wmSize, in: 1...100, step: 1) { Text("\(Int(doc.wmSize)) %") }
                    LabeledSlider(title: "Opacidad", value: $doc.wmOpacity, in: 0...100, step: 1) { Text("\(Int(doc.wmOpacity)) %") }
                }
            }
        }
    }

    private func slotRow(title: LocalizedStringKey, url: Binding<URL?>, duration: Binding<Double>) -> some View {
        HStack {
            Text(title).frame(width: 130, alignment: .leading)
            Text(url.wrappedValue?.lastPathComponent ?? String(localized: "Ninguna"))
                .lineLimit(1).truncationMode(.middle).frame(maxWidth: .infinity, alignment: .leading)
                .foregroundStyle(url.wrappedValue == nil ? .secondary : .primary)
            if url.wrappedValue != nil {
                Stepper("\(duration.wrappedValue, specifier: "%.0f") s", value: duration, in: 1...30).fixedSize()
                Button("Quitar") { url.wrappedValue = nil }
            }
            Button("Elegir…") { if let picked = pickImage() { url.wrappedValue = picked } }
        }
    }
}

/// Pestaña Música: lista de pistas y opciones.
struct MusicTab: View {
    @Bindable var doc: SlideshowDocument

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            OptionGroup(title: "Pistas") {
                if doc.tracks.isEmpty {
                    Text("Sin pistas. Añade una canción y colócala arrastrando su bloque en el timeline.").font(.callout).foregroundStyle(.secondary)
                }
                ForEach(doc.tracks) { track in
                    HStack {
                        Image(systemName: "music.note").foregroundStyle(.secondary)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(track.url.lastPathComponent).lineLimit(1).truncationMode(.middle)
                            if let d = doc.trackDurations[track.id] {
                                Text("Empieza en \(TimecodeField.format(doc.effectiveStart(of: track))) · suena \(TimecodeField.format(track.effectiveDuration(assetDuration: d)))")
                                    .font(.caption).foregroundStyle(.secondary)
                            }
                        }
                        Spacer()
                        Button("Editar") { doc.selection = .track(track.id) }.controlSize(.small)
                        Button { doc.removeTrack(track.id) } label: { Image(systemName: "minus.circle") }.buttonStyle(.borderless)
                    }
                }
                Button("Añadir pista…") { addTracks() }
            }
            OptionGroup(title: "Opciones") {
                if doc.tracks.count > 1 {
                    Toggle("Repetir la lista si el vídeo es más largo", isOn: $doc.loopPlaylist)
                }
                Toggle("Fundido de salida (3 s)", isOn: $doc.fadeOut)
                Toggle("Normalizar volumen (EBU R128, -16 LUFS)", isOn: $doc.normalize)
                Text("Entre pistas hay siempre un crossfade de 3 segundos.").font(.caption).foregroundStyle(.secondary)
            }
        }
    }

    private func addTracks() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.mp3, .mpeg4Audio, .wav, .aiff, .audio]
        panel.allowsMultipleSelection = true
        guard panel.runModal() == .OK else { return }
        doc.addTracks(panel.urls)
    }
}

@MainActor
func pickImage(types: [UTType] = [.jpeg, .png, .heic]) -> URL? {
    let panel = NSOpenPanel()
    panel.allowedContentTypes = types
    return panel.runModal() == .OK ? panel.url : nil
}

/// Portada o créditos seleccionados.
struct ImageSlotInspector: View {
    @Bindable var doc: SlideshowDocument
    let isCover: Bool

    var body: some View {
        Text(isCover ? "Portada" : "Créditos").font(.headline)
        OptionGroup(title: "Imagen") {
            let url = isCover ? doc.coverURL : doc.creditsURL
            if let url {
                ThumbnailView(url: url, maxPixelSize: 600, displaySize: 220)
                Text(url.lastPathComponent).lineLimit(1).truncationMode(.middle)
            }
            HStack {
                Button("Cambiar…") { if let picked = pickImage() { if isCover { doc.coverURL = picked } else { doc.creditsURL = picked } } }
                Button("Quitar") { if isCover { doc.coverURL = nil } else { doc.creditsURL = nil }; doc.selection = .none }
            }
            LabeledSlider(title: "Duración", value: isCover ? $doc.coverDuration : $doc.creditsDuration, in: 1...30, step: 0.5) { Text("\(isCover ? doc.coverDuration : doc.creditsDuration, specifier: "%.1f") s") }
        }
    }
}

/// Foto seleccionada: efecto, duración y encuadre.
struct PhotoInspector: View {
    @Bindable var doc: SlideshowDocument
    let url: URL
    @Binding var expandedFraming: URL?

    private var name: String { url.lastPathComponent }

    var body: some View {
        HStack {
            Text(name).font(.headline).lineLimit(1).truncationMode(.middle)
            Spacer()
            Button { expandedFraming = url } label: { Label("Ampliar", systemImage: "arrow.up.left.and.arrow.down.right") }
                .help("Editar el encuadre a tamaño grande")
        }
        HStack(spacing: 16) {
            LabeledRow("Efecto") {
                Picker("", selection: Binding(get: { doc.choice(for: url) }, set: { doc.setChoice($0, for: url) })) {
                    ForEach(EffectChoice.all, id: \.self) { Text($0.title).tag($0) }
                }
                .frame(maxWidth: 300)
                .labelsHidden()
            }
            Text("Duración").foregroundStyle(.secondary)
            Slider(value: Binding(get: { doc.duration(of: url) }, set: { doc.photoDurations[name] = $0 }), in: 0.5...30, step: 0.5)
                .frame(maxWidth: 220)
            Text("\(doc.duration(of: url), specifier: "%.1f") s").monospacedDigit().frame(width: 48)
            if doc.photoDurations[name] != nil {
                Button { doc.photoDurations[name] = nil } label: { Image(systemName: "arrow.uturn.backward") }
                    .buttonStyle(.borderless).help("Volver a la duración global")
            }
            Spacer()
        }
        KenBurnsFramingView(doc: doc, url: url, compact: false)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
}

/// Pista seleccionada.
struct TrackInspector: View {
    @Bindable var doc: SlideshowDocument
    let track: AudioTrack

    private var index: Int? { doc.tracks.firstIndex { $0.id == track.id } }

    var body: some View {
        Text(track.url.lastPathComponent).font(.headline).lineLimit(1).truncationMode(.middle)
        OptionGroup(title: "Pista") {
            if let d = doc.trackDurations[track.id] {
                Text("Duración del fichero: \(TimecodeField.format(d)) · suena \(TimecodeField.format(track.effectiveDuration(assetDuration: d)))")
                    .font(.caption).foregroundStyle(.secondary)
            }
            LabeledRow("Inicio en el vídeo") {
                TimecodeField(seconds: Binding(get: { doc.effectiveStart(of: track) }, set: { doc.setStart($0, for: track.id) }))
                Button("Tras la anterior") { if let i = index { doc.tracks[i].startMode = .automatic } }
                    .controlSize(.small)
                    .disabled(index == 0 || { if case .automatic = track.startMode { return true } else { return false } }())
            }
            LabeledRow("Desde") {
                TimecodeField(seconds: Binding(get: { track.trimStart }, set: { v in if let i = index { doc.tracks[i].trimStart = max(0, v) } }))
                Text("Hasta").padding(.leading, 12)
                TimecodeField(seconds: Binding(get: { track.trimEnd ?? doc.trackDurations[track.id] ?? 0 },
                                               set: { v in
                                                   guard let i = index else { return }
                                                   let asset = doc.trackDurations[track.id] ?? v
                                                   doc.tracks[i].trimEnd = v >= asset - 0.5 ? nil : max(track.trimStart + 1, v)
                                               }))
            }
            Text("También puedes arrastrar el bloque en el timeline y estirar sus bordes.").font(.caption).foregroundStyle(.secondary)
            Button("Quitar pista", role: .destructive) { doc.removeTrack(track.id) }
        }
    }
}

/// Collage seleccionado: encuadre por celda (encajado al espacio) y cambio de plantilla.
struct CollageInspector: View {
    @Bindable var doc: SlideshowDocument
    let row: CollageRow
    @State private var showTemplates = false

    private var itemIndex: Int? { doc.sequence.firstIndex { $0.id == row.id } }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 10) {
                Text(row.template.name).font(.headline)
                Text("· arrastra cada foto para encuadrarla").font(.caption).foregroundStyle(.secondary)
                Spacer()
                Text("Mantener").foregroundStyle(.secondary)
                Slider(value: Binding(get: { row.hold ?? doc.hold }, set: { doc.setHold($0, for: row.id) }), in: 0...30, step: 0.5)
                    .frame(width: 140)
                Text("\(row.hold ?? doc.hold, specifier: "%.1f") s").monospacedDigit().frame(width: 44)
                if row.hold != nil {
                    Button { doc.setHold(nil, for: row.id) } label: { Image(systemName: "arrow.uturn.backward") }
                        .buttonStyle(.borderless).help("Volver al valor global")
                }
                Divider().frame(height: 16)
                Button { centerCells() } label: { Label("Centrar", systemImage: "scope") }
                Toggle(isOn: $showTemplates) { Label("Cambiar", systemImage: "rectangle.3.group") }.toggleStyle(.button)
                Button(role: .destructive) { doc.removeCollage(row.id) } label: { Label("Quitar", systemImage: "trash") }
            }
            HStack(alignment: .top, spacing: 16) {
                TemplateView(template: row.template, files: row.files, focusPoints: row.focusPoints, gap: 3) { cell, point in
                    guard let i = itemIndex, doc.sequence[i].focusPoints.indices.contains(cell) else { return }
                    doc.sequence[i].focusPoints[cell] = point
                    doc.sequence[i].manualCells.insert(cell)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                if showTemplates {
                    TemplatePicker(templates: CollageTemplates.filter(photos: row.template.photos, includeOverlap: true), selected: [row.template.id]) { template in
                        guard let i = itemIndex else { return }
                        doc.sequence[i].templateID = template.id
                        doc.sequence[i].focusPoints = Array(repeating: nil, count: template.photos)
                        doc.sequence[i].manualCells = []
                    }
                    .frame(width: 340)
                    .frame(maxHeight: .infinity)
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private func centerCells() {
        guard let i = itemIndex else { return }
        doc.sequence[i].focusPoints = Array(repeating: nil, count: row.template.photos)
        doc.sequence[i].manualCells = []
    }
}
