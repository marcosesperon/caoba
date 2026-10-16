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
            case .title: TextCardInspector(doc: doc, isClosing: false)
            case .closing: TextCardInspector(doc: doc, isClosing: true)
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
                LabeledRow("Transición") {
                    Picker("", selection: $doc.transitionChoice) {
                        ForEach(TransitionChoice.all, id: \.self) { Text($0.title).tag($0) }
                    }
                    .frame(maxWidth: 260)
                    .labelsHidden()
                }
                if doc.transitionChoice.hasDuration {
                    LabeledSlider(title: "Duración transición", value: $doc.transitionDuration, in: 0.25...2, step: 0.25) { Text("\(doc.transitionDuration, specifier: "%.2f") s") }
                }
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

/// Pestaña Portada y texto: título, pies, portada, créditos y marca de agua.
struct ExtrasTab: View {
    @Bindable var doc: SlideshowDocument

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            OptionGroup(title: "Título") {
                LabeledRow("Modo") {
                    Picker("", selection: $doc.titleMode) {
                        Text("Sin título").tag(TitleMode.none)
                        Text("Pantalla propia").tag(TitleMode.card)
                        Text("Sobre la primera foto").tag(TitleMode.overlay)
                    }
                    .pickerStyle(.segmented).fixedSize()
                    .labelsHidden()
                }
                if doc.titleMode != .none {
                    LabeledRow("Título") { TextField("", text: $doc.titleText).textFieldStyle(.roundedBorder).frame(maxWidth: 360) }
                    LabeledRow("Subtítulo") { TextField("", text: $doc.subtitleText).textFieldStyle(.roundedBorder).frame(maxWidth: 360) }
                    if doc.titleMode == .card {
                        LabeledRow("Fondo") {
                            Picker("", selection: $doc.titleBackground) {
                                Text("Negro").tag(CanvasBackground.black)
                                Text("Blanco").tag(CanvasBackground.white)
                                Text("Gris").tag(CanvasBackground.gray)
                            }
                            .fixedSize().labelsHidden()
                        }
                        LabeledSlider(title: "Duración", value: $doc.titleDuration, in: 1...15, step: 0.5) { Text("\(doc.titleDuration, specifier: "%.1f") s") }
                        Toggle("Mantener el título quieto mientras la tarjeta se funde con la primera foto", isOn: $doc.titleCarryOver)
                        if doc.titleCarryOver {
                            LabeledSlider(title: "Segundos sobre la foto", value: $doc.titleOverlaySeconds, in: 0.5...15, step: 0.5) { Text("\(doc.titleOverlaySeconds, specifier: "%.1f") s") }
                        }
                    } else {
                        LabeledSlider(title: "Segundos mostrándose", value: $doc.titleOverlaySeconds, in: 1...15, step: 0.5) { Text("\(doc.titleOverlaySeconds, specifier: "%.1f") s") }
                    }
                }
                Toggle("Cierre al final (pantalla propia)", isOn: $doc.closingEnabled)
                if doc.closingEnabled {
                    LabeledRow("Texto") { TextField("Gracias", text: $doc.closingText).textFieldStyle(.roundedBorder).frame(maxWidth: 360) }
                    LabeledRow("Subtítulo") { TextField("", text: $doc.closingSubtitle).textFieldStyle(.roundedBorder).frame(maxWidth: 360) }
                    LabeledSlider(title: "Duración", value: $doc.closingDuration, in: 1...15, step: 0.5) { Text("\(doc.closingDuration, specifier: "%.1f") s") }
                    Toggle("Empezar el cierre sobre la última foto y mantenerlo al fundir a su pantalla", isOn: $doc.closingCarryOver)
                    if doc.closingCarryOver {
                        LabeledSlider(title: "Segundos sobre la foto", value: $doc.closingOverlaySeconds, in: 0.5...15, step: 0.5) { Text("\(doc.closingOverlaySeconds, specifier: "%.1f") s") }
                    }
                }
                if doc.titleMode != .none || doc.closingEnabled {
                    TextStyleEditor(title: "Estilo del título", style: $doc.titleStyle)
                }
            }
            OptionGroup(title: "Pies de foto") {
                LabeledRow("Patrón") { TextField("", text: $doc.captionPattern).textFieldStyle(.roundedBorder).frame(maxWidth: 360) }
                Text("Vacío = sin pies. Variables: {nombre} {n} {total} {fecha} {camara} {objetivo}. Cada foto o collage puede llevar un pie propio desde su inspector.")
                    .font(.caption).foregroundStyle(.secondary)
                if !doc.captionPattern.isEmpty || !doc.itemCaptions.isEmpty {
                    TextStyleEditor(title: "Estilo de los pies", style: $doc.captionStyle, showsHold: true)
                }
            }
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
                                HStack(spacing: 4) {
                                    Text("Empieza en \(TimecodeField.format(doc.effectiveStart(of: track))) · suena \(TimecodeField.format(track.effectiveDuration(assetDuration: d)))")
                                    if let beat = doc.beatTracks[track.url.path] {
                                        Text(beat.isReliable ? "· \(Int(beat.tempo.rounded())) ppm" : "· sin ritmo claro")
                                    }
                                }
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
            OptionGroup(title: "Ritmo") {
                LabeledRow("Golpes por foto") {
                    Picker("", selection: $doc.beatsPerCut) {
                        Text("Auto").tag(Int?.none)
                        ForEach(RhythmPlanner.densities, id: \.self) { Text("\($0)").tag(Int?.some($0)) }
                    }
                    .pickerStyle(.segmented).fixedSize()
                    .labelsHidden()
                }
                HStack(spacing: 10) {
                    Button("Ajustar al ritmo") { Task { await doc.adjustToRhythm() } }
                        .disabled(doc.tracks.isEmpty || doc.isAnalyzingRhythm || doc.files.isEmpty)
                    if doc.isAnalyzingRhythm {
                        ProgressView().controlSize(.small)
                        Text("Analizando la música…").font(.caption).foregroundStyle(.secondary)
                    }
                }
                if let message = doc.rhythmMessage {
                    Text(message).font(.caption).foregroundStyle(Color.accentColor)
                }
                Text("Opcional: cada cambio de foto o collage cae en un golpe de la música que suene en ese momento. Las duraciones que hayas fijado a mano se respetan.")
                    .font(.caption).foregroundStyle(.secondary)
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

/// Editor de un estilo de texto: fuente, negrita, tamaño, color, posición y fondo.
struct TextStyleEditor: View {
    let title: LocalizedStringKey
    @Binding var style: TextStyle
    /// Solo en los pies: elegir si se muestran toda la foto o unos segundos.
    var showsHold = false

    @ViewBuilder
    private func animationPicker(_ selection: Binding<TextAnimation>, exit: Bool) -> some View {
        Picker("", selection: selection) {
            if exit {
                Text("Igual que la entrada (inversa)").tag(TextAnimation.mirror)
                Text("Ninguna (se queda)").tag(TextAnimation.none)
            } else {
                Text("Ninguna").tag(TextAnimation.none)
            }
            Text("Fundido").tag(TextAnimation.fade)
            Text(exit ? "Hacia abajo" : "Desde abajo").tag(TextAnimation.slideUp)
            Text(exit ? "Hacia arriba" : "Desde arriba").tag(TextAnimation.slideDown)
            Text(exit ? "Hacia la derecha" : "Desde la derecha").tag(TextAnimation.slideLeft)
            Text(exit ? "Hacia la izquierda" : "Desde la izquierda").tag(TextAnimation.slideRight)
            Text("Zoom").tag(TextAnimation.zoom)
            Text(exit ? "Máquina de escribir (se borra)" : "Máquina de escribir").tag(TextAnimation.typewriter)
            Text("Aleatorio").tag(TextAnimation.random)
        }
        .frame(maxWidth: 240).labelsHidden()
    }

    private var colorBinding: Binding<Color> {
        Binding(get: { Color(red: style.color.red, green: style.color.green, blue: style.color.blue) },
                set: { new in
                    if let c = NSColor(new).usingColorSpace(.sRGB) {
                        style.color = RGBColor(red: Double(c.redComponent), green: Double(c.greenComponent), blue: Double(c.blueComponent))
                    }
                })
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title).font(.subheadline.weight(.semibold)).padding(.top, 4)
            LabeledRow("Fuente") {
                HStack {
                    FontField(fontName: $style.fontName)
                    Toggle("Negrita", isOn: $style.bold)
                }
            }
            LabeledSlider(title: "Tamaño", value: $style.sizePercent, in: 1...20, step: 0.5) { Text("\(style.sizePercent, specifier: "%.1f") %") }
            LabeledRow("Color") { ColorPicker("", selection: colorBinding, supportsOpacity: false).labelsHidden() }
            LabeledRow("Posición") {
                Picker("", selection: $style.anchor) {
                    Text("Arriba izquierda").tag(TextAnchor.topLeft)
                    Text("Arriba centro").tag(TextAnchor.top)
                    Text("Arriba derecha").tag(TextAnchor.topRight)
                    Text("Centro izquierda").tag(TextAnchor.left)
                    Text("Centro").tag(TextAnchor.center)
                    Text("Centro derecha").tag(TextAnchor.right)
                    Text("Abajo izquierda").tag(TextAnchor.bottomLeft)
                    Text("Abajo centro").tag(TextAnchor.bottom)
                    Text("Abajo derecha").tag(TextAnchor.bottomRight)
                }
                .frame(maxWidth: 220).labelsHidden()
            }
            LabeledRow("Fondo") {
                Picker("", selection: $style.backdrop) {
                    Text("Nada").tag(TextBackdrop.none)
                    Text("Sombra").tag(TextBackdrop.shadow)
                    Text("Banda").tag(TextBackdrop.band)
                }
                .pickerStyle(.segmented).fixedSize().labelsHidden()
            }
            // `$style.animation` chocaría con `Binding.animation(_:)` de SwiftUI: bindings explícitos.
            LabeledRow("Entrada") {
                HStack {
                    animationPicker(Binding(get: { style.animation }, set: { style.animation = $0 }), exit: false)
                    if style.animation != .none {
                        Text("en").foregroundStyle(.secondary)
                        Slider(value: $style.animationDuration, in: 0.25...3, step: 0.25).frame(width: 120)
                        Text("\(style.animationDuration, specifier: "%.2f") s").monospacedDigit().frame(width: 52)
                    }
                }
            }
            if showsHold {
                LabeledRow("Mostrar") {
                    HStack {
                        Picker("", selection: Binding(get: { style.holdSeconds == nil }, set: { style.holdSeconds = $0 ? nil : 3 })) {
                            Text("Toda la foto").tag(true)
                            Text("Unos segundos").tag(false)
                        }
                        .pickerStyle(.segmented).fixedSize().labelsHidden()
                        if let hold = style.holdSeconds {
                            Slider(value: Binding(get: { hold }, set: { style.holdSeconds = $0 }), in: 0.5...30, step: 0.5).frame(width: 120)
                            Text("\(hold, specifier: "%.1f") s").monospacedDigit().frame(width: 52)
                        }
                    }
                }
            }
            LabeledRow("Salida") {
                HStack {
                    animationPicker(Binding(get: { style.exitAnimation }, set: { style.exitAnimation = $0 }), exit: true)
                    if style.resolvedExit != .none {
                        Text("en").foregroundStyle(.secondary)
                        Slider(value: $style.exitDuration, in: 0.25...3, step: 0.25).frame(width: 120)
                        Text("\(style.exitDuration, specifier: "%.2f") s").monospacedDigit().frame(width: 52)
                    }
                }
            }
        }
    }
}

/// Selector de fuente: el nombre en su propia tipografía, flechas para pasar a
/// la anterior o la siguiente (viendo la vista previa) y una lista desplegable
/// con buscador por la que se puede ir con las flechas del teclado.
struct FontField: View {
    @Binding var fontName: String?
    @Environment(AppState.self) private var appState
    @State private var showList = false

    /// Familias instaladas más Doto, que va con la app. "" = sistema.
    static let families: [String] = {
        var names = Set(NSFontManager.shared.availableFontFamilies)
        names.insert("Doto")
        return [""] + names.sorted { $0.localizedStandardCompare($1) == .orderedAscending }
    }()

    private var current: String { fontName ?? "" }

    static func font(_ family: String, size: CGFloat) -> Font {
        family.isEmpty ? .system(size: size) : .custom(family, size: size)
    }

    var body: some View {
        HStack(spacing: 4) {
            Button { step(-1) } label: { Image(systemName: "chevron.left") }
                .controlSize(.small).help("Fuente anterior")
            Button { showList.toggle() } label: {
                HStack {
                    Text(current.isEmpty ? String(localized: "Sistema") : current)
                        .font(Self.font(current, size: 13)).lineLimit(1).truncationMode(.tail)
                    Spacer(minLength: 4)
                    Image(systemName: "chevron.up.chevron.down").font(.caption2).foregroundStyle(.secondary)
                }
                .frame(width: 190)
            }
            .popover(isPresented: $showList, arrowEdge: .bottom) {
                FontListPopover(fontName: $fontName, dismiss: { showList = false })
            }
            Button { step(1) } label: { Image(systemName: "chevron.right") }
                .controlSize(.small).help("Fuente siguiente")
        }
        .onAppear {
            // Para capturas: `--state text.fontpicker=1` abre la lista.
            if appState.launchState["text.fontpicker"] != nil { showList = true }
        }
    }

    private func step(_ delta: Int) {
        let list = Self.families
        guard let index = list.firstIndex(of: current) else { fontName = nil; return }
        let next = list[(index + delta + list.count) % list.count]
        fontName = next.isEmpty ? nil : next
    }
}

/// Lista de fuentes con buscador: cada nombre en su tipografía; las flechas del
/// teclado cambian la selección y la vista previa de fondo se actualiza al momento.
struct FontListPopover: View {
    @Binding var fontName: String?
    let dismiss: () -> Void
    @State private var filter = ""
    @FocusState private var listFocused: Bool

    private var filtered: [String] {
        let query = filter.trimmingCharacters(in: .whitespaces)
        return FontField.families.filter { query.isEmpty || $0.isEmpty || $0.localizedCaseInsensitiveContains(query) }
    }

    var body: some View {
        VStack(spacing: 8) {
            TextField("Buscar fuente", text: $filter).textFieldStyle(.roundedBorder)
            List(selection: Binding<String?>(get: { fontName ?? "" }, set: { fontName = ($0 ?? "").isEmpty ? nil : $0 })) {
                ForEach(filtered, id: \.self) { family in
                    Text(family.isEmpty ? String(localized: "Sistema") : family)
                        .font(FontField.font(family, size: 15))
                        .lineLimit(1)
                        .tag(String?.some(family))
                }
            }
            .focused($listFocused)
            .onKeyPress(.return) { dismiss(); return .handled }
            Text("Flechas ↑↓ para probar; Intro para cerrar.").font(.caption).foregroundStyle(.secondary)
        }
        .padding(10)
        .frame(width: 300, height: 420)
        .onAppear { listFocused = true }
    }
}

/// Pie propio de un elemento: patrón, texto propio o sin pie.
struct CaptionOverrideRow: View {
    @Bindable var doc: SlideshowDocument
    let id: String

    private enum Choice: Hashable { case pattern, own, none }
    private var choice: Choice {
        guard let own = doc.itemCaptions[id] else { return .pattern }
        return own.isEmpty ? .none : .own
    }

    var body: some View {
        HStack(spacing: 10) {
            LabeledRow("Pie") {
                Picker("", selection: Binding<Choice>(get: { choice }, set: { new in
                    switch new {
                    case .pattern: doc.itemCaptions[id] = nil
                    case .own: if doc.itemCaptions[id]?.isEmpty ?? true { doc.itemCaptions[id] = " " }
                    case .none: doc.itemCaptions[id] = ""
                    }
                })) {
                    Text("Patrón").tag(Choice.pattern)
                    Text("Propio").tag(Choice.own)
                    Text("Sin pie").tag(Choice.none)
                }
                .pickerStyle(.segmented).fixedSize().labelsHidden()
            }
            if choice == .own {
                TextField("", text: Binding(get: { doc.itemCaptions[id] ?? "" }, set: { doc.itemCaptions[id] = $0.isEmpty ? " " : $0 }))
                    .textFieldStyle(.roundedBorder).frame(maxWidth: 300)
            }
            Spacer()
        }
    }
}

/// Tarjeta de título o de cierre seleccionada.
struct TextCardInspector: View {
    @Bindable var doc: SlideshowDocument
    let isClosing: Bool

    var body: some View {
        Text(isClosing ? "Cierre" : "Título").font(.headline)
        OptionGroup(title: "Texto") {
            LabeledRow(isClosing ? "Texto" : "Título") { TextField("", text: isClosing ? $doc.closingText : $doc.titleText).textFieldStyle(.roundedBorder).frame(maxWidth: 360) }
            LabeledRow("Subtítulo") { TextField("", text: isClosing ? $doc.closingSubtitle : $doc.subtitleText).textFieldStyle(.roundedBorder).frame(maxWidth: 360) }
            LabeledRow("Fondo") {
                Picker("", selection: $doc.titleBackground) {
                    Text("Negro").tag(CanvasBackground.black)
                    Text("Blanco").tag(CanvasBackground.white)
                    Text("Gris").tag(CanvasBackground.gray)
                }
                .fixedSize().labelsHidden()
            }
            LabeledSlider(title: "Duración", value: isClosing ? $doc.closingDuration : $doc.titleDuration, in: 1...15, step: 0.5) {
                Text("\(isClosing ? doc.closingDuration : doc.titleDuration, specifier: "%.1f") s")
            }
            TransitionOverrideRow(doc: doc, id: isClosing ? "closing" : "title")
            Text("El estilo del texto se ajusta en la pestaña «Portada y texto».").font(.caption).foregroundStyle(.secondary)
        }
    }
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
            TransitionOverrideRow(doc: doc, id: isCover ? "cover" : "credits")
        }
    }
}

/// Transición y duración de entrada propias de un elemento («Por defecto» = las globales).
struct TransitionOverrideRow: View {
    @Bindable var doc: SlideshowDocument
    let id: String

    private var hasDuration: Bool { doc.transitionChoice(for: id).hasDuration }

    var body: some View {
        HStack(spacing: 10) {
            LabeledRow("Transición") {
                Picker("", selection: Binding<TransitionChoice?>(get: { doc.itemTransitions[id] }, set: { doc.itemTransitions[id] = $0 })) {
                    Text("Por defecto").tag(TransitionChoice?.none)
                    ForEach(TransitionChoice.all, id: \.self) { Text($0.title).tag(TransitionChoice?.some($0)) }
                }
                .frame(maxWidth: 220)
                .labelsHidden()
            }
            if hasDuration {
                Text("Duración").foregroundStyle(.secondary)
                Slider(value: Binding(get: { doc.entryDuration(for: id) }, set: { doc.itemTransitionDurations[id] = $0 }), in: 0.25...2, step: 0.25)
                    .frame(maxWidth: 160)
                Text("\(doc.entryDuration(for: id), specifier: "%.2f") s").monospacedDigit().frame(width: 52)
                if doc.itemTransitionDurations[id] != nil {
                    Button { doc.itemTransitionDurations[id] = nil } label: { Image(systemName: "arrow.uturn.backward") }
                        .buttonStyle(.borderless).help("Volver a la duración global")
                }
            }
            Spacer()
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
        TransitionOverrideRow(doc: doc, id: name)
        CaptionOverrideRow(doc: doc, id: name)
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
    @State private var showResult = false

    private var itemIndex: Int? { doc.sequence.firstIndex { $0.id == row.id } }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 10) {
                Text(row.template.name).font(.headline)
                CollageViewModePicker(showResult: $showResult)
                if !showResult {
                    Text("· arrastra cada foto para encuadrarla").font(.caption).foregroundStyle(.secondary)
                }
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
                if !showResult {
                    Button { centerCells() } label: { Label("Centrar", systemImage: "scope") }
                    Toggle(isOn: $showTemplates) { Label("Cambiar", systemImage: "rectangle.3.group") }.toggleStyle(.button)
                }
                Button(role: .destructive) { doc.removeCollage(row.id) } label: { Label("Quitar", systemImage: "trash") }
            }
            TransitionOverrideRow(doc: doc, id: row.id.uuidString)
            CaptionOverrideRow(doc: doc, id: row.id.uuidString)
            HStack(alignment: .top, spacing: 16) {
                if showResult {
                    // Con las opciones de collage del vídeo, que son las que se usan al generar.
                    CollageResultView(row: row, options: doc.collageOptions.collage)
                } else {
                    TemplateView(template: row.template, files: row.files, focusPoints: row.focusPoints, gap: 3) { cell, point in
                        guard let i = itemIndex, doc.sequence[i].focusPoints.indices.contains(cell) else { return }
                        doc.sequence[i].focusPoints[cell] = point
                        doc.sequence[i].manualCells.insert(cell)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                }
                if showTemplates, !showResult {
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
