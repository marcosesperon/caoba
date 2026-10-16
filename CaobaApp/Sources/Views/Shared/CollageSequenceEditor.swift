import SwiftUI
import CaobaCore

/// Editor de secuencia de collages compartido por Collage y Slideshow:
/// Componer, Añadir, Ajustar foco, tarjetas reordenables y editor de enfoque.
struct CollageSequenceEditor: View {
    @Environment(AppState.self) private var appState
    @Binding var sequence: [SequenceItem]
    @Binding var selectedTemplates: Set<String>
    /// Reparto, reordenar y filtros de la hoja; el padre los guarda por carpeta.
    @Binding var composeState: ComposeSheetState
    let files: [URL]
    /// Opciones reales de salida, para la vista «Resultado» del editor de foco.
    let options: CollageOptions
    /// Si se ofrecen las plantillas superpuestas (marco y sombra). Solo en el slideshow.
    var includeOverlap = false

    @State private var showComposePicker = false
    @State private var showAddPicker = false
    @State private var editingIndex: Int?
    @State private var isAdjustingFocus = false
    @State private var composeProgress: ComposeProgress?
    @State private var composeTask: Task<Void, Never>?
    @State private var autoComposed = false
    private let detector = FocusDetector()

    /// Filas con las fotos repartidas en orden.
    static func rows(from sequence: [SequenceItem], files: [URL]) -> [CollageRow] {
        var index = 0
        var result: [CollageRow] = []
        for item in sequence {
            guard let template = item.template, index + template.photos <= files.count else { break }
            result.append(CollageRow(id: item.id, template: template, files: Array(files[index..<(index + template.photos)]), focusPoints: item.focusPoints, hold: item.hold))
            index += template.photos
        }
        return result
    }

    var rows: [CollageRow] { Self.rows(from: sequence, files: files) }
    private var assignedCount: Int { rows.reduce(0) { $0 + $1.files.count } }
    private var visibleTemplates: [CollageTemplate] { CollageTemplates.filter(photos: composeState.filters.photos, aspectLabel: composeState.filters.aspect, includeOverlap: includeOverlap, type: composeState.filters.type) }

    var body: some View {
        OptionGroup(title: "Secuencia") {
            HStack {
                Button("Componer") { showComposePicker = true }.disabled(files.isEmpty)
                Button("Añadir") { showAddPicker = true }.disabled(assignedCount >= files.count)
                Menu("Ajustar foco") {
                    Button("Automático (saliencia)") { adjustFocus(.saliency) }
                    Button("Caras") { adjustFocus(.faces) }
                    Button("Centrar todo") { adjustFocus(.center) }
                }
                .disabled(sequence.isEmpty || isAdjustingFocus)
                Button("Vaciar") { sequence = [] }.disabled(sequence.isEmpty)
                if isAdjustingFocus { ProgressView().controlSize(.small) }
                if let composeProgress {
                    ComposeProgressView(progress: composeProgress) { composeTask?.cancel() }
                }
            }
            Text("\(assignedCount) de \(files.count) fotos asignadas · \(rows.count) collages")
                .font(.caption).foregroundStyle(.secondary)
            ScrollView(.horizontal) {
                HStack(spacing: 10) {
                    ForEach(Array(rows.enumerated()), id: \.element.id) { index, row in
                        VStack(spacing: 2) {
                            TemplateView(template: row.template, files: row.files, focusPoints: row.focusPoints)
                                .frame(height: 90)
                            Text("\(index + 1)").font(.caption2).foregroundStyle(.secondary)
                        }
                        .onTapGesture { editingIndex = index }
                        .contextMenu {
                            Button("Editar enfoque") { editingIndex = index }
                            Button("Quitar", role: .destructive) { sequence.removeAll { $0.id == row.id } }
                        }
                        .draggable(row.id.uuidString)
                        .dropDestination(for: String.self) { items, _ in
                            guard let moved = items.first.flatMap(UUID.init), let from = sequence.firstIndex(where: { $0.id == moved }),
                                  let to = sequence.firstIndex(where: { $0.id == row.id }) else { return false }
                            sequence.move(fromOffsets: IndexSet(integer: from), toOffset: to > from ? to + 1 : to)
                            return true
                        }
                    }
                    if rows.isEmpty {
                        Text("Pulsa Componer o Añadir para empezar.").font(.callout).foregroundStyle(.secondary).padding()
                    }
                }
                .padding(.vertical, 4)
            }
            .frame(height: 120)
        }
        .onChange(of: files) { prune(); autoComposeIfRequested() }
        .onChange(of: sequence) { openEditorIfRequested() }
        .onAppear {
            // Para capturas desde línea de comandos: `--state collage.compose=open` abre la hoja
            // tal como esté guardada; con `content` o `random` fuerza además el modo.
            if let value = appState.launchState["collage.compose"] {
                if let mode = ComposeMode(rawValue: value) { composeState.mode = mode }
                showComposePicker = true
            }
        }
        .sheet(isPresented: $showComposePicker) { composeSheet }
        .sheet(isPresented: $showAddPicker) { addSheet }
        .sheet(item: Binding(get: { editingIndex.map { EditorTarget(index: $0) } }, set: { editingIndex = $0?.index })) { target in
            FocusEditorSheet(sequence: $sequence, rows: rows, index: target.index, options: options, includeOverlap: includeOverlap)
        }
    }

    private var composeSheet: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Componer secuencia").font(.headline)
            Text(composeState.mode == .random
                 ? "Elige qué plantillas pueden usarse. Se repartirán al azar entre las \(files.count) fotos marcadas."
                 : "Elige qué plantillas pueden usarse. Se analizarán las \(files.count) fotos marcadas para dar a cada grupo la plantilla que mejor le encaje.")
                .font(.callout).foregroundStyle(.secondary)
            ComposeModeControls(mode: $composeState.mode, allowReorder: $composeState.allowReorder)
            TemplateFilters(filters: $composeState.filters, showType: includeOverlap)
            TemplatePicker(templates: visibleTemplates, selected: selectedTemplates) { template in
                if selectedTemplates.contains(template.id) { selectedTemplates.remove(template.id) } else { selectedTemplates.insert(template.id) }
            }
            .frame(minHeight: 320)
            HStack {
                Toggle("Todas las visibles", isOn: Binding(
                    get: { !visibleTemplates.isEmpty && visibleTemplates.allSatisfy { selectedTemplates.contains($0.id) } },
                    set: { on in if on { selectedTemplates.formUnion(visibleTemplates.map(\.id)) } else { selectedTemplates.subtract(visibleTemplates.map(\.id)) } }
                )).toggleStyle(.checkbox)
                Spacer()
                Button("Cancelar") { showComposePicker = false }.keyboardShortcut(.cancelAction)
                Button("Componer") { compose(); showComposePicker = false }
                    .buttonStyle(.borderedProminent).disabled(selectedTemplates.isEmpty)
            }
        }
        .padding(20)
        .frame(width: 720, height: includeOverlap ? 660 : 620)
    }

    private var addSheet: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Añadir collage").font(.headline)
            Text("Quedan \(files.count - assignedCount) fotos sin asignar.").font(.callout).foregroundStyle(.secondary)
            TemplateFilters(filters: $composeState.filters, showType: includeOverlap)
            TemplatePicker(templates: visibleTemplates.filter { $0.photos <= files.count - assignedCount }) { template in
                sequence.append(SequenceItem(templateID: template.id, focusPoints: Array(repeating: nil, count: template.photos)))
                showAddPicker = false
                editingIndex = rows.count - 1
            }
            .frame(minHeight: 320)
            HStack { Spacer(); Button("Cancelar") { showAddPicker = false }.keyboardShortcut(.cancelAction) }
        }
        .padding(20)
        .frame(width: 720, height: 520)
    }

    private func compose() {
        let templates = selectedTemplates.compactMap(CollageTemplates.template(id:))
        guard composeState.mode == .content else {
            let (grouped, _) = CollageRenderer.group(files: files, templates: templates, mode: .random)
            sequence = grouped.map { SequenceItem(templateID: $0.template.id, focusPoints: $0.focusPoints) }
            return
        }
        composeByContent(templates: templates)
    }

    /// Analiza las fotos y reparte según su contenido; reordena la lista de la app
    /// con el orden que decida el reparto y deja la secuencia con el foco puesto.
    private func composeByContent(templates: [CollageTemplate]) {
        composeTask?.cancel()
        let snapshot = files
        composeProgress = ComposeProgress(done: 0, total: snapshot.count)
        composeTask = Task {
            defer { composeProgress = nil; composeTask = nil }
            do {
                let result = try await ContentComposition.compose(files: snapshot, templates: templates, allowReorder: composeState.allowReorder, detector: detector) { done in
                    composeProgress = ComposeProgress(done: done, total: snapshot.count)
                }
                appState.reorderCheckedFiles(to: result.order)
                sequence = result.sequence
            } catch {
                // Cancelado: se deja todo como estaba.
            }
        }
    }

    /// Para pruebas desde línea de comandos: `--state collage.autocompose=content`
    /// (y `collage.reorder=1`) compone con todas las plantillas de 1 a 4 fotos en cuanto hay fotos.
    private func autoComposeIfRequested() {
        guard !autoComposed, !files.isEmpty,
              let mode = appState.launchState["collage.autocompose"].flatMap(ComposeMode.init(rawValue:)) else { return }
        autoComposed = true
        selectedTemplates = Set(CollageTemplates.all.filter { !$0.overlap && (1...4).contains($0.photos) }.map(\.id))
        composeState.mode = mode
        composeState.allowReorder = appState.launchState["collage.reorder"] == "1"
        compose()
    }

    /// Para capturas: `--state collage.editor=result` abre el editor del primer collage en cuanto hay secuencia.
    private func openEditorIfRequested() {
        guard appState.launchState["collage.editor"] != nil, editingIndex == nil, !rows.isEmpty else { return }
        editingIndex = 0
    }

    private func prune() {
        var count = 0
        sequence = sequence.filter { item in
            guard let t = item.template, count + t.photos <= files.count else { return false }
            count += t.photos
            return true
        }
    }

    private func adjustFocus(_ mode: FocusMode) {
        let snapshot = rows
        isAdjustingFocus = true
        Task {
            for row in snapshot {
                guard let itemIndex = sequence.firstIndex(where: { $0.id == row.id }) else { continue }
                for (cell, url) in row.files.enumerated() where !sequence[itemIndex].manualCells.contains(cell) {
                    let result = await detector.focus(for: url, mode: mode)
                    if sequence.indices.contains(itemIndex), sequence[itemIndex].focusPoints.indices.contains(cell) {
                        sequence[itemIndex].focusPoints[cell] = mode == .center ? nil : result.point
                    }
                }
            }
            isAdjustingFocus = false
        }
    }

    private struct EditorTarget: Identifiable { let index: Int; var id: Int { index } }
}
