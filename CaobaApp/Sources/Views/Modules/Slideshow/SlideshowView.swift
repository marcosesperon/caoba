import SwiftUI
import AVKit
import UniformTypeIdentifiers
import CaobaCore

/// Pestañas de la parte superior de la pantalla.
enum SlideshowTab: String, Hashable {
    case photos, video, extras, music, inspector
}

/// Pantalla del Slideshow: pestañas arriba (origen, vídeo, portada y marca,
/// música y la contextual de lo seleccionado), timeline a toda la anchura
/// abajo y barra de acción al pie.
struct SlideshowView: View {
    @Environment(AppState.self) private var appState
    @State private var document: SlideshowDocument?
    @State private var tab: SlideshowTab = .photos
    @State private var previousTab: SlideshowTab = .photos
    @State private var showComposePicker = false
    @State private var showAddPicker = false
    @State private var expandedFraming: URL?

    var body: some View {
        Group {
            if let document {
                content(document)
            } else {
                Color.clear
            }
        }
        .onAppear {
            if document == nil { document = SlideshowDocument(app: appState) }
            appState.destinationFileTypes = [.mpeg4Movie]
            appState.destinationFileDefaultName = "caoba_slideshow_\(AppState.timestampSuffix()).mp4"
            document?.loadPresetIfNeeded()
        }
    }

    @ViewBuilder
    private func content(_ doc: SlideshowDocument) -> some View {
        @Bindable var doc = doc
        VStack(spacing: 8) {
            tabBar(doc)
            Group {
                switch tab {
                case .photos: SourceTab(doc: doc, showComposePicker: $showComposePicker, showAddPicker: $showAddPicker)
                case .video: ScrollView { VideoTab(doc: doc).padding(.horizontal, 4) }
                case .extras:
                    // Controles a la izquierda y, a la derecha, cómo quedan los textos sobre el vídeo.
                    HStack(alignment: .top, spacing: 14) {
                        ScrollView { ExtrasTab(doc: doc).padding(.horizontal, 4) }
                        TextPreviewPanel(doc: doc).frame(width: 380)
                    }
                case .music: ScrollView { MusicTab(doc: doc).padding(.horizontal, 4) }
                case .inspector: SelectionTab(doc: doc, expandedFraming: $expandedFraming).padding(.horizontal, 4)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            SlideshowTimelineView(doc: doc)
                .frame(height: timelineHeight(doc))
            SlideshowActionBar(doc: doc)
        }
        .onChange(of: appState.sourceFolder) { doc.loadPresetIfNeeded() }
        .onChange(of: appState.configResetToken) { doc.resetToDefaults() }
        .onAppear {
            // Para capturas desde línea de comandos: `--state slideshow.compose=open` abre la hoja de Componer.
            if appState.launchState["slideshow.compose"] != nil { doc.mode = .collage; showComposePicker = true }
            if appState.launchState["slideshow.add"] != nil { doc.mode = .collage; showAddPicker = true }
            // `--state text.demo=card|overlay`: título, cierre y pies de ejemplo; `slideshow.generate=/ruta.mp4` genera una vista previa ahí.
            if let demo = appState.launchState["text.demo"] {
                let carry = appState.launchState["text.carry"] != nil
                var title = TextCard(text: "Alex & Sofi", subtitle: "Biar, julio de 2025", background: demo == "overlay" ? nil : .black, duration: carry ? 3 : 4, anchor: TextCard.startAnchor)
                title.carryNext = carry; title.carryNextSeconds = 2
                var closing = TextCard(text: "Gracias", subtitle: "caobafoto.com", background: .black, duration: carry ? 3 : 4, anchor: TextCard.endAnchor)
                closing.carryPrevious = carry; closing.carryPreviousSeconds = 2
                doc.textCards = [title, closing]
                // `text.section=1`: un título de sección superpuesto ante el tercer elemento (cuando haya fotos).
                if appState.launchState["text.section"] != nil {
                    Task {
                        var attempts = 0
                        while doc.items.filter({ !$0.isText }).count < 3 && attempts < 40 { try? await Task.sleep(for: .milliseconds(250)); attempts += 1 }
                        guard let third = doc.items.filter({ !$0.isText }).dropFirst(2).first else { return }
                        var section = TextCard(text: "Segunda parte", subtitle: "", background: nil, duration: 3, anchor: third.id)
                        section.style = doc.titleStyle; section.style?.anchor = .bottomRight; section.style?.animation = .slideLeft; section.style?.animationDuration = 0.75
                        doc.textCards.append(section)
                    }
                }
                if carry {
                    doc.transitionChoice = .kind(.crossfade); doc.transitionDuration = 1; doc.itemTransitions = [:]
                    doc.titleStyle.animation = .fade; doc.titleStyle.animationDuration = 0.5; doc.titleStyle.exitAnimation = .fade; doc.titleStyle.exitDuration = 0.5
                }
                if let anim = appState.launchState["text.animation"].flatMap(TextAnimation.init(rawValue:)) {
                    doc.titleStyle.animation = anim; doc.titleStyle.animationDuration = 1
                    doc.captionStyle.animation = anim; doc.captionStyle.animationDuration = 0.75
                }
                doc.captionPattern = "{n} de {total} · {nombre}"
                tab = .extras
            }
            if let path = appState.launchState["slideshow.generate"] {
                Task {
                    var attempts = 0
                    while doc.files.isEmpty && attempts < 40 { try? await Task.sleep(for: .milliseconds(250)); attempts += 1 }
                    doc.generateForTest(to: URL(fileURLWithPath: path))
                }
            }
            // `--state slideshow.tab=video|extras|music`: abre esa pestaña.
            if let name = appState.launchState["slideshow.tab"], let wanted = SlideshowTab(rawValue: name) { tab = wanted }
            // `--state slideshow.rhythm=1`: ajusta al ritmo en cuanto haya fotos y pistas (para pruebas).
            if appState.launchState["slideshow.rhythm"] != nil {
                Task { await autoAdjustToRhythm(doc) }
            }
        }
        .onChange(of: doc.snapshot) { doc.scheduleSave() }
        .onChange(of: doc.files) { doc.pruneSequence() }
        .onChange(of: appState.jobRunner.isRunning) { _, running in if !running { doc.jobFinished() } }
        .onChange(of: doc.selection) { _, selection in
            // Seleccionar algo abre su pestaña; quitar la selección vuelve a la anterior.
            if selection == .none {
                if tab == .inspector { tab = previousTab }
            } else {
                if tab != .inspector { previousTab = tab }
                tab = .inspector
            }
        }
        .onDeleteCommand { doc.deleteSelection() }
        .onMoveCommand { direction in
            switch direction {
            case .left: doc.moveSelection(-1)
            case .right: doc.moveSelection(1)
            default: break
            }
        }
        .sheet(item: $doc.previewURL) { url in VideoPreviewSheet(url: url) }
        .sheet(item: $expandedFraming) { url in KenBurnsFramingSheet(doc: doc, photo: url) }
        .sheet(isPresented: $showComposePicker) {
            TemplatePickerSheet(title: "Componer secuencia",
                                subtitle: doc.composeSheet.mode == .random
                                    ? "Elige qué plantillas pueden usarse. Se repartirán al azar entre las \(doc.files.count) fotos marcadas."
                                    : "Elige qué plantillas pueden usarse. Se analizarán las \(doc.files.count) fotos marcadas para dar a cada grupo la plantilla que mejor le encaje.",
                                templates: { CollageTemplates.filter(photos: $0.photos, aspectLabel: $0.aspect, includeOverlap: true, type: $0.type) },
                                filters: $doc.composeSheet.filters,
                                selection: $doc.selectedTemplates, confirmTitle: "Componer",
                                composeMode: $doc.composeSheet.mode, allowReorder: $doc.composeSheet.allowReorder) {
                doc.compose()
            }
        }
        .sheet(isPresented: $showAddPicker) {
            TemplatePickerSheet(title: "Añadir collage",
                                subtitle: "Quedan \(doc.files.count - doc.rows.reduce(0) { $0 + $1.files.count }) fotos sin asignar.",
                                templates: { f in doc.visibleTemplatesForAdd.filter { (f.photos == nil || $0.photos == f.photos) && (f.aspect == nil || $0.aspectLabel == f.aspect) && (f.type == nil || (f.type == .overlap) == $0.overlap) } },
                                filters: $doc.addFilters,
                                selection: .constant([]), confirmTitle: nil, onPick: { doc.addTemplate($0); showAddPicker = false }) {}
        }
    }

    /// Espera a que haya fotos y pistas, va a Música y ajusta al ritmo (solo para pruebas).
    private func autoAdjustToRhythm(_ doc: SlideshowDocument) async {
        var attempts = 0
        while (doc.files.isEmpty || doc.tracks.isEmpty) && attempts < 40 {
            try? await Task.sleep(for: .milliseconds(250))
            attempts += 1
        }
        tab = .music
        await doc.adjustToRhythm()
    }

    private func tabBar(_ doc: SlideshowDocument) -> some View {
        // Título en su propia fila y las pestañas debajo, siempre.
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                ModuleTitle(title: "Slideshow").fixedSize()
                Spacer()
                if doc.isAssigning { ProgressView().controlSize(.small) }
            }
            tabPicker(doc)
        }
    }

    private func tabPicker(_ doc: SlideshowDocument) -> some View {
        Picker("", selection: $tab) {
            Text(doc.mode == .photos ? "Fotos" : "Collages").tag(SlideshowTab.photos)
            Text("Vídeo").tag(SlideshowTab.video)
            Text("Portada y texto").tag(SlideshowTab.extras)
            Text("Música").tag(SlideshowTab.music)
            if doc.selection != .none {
                Text(selectionTitle(doc)).tag(SlideshowTab.inspector)
            }
        }
        .pickerStyle(.segmented)
        .labelsHidden()
        .fixedSize()
    }

    /// Título corto de la pestaña contextual: el nombre completo ya se ve dentro.
    /// Un título largo obligaría a todos los segmentos a ser igual de anchos.
    private func selectionTitle(_ doc: SlideshowDocument) -> String {
        switch doc.selection {
        case .none: return ""
        case .cover: return String(localized: "Portada")
        case .credits: return String(localized: "Créditos")
        case .text: return String(localized: "Texto")
        case .photo: return String(localized: "Foto")
        case .track: return String(localized: "Pista")
        case .collage(let id): return String(localized: "Collage \((doc.rows.firstIndex { $0.id == id } ?? 0) + 1)")
        }
    }

    /// Altura del timeline según el número de pistas (con tope).
    private func timelineHeight(_ doc: SlideshowDocument) -> CGFloat {
        let base: CGFloat = 36 + 18 + 96 + 12 + 30 // cabecera, regla, tarjetas, márgenes, botón añadir
        return min(400, base + CGFloat(doc.tracks.count) * 29)
    }
}

/// Pestaña de origen: modo, lista de fotos y, en Collages, sus acciones.
struct SourceTab: View {
    @Bindable var doc: SlideshowDocument
    @Binding var showComposePicker: Bool
    @Binding var showAddPicker: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 10) {
                LabeledRow("Modo") {
                    Picker("", selection: $doc.mode) {
                        Text("Fotos").tag(SlideshowDocument.Mode.photos)
                        Text("Collages").tag(SlideshowDocument.Mode.collage)
                    }
                    .pickerStyle(.segmented).fixedSize()
                    .labelsHidden()
                }
                Divider().frame(height: 18)
                if doc.mode == .photos {
                    Menu("Asignar efectos") {
                        Button("Ninguno a todas") { doc.assignAll(.none) }
                        Button("Aleatorio") { doc.assignAll(.random) }
                        Button("Automático (saliencia)") { doc.assignAuto(.saliency) }
                        Button("Caras") { doc.assignAuto(.faces) }
                    }
                    .fixedSize()
                    .disabled(doc.files.isEmpty || doc.isAssigning)
                    Text("Marca las fotos que entran en el vídeo y ordénalas arrastrando; el timeline de abajo se actualiza al momento.")
                        .font(.caption).foregroundStyle(.secondary)
                } else {
                    Button("Componer") { showComposePicker = true }.disabled(doc.files.isEmpty)
                    Button("Añadir") { showAddPicker = true }.disabled(doc.visibleTemplatesForAdd.isEmpty)
                    Menu("Ajustar foco") {
                        Button("Automático (saliencia)") { doc.adjustFocus(.saliency) }
                        Button("Caras") { doc.adjustFocus(.faces) }
                        Button("Centrar todo") { doc.adjustFocus(.center) }
                    }
                    .fixedSize()
                    .disabled(doc.sequence.isEmpty || doc.isAssigning)
                    Button("Vaciar") { doc.sequence = []; doc.selection = .none }.disabled(doc.sequence.isEmpty)
                    if let progress = doc.composeProgress {
                        ComposeProgressView(progress: progress) { doc.cancelCompose() }
                    } else {
                        Text("\(doc.rows.reduce(0) { $0 + $1.files.count }) de \(doc.files.count) fotos asignadas · \(doc.rows.count) collages")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                }
                Spacer()
            }
            FileListView(allowsReorder: true)
        }
    }
}

/// Barra inferior: destino, duración, vista previa y generar.
struct SlideshowActionBar: View {
    @Environment(AppState.self) private var appState
    let doc: SlideshowDocument

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "arrow.down.doc").foregroundStyle(.secondary)
            Text(appState.destinationFile?.path ?? String(localized: "Elige dónde guardar el vídeo"))
                .lineLimit(1).truncationMode(.middle)
                .foregroundStyle(appState.destinationFile == nil ? .secondary : .primary)
                .frame(maxWidth: .infinity, alignment: .leading)
            Button("Elegir…") { appState.chooseDestinationFile(contentTypes: appState.destinationFileTypes) }
            Divider().frame(height: 18)
            Button("Vista previa") { doc.preview() }.disabled(!doc.canPreview)
            Button("Generar vídeo") { doc.generate() }
                .buttonStyle(.borderedProminent)
                .disabled(!doc.canGenerate)
        }
        .padding(10)
        .background(Color(nsColor: .controlBackgroundColor))
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }
}

/// Hoja de selección de plantillas (componer o añadir).
struct TemplatePickerSheet: View {
    @Environment(\.dismiss) private var dismiss
    let title: LocalizedStringKey
    let subtitle: String
    let templates: (TemplateFilterState) -> [CollageTemplate]
    @Binding var filters: TemplateFilterState
    @Binding var selection: Set<String>
    /// Si hay título de confirmación se eligen varias; si no, un clic elige una.
    let confirmTitle: LocalizedStringKey?
    var onPick: ((CollageTemplate) -> Void)? = nil
    /// Solo en Componer: selector de reparto y casilla de reordenar.
    var composeMode: Binding<ComposeMode>? = nil
    var allowReorder: Binding<Bool>? = nil
    let onConfirm: () -> Void

    private var visible: [CollageTemplate] { templates(filters) }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title).font(.headline)
            Text(subtitle).font(.callout).foregroundStyle(.secondary)
            if let composeMode, let allowReorder {
                ComposeModeControls(mode: composeMode, allowReorder: allowReorder)
            }
            TemplateFilters(filters: $filters, showType: true)
            TemplatePicker(templates: visible, selected: confirmTitle == nil ? [] : selection) { template in
                if let onPick { onPick(template); return }
                if selection.contains(template.id) { selection.remove(template.id) } else { selection.insert(template.id) }
            }
            .frame(minHeight: 320)
            HStack {
                if confirmTitle != nil {
                    Toggle("Todas las visibles", isOn: Binding(
                        get: { !visible.isEmpty && visible.allSatisfy { selection.contains($0.id) } },
                        set: { on in if on { selection.formUnion(visible.map(\.id)) } else { selection.subtract(visible.map(\.id)) } }
                    )).toggleStyle(.checkbox)
                }
                Spacer()
                Button("Cancelar") { dismiss() }.keyboardShortcut(.cancelAction)
                if let confirmTitle {
                    Button(confirmTitle) { onConfirm(); dismiss() }.buttonStyle(.borderedProminent).disabled(selection.isEmpty)
                }
            }
        }
        .padding(20)
        .frame(width: 720, height: composeMode == nil ? 600 : 660)
    }
}

/// Reproductor de la vista previa.
struct VideoPreviewSheet: View {
    @Environment(\.dismiss) private var dismiss
    let url: URL
    @State private var player: AVPlayer?

    var body: some View {
        VStack {
            VideoPlayer(player: player)
                .frame(minWidth: 720, minHeight: 405)
            HStack {
                Text("Vista previa: primeras fotos a media resolución, sin normalizar el audio.").font(.caption).foregroundStyle(.secondary)
                Spacer()
                Button("Cerrar") { dismiss() }.keyboardShortcut(.cancelAction)
            }
        }
        .padding()
        .onAppear { player = AVPlayer(url: url); player?.play() }
        .onDisappear { player?.pause(); TempFiles.remove(url) }
    }
}

/// Campo de texto para tiempos "m:ss" (acepta también segundos sueltos).
struct TimecodeField: View {
    @Binding var seconds: Double
    @State private var text = ""

    var body: some View {
        TextField("0:00", text: $text)
            .frame(width: 56)
            .monospacedDigit()
            .onAppear { text = Self.format(seconds) }
            .onChange(of: seconds) { text = Self.format(seconds) }
            .onSubmit { commit() }
    }

    private func commit() {
        if let parsed = Self.parse(text) { seconds = parsed }
        text = Self.format(seconds)
    }

    static func format(_ s: Double) -> String {
        let total = Int(s.rounded())
        return String(format: "%d:%02d", total / 60, total % 60)
    }

    static func parse(_ raw: String) -> Double? {
        let parts = raw.trimmingCharacters(in: .whitespaces).split(separator: ":")
        if parts.count == 2, let m = Double(parts[0]), let sec = Double(parts[1]) { return m * 60 + sec }
        if parts.count == 1, let sec = Double(parts[0]) { return sec }
        return nil
    }
}
