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
            case .text(let id): TextCardInspector(doc: doc, cardId: id)
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
                    .frame(maxWidth: 260, alignment: .leading)
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
        // Las tarjetas de texto (y su estilo) se añaden desde el Timeline y se editan al pulsarlas allí.
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
            OptionGroup(title: "Pies de foto") {
                LabeledRow("Patrón") { TextField("", text: $doc.captionPattern).textFieldStyle(.roundedBorder).frame(maxWidth: 360) }
                Text("Vacío = sin pies. Variables: {nombre} {n} {total} {fecha} {camara} {objetivo}. Cada foto o collage puede llevar un pie propio desde su inspector.")
                    .font(.caption).foregroundStyle(.secondary)
                if !doc.captionPattern.isEmpty || !doc.itemCaptions.isEmpty {
                    TextStyleEditor(title: "Estilo de los pies", style: $doc.captionStyle, showsHold: true)
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
    /// Subtítulo encima de los controles; `nil` cuando el bloque que lo contiene ya lo dice.
    var title: LocalizedStringKey? = nil
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
        .frame(maxWidth: 240, alignment: .leading).labelsHidden()
    }

    private var colorBinding: Binding<Color> {
        Binding(get: { Color(red: style.color.red, green: style.color.green, blue: style.color.blue) },
                set: { new in
                    if let c = NSColor(new).usingColorSpace(.sRGB) {
                        style.color = RGBColor(red: Double(c.redComponent), green: Double(c.greenComponent), blue: Double(c.blueComponent))
                    }
                })
    }

    /// Partes del estilo, para montarlas juntas (pies) o cada una en su grupo (tarjetas).
    enum Part: CaseIterable { case letter, placement, animation }
    /// Qué partes se enseñan; por defecto todas.
    var parts: Set<Part> = Set(Part.allCases)
    /// En columna estrecha (inspector): cada etiqueta encima de su control.
    var stacked = false

    var body: some View {
        VStack(alignment: .leading, spacing: stacked ? 10 : 8) {
            if let title { Text(title).font(.subheadline.weight(.semibold)).padding(.top, 4) }
            if parts.contains(.letter) { letter }
            if parts.contains(.placement) { placement }
            if parts.contains(.animation) { animations }
        }
    }

    /// Fila con etiqueta: a la izquierda en la columna fija o, en columna estrecha, encima.
    @ViewBuilder
    private func row(_ title: LocalizedStringKey, @ViewBuilder content: () -> some View) -> some View {
        if stacked {
            StackedRow(title, content: content)
        } else {
            LabeledRow(title, content: content)
        }
    }

    /// Deslizador de segundos de una animación (o de lo que se muestra el pie).
    @ViewBuilder
    private func secondsSlider(_ title: LocalizedStringKey, value: Binding<Double>, in range: ClosedRange<Double>, step: Double) -> some View {
        // Con la coma o el punto que toque según el idioma (0,60 s).
        let label = Text("\(value.wrappedValue.formatted(.number.precision(.fractionLength(2)))) s")
        if stacked {
            StackedSlider(title: title, value: value, in: range, step: step) { label }
        } else {
            HStack {
                Text(title).foregroundStyle(.secondary)
                Slider(value: value, in: range, step: step).frame(width: 120)
                label.monospacedDigit().frame(width: 52)
            }
        }
    }

    /// Letra: fuente con negrita, tamaño y color.
    @ViewBuilder
    private var letter: some View {
        row("Fuente") {
            if stacked {
                VStack(alignment: .leading, spacing: 6) {
                    FontField(fontName: $style.fontName)
                    Toggle("Negrita", isOn: $style.bold)
                }
            } else {
                HStack {
                    FontField(fontName: $style.fontName)
                    Toggle("Negrita", isOn: $style.bold)
                }
            }
        }
        if stacked {
            StackedSlider(title: "Tamaño", value: $style.sizePercent, in: 1...20, step: 0.5) { Text("\(style.sizePercent, specifier: "%.1f") %") }
        } else {
            LabeledSlider(title: "Tamaño", value: $style.sizePercent, in: 1...20, step: 0.5) { Text("\(style.sizePercent, specifier: "%.1f") %") }
        }
        row("Color") { ColorPicker("", selection: colorBinding, supportsOpacity: false).labelsHidden() }
    }

    /// Colocación: en qué parte de la pantalla y con qué realce (sombra o banda) para que se lea.
    @ViewBuilder
    private var placement: some View {
        row("Posición") {
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
            .frame(maxWidth: 220, alignment: .leading).labelsHidden()
        }
        row("Realce") {
            Picker("", selection: $style.backdrop) {
                Text("Nada").tag(TextBackdrop.none)
                Text("Sombra").tag(TextBackdrop.shadow)
                Text("Banda").tag(TextBackdrop.band)
            }
            .pickerStyle(.segmented).fixedSize().labelsHidden()
        }
    }

    /// Animación: entrada, (en los pies) cuánto se muestra, y salida; cada una con sus segundos.
    // `$style.animation` chocaría con `Binding.animation(_:)` de SwiftUI: bindings explícitos.
    @ViewBuilder
    private var animations: some View {
        row("Entrada") {
            if stacked {
                animationPicker(Binding(get: { style.animation }, set: { style.animation = $0 }), exit: false)
            } else {
                HStack {
                    animationPicker(Binding(get: { style.animation }, set: { style.animation = $0 }), exit: false)
                    if style.animation != .none {
                        secondsSlider("en", value: $style.animationDuration, in: 0.25...3, step: 0.25)
                    }
                }
            }
        }
        if stacked, style.animation != .none {
            secondsSlider("Duración de la entrada", value: $style.animationDuration, in: 0.25...3, step: 0.25)
        }
        if showsHold {
            row("Mostrar") {
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
        row("Salida") {
            if stacked {
                animationPicker(Binding(get: { style.exitAnimation }, set: { style.exitAnimation = $0 }), exit: true)
            } else {
                HStack {
                    animationPicker(Binding(get: { style.exitAnimation }, set: { style.exitAnimation = $0 }), exit: true)
                    if style.resolvedExit != .none {
                        secondsSlider("en", value: $style.exitDuration, in: 0.25...3, step: 0.25)
                    }
                }
            }
        }
        if stacked, style.resolvedExit != .none {
            secondsSlider("Duración de la salida", value: $style.exitDuration, in: 0.25...3, step: 0.25)
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
    /// En columna (inspectores con columna de ajustes): selector y campo uno debajo de otro.
    var stacked = false

    private enum Choice: Hashable { case pattern, own, none }
    private var choice: Choice {
        guard let own = doc.itemCaptions[id] else { return .pattern }
        return own.isEmpty ? .none : .own
    }

    var body: some View {
        if stacked {
            VStack(alignment: .leading, spacing: 8) {
                picker
                if choice == .own { ownField }
            }
        } else {
            HStack(spacing: 10) {
                LabeledRow("Pie") { picker }
                if choice == .own { ownField.frame(maxWidth: 300) }
                Spacer()
            }
        }
    }

    /// Patrón (el de la pestaña «Portada y texto»), pie propio o ninguno.
    private var picker: some View {
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

    /// Texto del pie propio (un espacio guardado = propio pero aún vacío).
    private var ownField: some View {
        TextField("", text: Binding(get: { doc.itemCaptions[id] ?? "" }, set: { doc.itemCaptions[id] = $0.isEmpty ? " " : $0 }))
            .textFieldStyle(.roundedBorder)
    }
}

/// Tarjeta de texto seleccionada: la vista previa a la izquierda y, en una columna,
/// contenido, pantalla y tiempo, letra, colocación, animación y empalmes. Cada tarjeta
/// lleva su propio estilo; «Aplicar estilo a todas» lo copia a las demás.
struct TextCardInspector: View {
    @Bindable var doc: SlideshowDocument
    let cardId: UUID
    @State private var confirmApplyAll = false

    private var card: Binding<TextCard> {
        Binding(get: { doc.textCard(cardId) ?? TextCard() }, set: { doc.updateTextCard($0) })
    }

    /// El estilo de la tarjeta (las antiguas sin estilo se migran al abrir; `.title` por si acaso).
    private var style: Binding<TextStyle> {
        Binding(get: { card.wrappedValue.style ?? .title }, set: { card.wrappedValue.style = $0 })
    }

    private var hasOwnScreen: Bool { card.wrappedValue.background != nil }
    private var otherCards: Int { max(0, doc.textCards.count - 1) }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            header
            // La vista previa, con la proporción del vídeo (más su título y su etiqueta); los ajustes, el resto.
            InspectorSplit(previewWidth: { height in (height - 56) * doc.format.aspectRatio }) {
                TextPreviewPanel(doc: doc, content: .card)
            } settings: {
                OptionGroup(title: "Contenido") { content }
                OptionGroup(title: "Pantalla y tiempo") { screenAndTime }
                OptionGroup(title: "Letra") { TextStyleEditor(style: style, parts: [.letter], stacked: true) }
                OptionGroup(title: "Colocación") { TextStyleEditor(style: style, parts: [.placement], stacked: true) }
                OptionGroup(title: "Animación") { TextStyleEditor(style: style, parts: [.animation], stacked: true) }
                if hasOwnScreen { OptionGroup(title: "Empalmes") { carryOvers } }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .confirmationDialog("¿Aplicar este estilo a todas las tarjetas de texto?", isPresented: $confirmApplyAll) {
            Button("Aplicar a todas") { doc.applyStyleToAllCards(from: cardId) }
        } message: {
            Text("Las otras \(otherCards) tarjetas pasarán a tener la misma letra, colocación y animaciones que esta. El texto, la pantalla y los tiempos de cada una no cambian.")
        }
    }

    /// «Texto · primera línea» y la acción de copiar el estilo a las demás tarjetas.
    private var header: some View {
        HStack {
            Text(card.wrappedValue.text.isEmpty ? String(localized: "Texto") : String(localized: "Texto · \(card.wrappedValue.text)"))
                .font(.headline).lineLimit(1).truncationMode(.tail)
            Spacer()
            Button { confirmApplyAll = true } label: { Label("Aplicar estilo a todas", systemImage: "square.on.square") }
                .disabled(otherCards == 0)
                .help("Copia la letra, la colocación y las animaciones de esta tarjeta a todas las demás")
        }
    }

    /// Texto principal y subtítulo (opcional, en una segunda línea más pequeña).
    @ViewBuilder
    private var content: some View {
        let c = card
        StackedRow("Texto") { TextField("", text: c.text).textFieldStyle(.roundedBorder) }
        StackedRow("Subtítulo") { TextField("", text: c.subtitle, prompt: Text("Opcional")).textFieldStyle(.roundedBorder) }
    }

    /// Dónde se ve (pantalla propia con fondo o encima del elemento siguiente) y cuánto dura.
    @ViewBuilder
    private var screenAndTime: some View {
        let c = card
        StackedRow("Dónde se ve") {
            Picker("", selection: Binding(get: { hasOwnScreen }, set: { own in c.wrappedValue.background = own ? (c.wrappedValue.background ?? .black) : nil })) {
                Text("Pantalla propia").tag(true)
                Text("Sobre el siguiente").tag(false)
            }
            .pickerStyle(.segmented).fixedSize().labelsHidden()
        }
        if let background = c.wrappedValue.background {
            StackedRow("Fondo de la pantalla") {
                Picker("", selection: Binding(get: { background }, set: { c.wrappedValue.background = $0 })) {
                    Text("Negro").tag(CanvasBackground.black)
                    Text("Blanco").tag(CanvasBackground.white)
                    Text("Gris").tag(CanvasBackground.gray)
                }
                .pickerStyle(.segmented).fixedSize().labelsHidden()
            }
            StackedSlider(title: "Duración", value: c.duration, in: 1...30, step: 0.5) { Text("\(c.wrappedValue.duration, specifier: "%.1f") s") }
            StackedRow("Transición de entrada") { TransitionOverrideRow(doc: doc, id: cardId.uuidString, stacked: true) }
        } else {
            StackedSlider(title: "Segundos sobre el siguiente", value: c.duration, in: 0.5...30, step: 0.5) { Text("\(c.wrappedValue.duration, specifier: "%.1f") s") }
            Text("El texto aparece encima del elemento que viene después en el timeline, con su entrada y su salida.")
                .font(.caption).foregroundStyle(.secondary)
        }
    }

    /// Con pantalla propia: el texto puede empezar sobre el elemento anterior o seguir sobre el siguiente.
    @ViewBuilder
    private var carryOvers: some View {
        let c = card
        Toggle("Empezar sobre el anterior", isOn: c.carryPrevious)
        Text("El texto aparece ya sobre el elemento anterior y se queda quieto mientras se funde a esta pantalla.")
            .font(.caption).foregroundStyle(.secondary)
        if c.wrappedValue.carryPrevious {
            StackedSlider(title: "Segundos sobre el anterior", value: c.carryPreviousSeconds, in: 0.5...15, step: 0.5) {
                Text("\(c.wrappedValue.carryPreviousSeconds, specifier: "%.1f") s")
            }
        }
        Divider()
        Toggle("Seguir sobre el siguiente", isOn: c.carryNext)
        Text("El texto se queda quieto mientras esta pantalla se funde con el elemento siguiente y sigue un rato sobre él.")
            .font(.caption).foregroundStyle(.secondary)
        if c.wrappedValue.carryNext {
            StackedSlider(title: "Segundos sobre el siguiente", value: c.carryNextSeconds, in: 0.5...15, step: 0.5) {
                Text("\(c.wrappedValue.carryNextSeconds, specifier: "%.1f") s")
            }
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
    /// En columna (inspectores con columna de ajustes): tipo arriba y duración debajo.
    var stacked = false

    private var hasDuration: Bool { doc.transitionChoice(for: id).hasDuration }

    private var duration: Binding<Double> {
        Binding(get: { doc.entryDuration(for: id) }, set: { doc.itemTransitionDurations[id] = $0 })
    }

    /// Botón de volver a la duración global; solo si esta tiene una propia.
    private var resetDuration: (() -> Void)? {
        doc.itemTransitionDurations[id] == nil ? nil : { doc.itemTransitionDurations[id] = nil }
    }

    var body: some View {
        if stacked {
            VStack(alignment: .leading, spacing: 8) {
                picker.frame(maxWidth: .infinity, alignment: .leading)
                if hasDuration {
                    StackedSlider(title: "Duración de la transición", value: duration, in: 0.25...2, step: 0.25, onReset: resetDuration) {
                        Text("\(doc.entryDuration(for: id), specifier: "%.2f") s")
                    }
                }
            }
        } else {
            HStack(spacing: 10) {
                LabeledRow("Transición") { picker.frame(maxWidth: 220, alignment: .leading) }
                if hasDuration {
                    Text("Duración").foregroundStyle(.secondary)
                    Slider(value: duration, in: 0.25...2, step: 0.25)
                        .frame(maxWidth: 160)
                    Text("\(doc.entryDuration(for: id), specifier: "%.2f") s").monospacedDigit().frame(width: 52)
                    if let resetDuration {
                        Button(action: resetDuration) { Image(systemName: "arrow.uturn.backward") }
                            .buttonStyle(.borderless).help("Volver a la duración global")
                    }
                }
                Spacer()
            }
        }
    }

    /// «Por defecto» = la transición global de la pestaña Vídeo.
    private var picker: some View {
        Picker("", selection: Binding<TransitionChoice?>(get: { doc.itemTransitions[id] }, set: { doc.itemTransitions[id] = $0 })) {
            Text("Por defecto").tag(TransitionChoice?.none)
            ForEach(TransitionChoice.all, id: \.self) { Text($0.title).tag(TransitionChoice?.some($0)) }
        }
        .labelsHidden()
    }
}

/// Foto seleccionada: cabecera con «Ampliar», los paneles de inicio y fin del Ken Burns
/// a la izquierda y, en una sola columna, efecto, encuadre, tiempo, transición y pie.
struct PhotoInspector: View {
    @Bindable var doc: SlideshowDocument
    let url: URL
    @Binding var expandedFraming: URL?

    private var name: String { url.lastPathComponent }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text(name).font(.headline).lineLimit(1).truncationMode(.middle)
                Spacer()
                Button { expandedFraming = url } label: { Label("Ampliar", systemImage: "arrow.up.left.and.arrow.down.right") }
                    .help("Editar el encuadre a tamaño grande")
            }
            KenBurnsFramingView(doc: doc, url: url, compact: false) {
                OptionGroup(title: "Efecto") {
                    Picker("", selection: Binding(get: { doc.choice(for: url) }, set: { doc.setChoice($0, for: url) })) {
                        ForEach(EffectChoice.all, id: \.self) { Text($0.title).tag($0) }
                    }
                    .labelsHidden()
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            } trailing: {
                OptionGroup(title: "Tiempo") {
                    StackedSlider(title: "Duración", value: Binding(get: { doc.duration(of: url) }, set: { doc.photoDurations[name] = $0 }),
                                  in: 0.5...30, step: 0.5, onReset: doc.photoDurations[name] == nil ? nil : { doc.photoDurations[name] = nil }) {
                        Text("\(doc.duration(of: url), specifier: "%.1f") s")
                    }
                }
                OptionGroup(title: "Transición") { TransitionOverrideRow(doc: doc, id: name, stacked: true) }
                OptionGroup(title: "Pie") { CaptionOverrideRow(doc: doc, id: name, stacked: true) }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
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

/// Reparto de los inspectores con vista grande (Texto, Collage y Foto): la vista toma
/// solo el ancho que necesita para llenar el alto disponible con su proporción, y los
/// ajustes se quedan con el resto, repartidos en columnas (`BalancedColumns`). Los
/// ajustes nunca bajan de `minSettingsWidth`: si no cabe, es la vista la que encoge.
struct InspectorSplit<Preview: View, Settings: View>: View {
    static var minSettingsWidth: CGFloat { 300 }
    private let spacing: CGFloat = 16
    /// Ancho que necesita la vista para un alto dado (según su proporción).
    let previewWidth: (CGFloat) -> CGFloat
    @ViewBuilder var preview: Preview
    @ViewBuilder var settings: Settings

    var body: some View {
        GeometryReader { geo in
            let width = max(120, min(previewWidth(geo.size.height), geo.size.width - Self.minSettingsWidth - spacing))
            HStack(alignment: .top, spacing: spacing) {
                preview.frame(width: width, height: geo.size.height, alignment: .topLeading)
                ScrollView {
                    BalancedColumns { settings }
                        .padding(.trailing, 2)   // que el borde de los bloques no lo tape la barra de desplazamiento
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
    }
}

/// Reparte los grupos de ajustes en 1, 2 o 3 columnas según el ancho (cada una de al menos
/// `minColumnWidth`). Mantiene el orden: se leen de arriba abajo y de izquierda a derecha,
/// en tramos seguidos, y elige los cortes que dejan la columna más alta lo más baja posible.
struct BalancedColumns: Layout {
    var minColumnWidth: CGFloat = 280
    var maxColumns = 3
    var columnSpacing: CGFloat = 16
    var rowSpacing: CGFloat = 12

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        // SwiftUI a veces pregunta sin ancho o con uno infinito (para saber el máximo): se mide como una columna.
        let width = proposal.width.flatMap { $0.isFinite ? $0 : nil } ?? minColumnWidth
        let plan = arrange(width: width, subviews: subviews)
        return CGSize(width: width, height: plan.height)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let plan = arrange(width: bounds.width, subviews: subviews)
        for (column, range) in plan.columns.enumerated() {
            var y = bounds.minY
            let x = bounds.minX + CGFloat(column) * (plan.columnWidth + columnSpacing)
            for index in range {
                subviews[index].place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(width: plan.columnWidth, height: plan.heights[index]))
                y += plan.heights[index] + rowSpacing
            }
        }
    }

    /// Cuántas columnas caben, su ancho, el alto de cada grupo a ese ancho y qué grupos van en cada columna.
    private func arrange(width: CGFloat, subviews: Subviews) -> (columnWidth: CGFloat, heights: [CGFloat], columns: [Range<Int>], height: CGFloat) {
        let fitting = width.isFinite ? Int((width + columnSpacing) / (minColumnWidth + columnSpacing)) : 1
        let count = max(1, min(maxColumns, fitting, subviews.count))
        let columnWidth = (width - CGFloat(count - 1) * columnSpacing) / CGFloat(count)
        let heights = subviews.map { $0.sizeThatFits(ProposedViewSize(width: columnWidth, height: nil)).height }
        let columns = bestSplit(heights, into: count)
        let tallest = columns.map { columnHeight(heights, $0) }.max() ?? 0
        return (columnWidth, heights, columns, tallest)
    }

    /// Alto de una columna con esos grupos (y la separación entre ellos).
    private func columnHeight(_ heights: [CGFloat], _ range: Range<Int>) -> CGFloat {
        guard !range.isEmpty else { return 0 }
        return heights[range].reduce(0, +) + CGFloat(range.count - 1) * rowSpacing
    }

    /// Cortes en tramos seguidos que minimizan la columna más alta. Son pocos grupos y
    /// como mucho 3 columnas, así que basta con probar todas las combinaciones.
    private func bestSplit(_ heights: [CGFloat], into count: Int) -> [Range<Int>] {
        let n = heights.count
        guard count > 1, n > 1 else { return [0..<n] }
        var best: [Range<Int>] = [0..<n]
        var bestHeight = columnHeight(heights, 0..<n)
        func consider(_ cuts: [Int]) {
            let bounds = [0] + cuts + [n]
            let ranges = zip(bounds, bounds.dropFirst()).map { $0..<$1 }
            let height = ranges.map { columnHeight(heights, $0) }.max() ?? 0
            if height < bestHeight { bestHeight = height; best = ranges }
        }
        if count == 2 {
            for a in 1..<n { consider([a]) }
        } else {
            // Con 3 columnas hay al menos 3 grupos (`count` nunca pasa del número de grupos).
            for a in 1..<(n - 1) { for b in (a + 1)..<n { consider([a, b]) } }
        }
        return best
    }
}

/// Collage seleccionado: cabecera con las acciones, el collage (encuadre por celda o
/// resultado) a la izquierda y los ajustes de tiempo, transición y pie en una columna.
struct CollageInspector: View {
    @Bindable var doc: SlideshowDocument
    let row: CollageRow
    @State private var showTemplates = false
    @State private var showResult = false

    private var itemIndex: Int? { doc.sequence.firstIndex { $0.id == row.id } }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            header
            // El collage con la proporción de su plantilla (más la línea de ayuda); los ajustes, el resto.
            InspectorSplit(previewWidth: { height in (height - 24) * row.template.aspectRatio }) {
                collageView
            } settings: {
                OptionGroup(title: "Tiempo") {
                    StackedSlider(title: "Mantener", value: Binding(get: { row.hold ?? doc.hold }, set: { doc.setHold($0, for: row.id) }),
                                  in: 0...30, step: 0.5, onReset: row.hold == nil ? nil : { doc.setHold(nil, for: row.id) }) {
                        Text("\(row.hold ?? doc.hold, specifier: "%.1f") s")
                    }
                    Text("Segundos con el collage ya completo, antes de pasar al siguiente.")
                        .font(.caption).foregroundStyle(.secondary)
                }
                OptionGroup(title: "Transición") { TransitionOverrideRow(doc: doc, id: row.id.uuidString, stacked: true) }
                OptionGroup(title: "Pie") { CaptionOverrideRow(doc: doc, id: row.id.uuidString, stacked: true) }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    /// Nombre de la plantilla y acciones: modo de vista, centrar, cambiar plantilla y quitar.
    private var header: some View {
        HStack(spacing: 10) {
            Text(row.template.name).font(.headline).lineLimit(1)
            Spacer()
            CollageViewModePicker(showResult: $showResult)
            if !showResult {
                Button { centerCells() } label: { Label("Centrar", systemImage: "scope") }
                    .help("Volver a centrar todas las fotos en su celda")
                Button { showTemplates = true } label: { Label("Cambiar", systemImage: "rectangle.3.group") }
                    .help("Cambiar la plantilla por otra con el mismo número de fotos")
                    .popover(isPresented: $showTemplates, arrowEdge: .bottom) { templatePicker }
            }
            Button(role: .destructive) { doc.removeCollage(row.id) } label: { Label("Quitar", systemImage: "trash") }
                .help("Quitar este collage del vídeo")
        }
    }

    /// El collage a todo el espacio que quede: resultado final o encuadre arrastrable por celda.
    @ViewBuilder
    private var collageView: some View {
        VStack(alignment: .leading, spacing: 6) {
            if showResult {
                // Con las opciones de collage del vídeo, que son las que se usan al generar.
                CollageResultView(row: row, options: doc.collageOptions.collage)
            } else {
                TemplateView(template: row.template, files: row.files, focusPoints: row.focusPoints, gap: 3) { cell, point in
                    guard let i = itemIndex, doc.sequence[i].focusPoints.indices.contains(cell) else { return }
                    doc.sequence[i].focusPoints[cell] = point
                    doc.sequence[i].manualCells.insert(cell)
                }
                Text("Arrastra cada foto para encuadrarla en su celda.").font(.caption).foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    /// Plantillas con el mismo número de fotos; al elegir una se aplica y se cierra el popover.
    private var templatePicker: some View {
        TemplatePicker(templates: CollageTemplates.filter(photos: row.template.photos, includeOverlap: true), selected: [row.template.id]) { template in
            guard let i = itemIndex else { return }
            doc.sequence[i].templateID = template.id
            doc.sequence[i].focusPoints = Array(repeating: nil, count: template.photos)
            doc.sequence[i].manualCells = []
            showTemplates = false
        }
        .frame(width: 360, height: 440)
        .padding(10)
    }

    private func centerCells() {
        guard let i = itemIndex else { return }
        doc.sequence[i].focusPoints = Array(repeating: nil, count: row.template.photos)
        doc.sequence[i].manualCells = []
    }
}
