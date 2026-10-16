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

/// Collage estático: secuencia de plantillas (o selección aleatoria), editor de
/// enfoque y opciones de salida. Guarda en carpeta con nombres automáticos.
struct CollageView: View {
    @Environment(AppState.self) private var appState

    @State private var mode: TemplateSelectionMode = .sequential
    @State private var sequence: [SequenceItem] = []
    @State private var randomSelection: Set<String> = []
    @State private var photosFilter: Int?
    @State private var aspectFilter: String?
    @State private var focusMode: FocusMode = .saliency

    @State private var longestSide = 3000
    @State private var gap = 10.0
    @State private var background: CanvasBackground = .white
    @State private var cornerRadius = 0.0
    @State private var shadow = true
    @State private var title = ""
    @State private var quality = 90.0
    @State private var logoURL: URL?
    @State private var logoPosition: OverlayPosition = .bottomRight
    @State private var logoSize = 20.0
    @State private var logoOpacity = 80.0

    private let detector = FocusDetector()

    private var files: [URL] { appState.checkedFiles }
    private var rows: [CollageRow] { CollageSequenceEditor.rows(from: sequence, files: files) }
    private var visibleTemplates: [CollageTemplate] { CollageTemplates.filter(photos: photosFilter, aspectLabel: aspectFilter) }

    private var options: CollageOptions {
        CollageOptions(longestSide: longestSide, gap: gap, background: background, cornerRadius: cornerRadius,
                       shadowIntensity: shadow ? 100 : 0, title: title, quality: Int(quality),
                       logo: logoURL.map { LogoOptions(url: $0, position: logoPosition, sizePercent: logoSize, opacity: logoOpacity) })
    }

    private var canRun: Bool {
        guard !files.isEmpty, appState.destinationFolder != nil else { return false }
        switch mode {
        case .sequential: return !rows.isEmpty
        case .random: return !randomSelection.isEmpty
        }
    }

    var body: some View {
        HSplitView {
            VStack(alignment: .leading, spacing: 12) {
                ModuleTitle(title: "Collage")
                ScrollView {
                    VStack(alignment: .leading, spacing: 12) {
                        LabeledRow("Plantillas") {
                            Picker("", selection: $mode) {
                                Text("Secuencia").tag(TemplateSelectionMode.sequential)
                                Text("Aleatorias").tag(TemplateSelectionMode.random)
                            }
                            .pickerStyle(.segmented)
                            .labelsHidden()
                        }
                        if mode == .random {
                            randomSection
                        } else {
                            CollageSequenceEditor(sequence: $sequence, selectedTemplates: $randomSelection, files: files)
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
                                Picker("", selection: $background) {
                                    Text("Blanco").tag(CanvasBackground.white)
                                    Text("Negro").tag(CanvasBackground.black)
                                    Text("Gris").tag(CanvasBackground.gray)
                                }
                                .labelsHidden()
                            }
                            LabeledSlider(title: "Esquinas", value: $cornerRadius, in: 0...200, step: 1) { Text("\(Int(cornerRadius)) px") }
                            Toggle("Sombra en plantillas superpuestas", isOn: $shadow)
                            TextField("Título", text: $title)
                            LabeledSlider(title: "Calidad", value: $quality, in: 1...100, step: 1) { Text("\(Int(quality))") }
                        }
                        LogoOptionsGroup(url: $logoURL, position: $logoPosition, size: $logoSize, opacity: $logoOpacity)
                    }
                }
                Spacer()
                HStack {
                    Spacer()
                    Button("Generar") { run() }
                        .buttonStyle(.borderedProminent)
                        .disabled(!canRun)
                }
            }
            .padding(.trailing, 8)
            .frame(minWidth: 360, idealWidth: 400)

            FileListView(allowsReorder: true).frame(minWidth: 320)
        }
        .onAppear {
            // Para capturas desde línea de comandos: `--state collage.tab=random` abre en "Aleatorias".
            if appState.launchState["collage.tab"] == "random" { mode = .random; photosFilter = 3 }
            if let aspect = appState.launchState["collage.aspect"] { aspectFilter = aspect }
        }
    }

    private var randomSection: some View {
        OptionGroup(title: "Plantillas permitidas") {
            TemplateFilters(photos: $photosFilter, aspect: $aspectFilter)
            LabeledRow("Enfoque") {
                Picker("", selection: $focusMode) {
                    Text("Centro").tag(FocusMode.center)
                    Text("Automático").tag(FocusMode.saliency)
                    Text("Caras").tag(FocusMode.faces)
                }
                .labelsHidden()
            }
            HStack {
                Text("\(randomSelection.count) plantillas elegidas").font(.caption).foregroundStyle(.secondary)
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
        guard let first = rows.first?.template ?? randomSelection.first.flatMap(CollageTemplates.template(id:)) else { return "" }
        let size = first.canvasSize(longestSide: min(CollageOptions.maxDimension, max(100, longestSide)))
        return "≈ \(size.width) × \(size.height) px"
    }

    private func run() {
        guard let folder = appState.destinationFolder else { return }
        let opts = options
        let allFiles = files
        let mode = mode
        let templates = randomSelection.compactMap(CollageTemplates.template(id:))
        let fixedRows = rows
        let focus = focusMode
        let detector = detector
        appState.jobRunner.run(openURL: folder) { progress in
            var rowsToRender = fixedRows
            if mode == .random {
                rowsToRender = CollageRenderer.group(files: allFiles, templates: templates, mode: .random).rows
                if focus != .center {
                    for i in rowsToRender.indices {
                        for (cell, url) in rowsToRender[i].files.enumerated() {
                            rowsToRender[i].focusPoints[cell] = await detector.focus(for: url, mode: focus).point
                        }
                    }
                }
            }
            let (summary, _) = try await CollageRenderer.generate(rows: rowsToRender, options: opts, outputFolder: folder, progress: progress)
            return summary
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
    @Binding var sequence: [SequenceItem]
    let rows: [CollageRow]
    @State var index: Int
    var includeOverlap = false
    @State private var showTemplates = false

    private var row: CollageRow? { rows.indices.contains(index) ? rows[index] : nil }
    private var item: SequenceItem? { row.flatMap { r in sequence.first { $0.id == r.id } } }

    var body: some View {
        VStack(spacing: 10) {
            HStack {
                Button { index -= 1 } label: { Image(systemName: "chevron.left") }.disabled(index <= 0)
                Text("Collage \(index + 1) de \(rows.count)").font(.headline)
                Button { index += 1 } label: { Image(systemName: "chevron.right") }.disabled(index >= rows.count - 1)
                Spacer()
                Toggle("Cambiar plantilla", isOn: $showTemplates).toggleStyle(.button)
                Button("Centrar celdas") { resetFocus() }
            }
            HStack(spacing: 12) {
                if let row, let item {
                    TemplateView(template: row.template, files: row.files, focusPoints: item.focusPoints, gap: 4) { cell, point in
                        updateFocus(cell: cell, point: point)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(Color(nsColor: .windowBackgroundColor))
                } else {
                    ContentUnavailableView("Sin collage", systemImage: "square.grid.2x2")
                }
                if showTemplates, let row {
                    VStack(alignment: .leading) {
                        Text("Plantillas de \(row.template.photos) fotos").font(.callout).foregroundStyle(.secondary)
                        TemplatePicker(templates: CollageTemplates.filter(photos: row.template.photos, includeOverlap: includeOverlap), selected: [row.template.id]) { template in
                            changeTemplate(template)
                        }
                    }
                    .frame(width: 240)
                }
            }
            Text("Arrastra cada foto para encuadrarla. Los encuadres manuales se conservan al usar «Ajustar foco».")
                .font(.caption).foregroundStyle(.secondary)
            HStack { Spacer(); Button("Hecho") { dismiss() }.keyboardShortcut(.defaultAction) }
        }
        .padding(16)
        .frame(minWidth: 900, minHeight: 620)
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
