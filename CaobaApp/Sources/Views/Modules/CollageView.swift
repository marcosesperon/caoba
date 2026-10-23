import SwiftUI
import CaobaCore

/// Una posición de la secuencia de collages: plantilla elegida y foco por celda.
struct SequenceItem: Identifiable, Equatable {
    var id = UUID()
    var templateID: String
    var focusPoints: [CGPoint?]
    /// Celdas cuyo foco ha ajustado el usuario a mano (no se pisan al "Ajustar foco").
    var manualCells: Set<Int> = []
    /// Segundos que se mantiene el collage completo en el slideshow; `nil` = valor global.
    var hold: Double? = nil

    var template: CollageTemplate? { CollageTemplates.template(id: templateID) }
}

/// Qué se hace en Collage: secuencia de plantillas, plantillas al azar o carrusel de Instagram.
enum CollageMode: String, Hashable {
    case sequential, random, carousel
}

/// Collage estático: secuencia de plantillas (o selección aleatoria, o carrusel), editor de
/// enfoque y opciones de salida. Guarda en carpeta con nombres automáticos.
struct CollageView: View {
    @Environment(AppState.self) private var appState

    @State private var mode: CollageMode = .sequential
    // Carrusel: formato, tramos encadenados y ajustes de Componer.
    @State private var carouselFormat: CarouselFormat = .portrait4x5
    @State private var carouselSequence: [SequenceItem] = []
    @State private var carouselBases: Set<String> = []
    @State private var carouselComposeMode: ComposeMode = .random
    @State private var carouselReorder = false
    @State private var sequence: [SequenceItem] = []
    @State private var randomSelection: Set<String> = []
    @State private var composeSheet = ComposeSheetState()
    /// Carpeta cuyos ajustes están cargados; evita guardar mientras se restauran.
    @State private var loadedFolder: URL?
    @State private var photosFilter: Int?
    @State private var aspectFilter: String?
    @State private var typeFilter: CollageTemplates.TemplateType?
    @State private var focusMode: FocusMode = .saliency
    /// Reparto sorteado de «Aleatorias»: es lo que se ve en la previsualización y lo que se genera.
    @State private var randomSequence: [SequenceItem] = []
    /// Mientras se calculan los focos del reparto (con «Automático» o «Caras»).
    @State private var drawTask: Task<Void, Never>?
    /// Alto del bloque de abajo; se recuerda entre sesiones.
    @AppStorage("collage.sequenceBlockHeight") private var sequenceBlockHeight = 260.0
    /// Collage del reparto abierto en el editor de enfoque.
    @State private var randomEditingIndex: Int?

    @State private var longestSide = 3000
    @State private var gap = 10.0
    @State private var background: CanvasColor = .white
    @State private var cornerRadius = 0.0
    @State private var shadow = true
    @State private var title = ""
    @State private var quality = 90.0
    @State private var logoURL: URL?
    @State private var logoPosition: OverlayPosition = .bottomRight
    @State private var logoSize = 20.0
    @State private var logoOpacity = 80.0

    @State private var presetWarning: String?
    private let detector = FocusDetector()

    /// Ajustes de salida actuales, para presets y para recordarlos entre sesiones.
    private var settings: CollageSettings {
        CollageSettings(longestSide: longestSide, gap: gap, background: background, cornerRadius: cornerRadius, shadow: shadow, title: title, quality: quality,
                        logoPath: logoURL?.path, logoPosition: logoPosition, logoSize: logoSize, logoOpacity: logoOpacity)
    }

    /// Aplica un preset; si su logo ya no existe, se aplica el resto y se avisa.
    private func apply(_ s: CollageSettings) {
        longestSide = s.longestSide; gap = s.gap; background = s.background; cornerRadius = s.cornerRadius
        shadow = s.shadow; title = s.title; quality = s.quality
        logoPosition = s.logoPosition; logoSize = s.logoSize; logoOpacity = s.logoOpacity
        if let path = s.logoPath {
            if FileManager.default.fileExists(atPath: path) {
                logoURL = URL(fileURLWithPath: path)
                presetWarning = nil
            } else {
                logoURL = nil
                presetWarning = L("No se encuentra el logo: ") + (path as NSString).lastPathComponent
            }
        } else {
            logoURL = nil
            presetWarning = nil
        }
    }

    private var files: [URL] { appState.checkedFiles }
    private var rows: [CollageRow] { CollageSequenceEditor.rows(from: sequence, files: files) }
    private var randomRows: [CollageRow] { CollageSequenceEditor.rows(from: randomSequence, files: files) }
    private var carouselRows: [CollageRow] { CollageSequenceEditor.rows(from: carouselSequence, files: files) }
    private var visibleTemplates: [CollageTemplate] { CollageTemplates.filter(photos: photosFilter, aspectLabel: aspectFilter, type: typeFilter) }

    private var options: CollageOptions {
        CollageOptions(longestSide: longestSide, gap: gap, background: background, cornerRadius: cornerRadius,
                       shadowIntensity: shadow ? 100 : 0, title: title, quality: Int(quality),
                       logo: logoURL.map { LogoOptions(url: $0, position: logoPosition, sizePercent: logoSize, opacity: logoOpacity) })
    }

    private var canRun: Bool {
        guard !files.isEmpty, appState.destinationFolder != nil else { return false }
        switch mode {
        case .sequential: return !rows.isEmpty
        // En «Aleatorias», cuando el reparto ya tiene sus focos (se genera tal cual se ve).
        case .random: return !randomRows.isEmpty && drawTask == nil
        case .carousel: return !carouselRows.isEmpty
        }
    }

    var body: some View {
        // Arriba opciones y fotos; abajo, a todo el ancho, la secuencia dibujada. Divisor ajustable.
        // Debajo de todo, la carpeta de salida con «Generar» al final.
        VStack(spacing: 12) {
            BottomSplit(bottomHeight: $sequenceBlockHeight) {
                HSplitView {
                    optionsColumn
                    FileListView(allowsReorder: true).frame(minWidth: 320)
                }
            } bottom: {
                sequenceBlock
            }
            DestinationBar(kind: .outputFolder) {
                Button("Generar") { run() }
                    .buttonStyle(.borderedProminent)
                    .disabled(!canRun)
            }
        }
        .sheet(item: randomEditingTarget) { target in
            FocusEditorSheet(sequence: $randomSequence, rows: randomRows, index: target.index, options: options)
        }
        .onAppear(perform: setUp)
        .onChange(of: appState.sourceFolder) { loadFolderSettings() }
        .onChange(of: appState.configResetToken) {
            composeSheet = ComposeSheetState(); randomSelection = []
            carouselFormat = .portrait4x5; carouselComposeMode = .random; carouselReorder = false
            carouselBases = Set(CarouselTemplates.templates(for: .portrait4x5).map(CarouselTemplates.baseID(of:)))
        }
        .onChange(of: composeSheet) { saveFolderSettings() }
        .onChange(of: randomSelection) { saveFolderSettings(); randomInputsChanged() }
        .onChange(of: files) { randomInputsChanged() }
        .onChange(of: focusMode) { randomInputsChanged() }
        .onChange(of: mode, modeChanged)
        .onChange(of: carouselSettings) { saveFolderSettings() }
        .onChange(of: settings) { PresetStore.shared.saveLast(settings, module: .collage) }
    }

    /// Al abrir: ajustes recordados, los de la carpeta y las opciones de arranque para capturas.
    private func setUp() {
        if let last = PresetStore.shared.last(.collage, as: CollageSettings.self) { apply(last) }
        loadFolderSettings()
        // Para capturas desde línea de comandos: `--state collage.tab=random` abre en "Aleatorias".
        if appState.launchState["collage.tab"] == "random" { mode = .random; photosFilter = 3 }
        // `--state collage.tab=carousel`: abre en «Carrusel».
        if appState.launchState["collage.tab"] == "carousel" { mode = .carousel }
        // `--state collage.run=1`: pulsa «Generar» en cuanto se puede (para pruebas).
        if appState.launchState["collage.run"] != nil {
            Task {
                var attempts = 0
                while !canRun && attempts < 60 { try? await Task.sleep(for: .milliseconds(250)); attempts += 1 }
                if canRun { run() }
            }
        }
        if let aspect = appState.launchState["collage.aspect"] { aspectFilter = aspect }
        // `--state collage.photos=9`: «Aleatorias» filtrado por ese número de fotos.
        if let photos = appState.launchState["collage.photos"].flatMap(Int.init) { mode = .random; photosFilter = photos }
        // `--state collage.type=round`: «Aleatorias» con ese tipo de plantilla.
        if let type = appState.launchState["collage.type"].flatMap(CollageTemplates.TemplateType.init(rawValue:)) { mode = .random; typeFilter = type }
    }

    /// Al entrar en «Aleatorias» sin reparto, se sortea uno.
    private func modeChanged() {
        if mode == .random, randomSequence.isEmpty { drawRandom() }
    }

    private var randomEditingTarget: Binding<RandomTarget?> {
        Binding(get: { randomEditingIndex.map { RandomTarget(index: $0) } }, set: { randomEditingIndex = $0?.index })
    }

    /// Columna de opciones: modo, plantillas o formato, salida y logo.
    private var optionsColumn: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                ModuleTitle(title: "Collage")
                Spacer()
                PresetBar(module: .collage, current: settings, defaults: CollageSettings(), apply: apply)
            }
            if let presetWarning {
                Text(presetWarning).font(.caption).foregroundStyle(Color.accentColor)
            }
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    LabeledRow("Plantillas") {
                        Picker("", selection: $mode) {
                            Text("Secuencia").tag(CollageMode.sequential)
                            Text("Aleatorias").tag(CollageMode.random)
                            Text("Carrusel").tag(CollageMode.carousel)
                        }
                        .pickerStyle(.segmented)
                        .labelsHidden()
                    }
                    if mode == .random {
                        randomSection
                    } else if mode == .carousel {
                        OptionGroup(title: "Carrusel") {
                            LabeledRow("Formato") {
                                Picker("", selection: $carouselFormat) {
                                    ForEach(CarouselFormat.allCases) { f in
                                        Text("\(f.label) · \(f.slideSize.width)×\(f.slideSize.height)").tag(f)
                                    }
                                }
                                .frame(maxWidth: 220, alignment: .leading).labelsHidden()
                            }
                        }
                    }
                    OptionGroup(title: "Salida") {
                        LabeledRow("Lado mayor") {
                            TextField("", value: $longestSide, format: .number).frame(width: 90)
                            Text("px").foregroundStyle(.secondary)
                            Spacer()
                            Text(estimate).font(.caption).foregroundStyle(.secondary)
                        }
                        LabeledSlider(title: "Separación", value: $gap, in: 0...100, step: 1) { Text("\(Int(gap)) px") }
                        LabeledRow("Fondo") {
                            BackgroundPicker(selection: $background)
                        }
                        LabeledSlider(title: "Esquinas", value: $cornerRadius, in: 0...200, step: 1) { Text("\(Int(cornerRadius)) px") }
                        Toggle("Sombra en plantillas superpuestas", isOn: $shadow)
                        TextField("Título", text: $title)
                        LabeledSlider(title: "Calidad", value: $quality, in: 1...100, step: 1) { Text("\(Int(quality))") }
                    }
                    LogoOptionsGroup(url: $logoURL, position: $logoPosition, size: $logoSize, opacity: $logoOpacity)
                }
            }
        }
        .padding(.trailing, 8)
        // Ancho mínimo en el que caben todos los controles; por debajo se cortaban por los lados.
        .frame(minWidth: 400, idealWidth: 440)
    }

    /// Bloque de abajo según el modo: la secuencia, el reparto de «Aleatorias» o el carrusel.
    @ViewBuilder
    private var sequenceBlock: some View {
        switch mode {
        case .sequential:
            CollageSequenceEditor(sequence: $sequence, selectedTemplates: $randomSelection, composeState: $composeSheet, files: files, options: options)
        case .random:
            SequenceBlock(title: "Reparto") {
                Button("Otro reparto") { drawRandom() }
                    .disabled(randomSelection.isEmpty || files.isEmpty)
                    .help("Vuelve a sortear qué plantilla le toca a cada grupo de fotos")
                if drawTask != nil { ProgressView().controlSize(.small) }
                Spacer()
                Text("\(randomRows.reduce(0) { $0 + $1.files.count }) de \(files.count) fotos · \(randomRows.count) collages")
                    .font(.caption).foregroundStyle(.secondary)
            } content: {
                CollagePreview(rows: randomRows, options: options, emptyMessage: "Marca plantillas en «Plantillas permitidas» para sortear un reparto.",
                               onSelect: { randomEditingIndex = $0 },
                               onMove: { moveItem(&randomSequence, moved: $0, onto: $1) }) { index in
                    Button("Editar enfoque") { randomEditingIndex = index }
                    Button("Quitar", role: .destructive) {
                        if randomRows.indices.contains(index) { let id = randomRows[index].id; randomSequence.removeAll { $0.id == id } }
                    }
                }
            }
        case .carousel:
            CarouselEditor(format: $carouselFormat, sequence: $carouselSequence, selectedBases: $carouselBases,
                           composeMode: $carouselComposeMode, allowReorder: $carouselReorder, files: files, options: options)
        }
    }

    private struct RandomTarget: Identifiable { let index: Int; var id: Int { index } }

    /// Restaura los ajustes de Componer guardados en el `.caoba` de la carpeta.
    private func loadFolderSettings() {
        guard appState.sourceFolder != loadedFolder else { return }
        loadedFolder = appState.sourceFolder
        let folderSettings = appState.sourceFolder.flatMap(CollageFolderSettings.load(from:))
        let saved = folderSettings?.compose
        composeSheet = ComposeSheetState(saved)
        randomSelection = Set(saved?.selectedTemplates ?? [])
        // Carrusel: formato y Componer guardados; por defecto, 4:5 y todos los tramos marcados.
        let carousel = folderSettings?.carousel
        carouselFormat = carousel?.format.flatMap(CarouselFormat.init(rawValue:)) ?? .portrait4x5
        carouselComposeMode = carousel?.mode.flatMap(ComposeMode.init(rawValue:)) ?? .random
        carouselReorder = carousel?.allowReorder ?? false
        carouselBases = Set(carousel?.templates ?? CarouselTemplates.templates(for: .portrait4x5).map(CarouselTemplates.baseID(of:)))
    }

    /// Lo que el carrusel guarda en la carpeta.
    private var carouselSettings: CarouselSettings {
        CarouselSettings(format: carouselFormat.rawValue, mode: carouselComposeMode.rawValue, allowReorder: carouselReorder, templates: carouselBases.sorted())
    }

    /// Guarda los ajustes de Componer en el `.caoba` de la carpeta (sección `collage`).
    private func saveFolderSettings() {
        guard let folder = appState.sourceFolder, folder == loadedFolder else { return }
        let settings = CollageFolderSettings(compose: composeSheet.settings(selectedTemplates: randomSelection), carousel: carouselSettings)
        if (try? settings.save(in: folder)) != nil { appState.markFolderConfigSaved() }
    }

    private var randomSection: some View {
        OptionGroup(title: "Plantillas permitidas") {
            TemplateFilters(filters: Binding(
                get: { TemplateFilterState(photos: photosFilter, aspect: aspectFilter, type: typeFilter) },
                set: { photosFilter = $0.photos; aspectFilter = $0.aspect; typeFilter = $0.type }))
            LabeledRow("Enfoque") {
                Picker("", selection: $focusMode) {
                    Text("Centro").tag(FocusMode.center)
                    Text("Automático").tag(FocusMode.saliency)
                    Text("Caras").tag(FocusMode.faces)
                }
                .labelsHidden().fixedSize()
            }
            HStack {
                HiddenSelectionNotice(selection: $randomSelection, visible: visibleTemplates)
                Spacer()
                Toggle("Todas las visibles", isOn: Binding(
                    get: { !visibleTemplates.isEmpty && visibleTemplates.allSatisfy { randomSelection.contains($0.id) } },
                    set: { on in if on { randomSelection.formUnion(visibleTemplates.map(\.id)) } else { randomSelection.subtract(visibleTemplates.map(\.id)) } }
                )).toggleStyle(.checkbox).controlSize(.small)
            }
            TemplatePicker(templates: visibleTemplates, selected: randomSelection) { template in
                if randomSelection.contains(template.id) { randomSelection.remove(template.id) } else { randomSelection.insert(template.id) }
            }
            .frame(height: 260)
        }
    }

    private var estimate: String {
        if mode == .carousel {
            let slides = Carousel.slideCount(CollageSequenceEditor.rows(from: carouselSequence, files: files))
            return "\(max(1, slides)) × \(carouselFormat.slideSize.width) × \(carouselFormat.slideSize.height) px"
        }
        guard let first = rows.first?.template ?? randomSelection.first.flatMap(CollageTemplates.template(id:)) else { return "" }
        let size = first.canvasSize(longestSide: min(CollageOptions.maxDimension, max(100, longestSide)))
        return "≈ \(size.width) × \(size.height) px"
    }

    private func run() {
        guard let folder = appState.destinationFolder else { return }
        let opts = options
        let mode = mode
        // En «Aleatorias» se genera el reparto que se ve en la previsualización.
        let fixedRows = mode == .random ? randomRows : rows
        if mode == .carousel {
            // Una carpeta nueva con 01.jpg, 02.jpg… y la panorámica.
            let carouselRows = carouselRows
            let format = carouselFormat
            appState.jobRunner.run(openURL: folder) { progress in
                _ = try Carousel.generate(carouselRows, format: format, options: opts, outputFolder: folder, progress: progress)
                return BatchSummary(processed: Carousel.slideCount(Carousel.limited(carouselRows)))
            }
            return
        }
        appState.jobRunner.run(openURL: folder) { progress in
            let (summary, _) = try await CollageRenderer.generate(rows: fixedRows, options: opts, outputFolder: folder, progress: progress)
            return summary
        }
    }

    // MARK: Reparto de «Aleatorias»

    /// Han cambiado las fotos, las plantillas marcadas o el enfoque: en «Aleatorias» se
    /// sortea de nuevo; en los otros modos se tira el reparto y se sorteará al volver.
    private func randomInputsChanged() {
        if mode == .random { drawRandom() } else { drawTask?.cancel(); drawTask = nil; randomSequence = [] }
    }

    /// Sortea un reparto con las plantillas marcadas y, si el enfoque no es «Centro»,
    /// le calcula los focos. Lo que salga es lo que se ve y lo que se genera.
    private func drawRandom() {
        drawTask?.cancel()
        drawTask = nil
        let templates = randomSelection.compactMap(CollageTemplates.template(id:))
        let grouped = CollageRenderer.group(files: files, templates: templates, mode: .random).rows
        randomSequence = grouped.map { SequenceItem(id: $0.id, templateID: $0.template.id, focusPoints: $0.focusPoints) }
        guard focusMode != .center, !grouped.isEmpty else { return }
        let mode = focusMode
        let detector = detector
        drawTask = Task {
            for row in grouped {
                for (cell, url) in row.files.enumerated() {
                    let point = await detector.focus(for: url, mode: mode).point
                    guard !Task.isCancelled else { return }
                    // Si mientras tanto se ha tocado ese encuadre a mano, se respeta.
                    if let i = randomSequence.firstIndex(where: { $0.id == row.id }),
                       !randomSequence[i].manualCells.contains(cell), randomSequence[i].focusPoints.indices.contains(cell) {
                        randomSequence[i].focusPoints[cell] = point
                    }
                }
            }
            drawTask = nil
        }
    }
}

/// Opciones de logo compartidas por Collage y Contact Sheet.
struct LogoOptionsGroup: View {
    @Binding var url: URL?
    @Binding var position: OverlayPosition
    @Binding var size: Double
    @Binding var opacity: Double

    var body: some View {
        OptionGroup(title: "Logo") {
            HStack {
                Text(url?.lastPathComponent ?? String(localized: "Sin logo"))
                    .lineLimit(1).truncationMode(.middle).frame(maxWidth: .infinity, alignment: .leading)
                Button("Elegir…") {
                    let panel = NSOpenPanel()
                    panel.allowedContentTypes = [.png, .jpeg]
                    if panel.runModal() == .OK { url = panel.url }
                }
                if url != nil { Button("Quitar") { url = nil } }
            }
            if url != nil {
                LabeledRow("Posición") {
                    Picker("", selection: $position) {
                        Text("Abajo derecha").tag(OverlayPosition.bottomRight)
                        Text("Abajo izquierda").tag(OverlayPosition.bottomLeft)
                        Text("Arriba derecha").tag(OverlayPosition.topRight)
                        Text("Arriba izquierda").tag(OverlayPosition.topLeft)
                        Text("Centro").tag(OverlayPosition.center)
                    }
                    .labelsHidden()
                }
                LabeledSlider(title: "Tamaño", value: $size, in: 1...100, step: 1) { Text("\(Int(size)) %") }
                LabeledSlider(title: "Opacidad", value: $opacity, in: 0...100, step: 1) { Text("\(Int(opacity)) %") }
            }
        }
    }
}

/// Editor de enfoque: la plantilla a tamaño grande, cada foto se arrastra
/// dentro de su celda. Permite cambiar de collage y de plantilla.
struct FocusEditorSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(AppState.self) private var appState
    @Binding var sequence: [SequenceItem]
    let rows: [CollageRow]
    @State var index: Int
    /// Opciones reales de salida, para la vista «Resultado».
    let options: CollageOptions
    var includeOverlap = false
    @State private var showTemplates = false
    @State private var showResult = false

    private var row: CollageRow? { rows.indices.contains(index) ? rows[index] : nil }
    private var item: SequenceItem? { row.flatMap { r in sequence.first { $0.id == r.id } } }

    var body: some View {
        VStack(spacing: 10) {
            HStack {
                Button { index -= 1 } label: { Image(systemName: "chevron.left") }.disabled(index <= 0)
                Text("Collage \(index + 1) de \(rows.count)").font(.headline)
                Button { index += 1 } label: { Image(systemName: "chevron.right") }.disabled(index >= rows.count - 1)
                CollageViewModePicker(showResult: $showResult).padding(.leading, 8)
                Spacer()
                if !showResult {
                    Toggle("Cambiar plantilla", isOn: $showTemplates).toggleStyle(.button)
                    Button("Centrar celdas") { resetFocus() }
                }
            }
            HStack(spacing: 12) {
                if let row, let item {
                    if showResult {
                        CollageResultView(row: row, options: options)
                            .background(Color(nsColor: .windowBackgroundColor))
                    } else {
                        TemplateView(template: row.template, files: row.files, focusPoints: item.focusPoints, gap: 4) { cell, point in
                            updateFocus(cell: cell, point: point)
                        }
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .background(Color(nsColor: .windowBackgroundColor))
                    }
                } else {
                    ContentUnavailableView("Sin collage", systemImage: "square.grid.2x2")
                }
                if showTemplates, !showResult, let row {
                    VStack(alignment: .leading) {
                        Text("Plantillas de \(row.template.photos) fotos").font(.callout).foregroundStyle(.secondary)
                        TemplatePicker(templates: CollageTemplates.filter(photos: row.template.photos, includeOverlap: includeOverlap), selected: [row.template.id]) { template in
                            changeTemplate(template)
                        }
                    }
                    .frame(width: 240)
                }
            }
            Text(showResult
                 ? "Así quedará el collage con las opciones de salida actuales. Vuelve a «Encuadre» para corregir cualquier foto."
                 : "Arrastra cada foto para encuadrarla. Los encuadres manuales se conservan al usar «Ajustar foco».")
                .font(.caption).foregroundStyle(.secondary)
            HStack { Spacer(); Button("Hecho") { dismiss() }.keyboardShortcut(.defaultAction) }
        }
        .padding(16)
        .frame(minWidth: 900, minHeight: 620)
        .onAppear {
            // Para capturas desde línea de comandos: `--state collage.editor=result` abre en «Resultado».
            if appState.launchState["collage.editor"] == "result" { showResult = true }
        }
    }

    private func updateFocus(cell: Int, point: CGPoint) {
        guard let row, let i = sequence.firstIndex(where: { $0.id == row.id }), sequence[i].focusPoints.indices.contains(cell) else { return }
        sequence[i].focusPoints[cell] = point
        sequence[i].manualCells.insert(cell)
    }

    private func resetFocus() {
        guard let row, let i = sequence.firstIndex(where: { $0.id == row.id }) else { return }
        sequence[i].focusPoints = Array(repeating: nil, count: row.template.photos)
        sequence[i].manualCells = []
    }

    private func changeTemplate(_ template: CollageTemplate) {
        guard let row, let i = sequence.firstIndex(where: { $0.id == row.id }) else { return }
        sequence[i].templateID = template.id
        sequence[i].focusPoints = Array(repeating: nil, count: template.photos)
        sequence[i].manualCells = []
    }
}
