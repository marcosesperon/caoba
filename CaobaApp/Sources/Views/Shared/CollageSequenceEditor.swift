import SwiftUI
import CaobaCore

/// Editor de secuencia de collages compartido por Collage y Slideshow:
/// Componer, Añadir, Ajustar foco, tarjetas reordenables y editor de enfoque.
struct CollageSequenceEditor: View {
    @Binding var sequence: [SequenceItem]
    @Binding var selectedTemplates: Set<String>
    let files: [URL]
    /// Si se ofrecen las plantillas superpuestas (marco y sombra). Solo en el slideshow.
    var includeOverlap = false

    @State private var photosFilter: Int?
    @State private var aspectFilter: String?
    @State private var showComposePicker = false
    @State private var showAddPicker = false
    @State private var editingIndex: Int?
    @State private var isAdjustingFocus = false
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
    private var visibleTemplates: [CollageTemplate] { CollageTemplates.filter(photos: photosFilter, aspectLabel: aspectFilter, includeOverlap: includeOverlap) }

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
        .onChange(of: files) { prune() }
        .sheet(isPresented: $showComposePicker) { composeSheet }
        .sheet(isPresented: $showAddPicker) { addSheet }
        .sheet(item: Binding(get: { editingIndex.map { EditorTarget(index: $0) } }, set: { editingIndex = $0?.index })) { target in
            FocusEditorSheet(sequence: $sequence, rows: rows, index: target.index, includeOverlap: includeOverlap)
        }
    }

    private var composeSheet: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Componer secuencia").font(.headline)
            Text("Elige qué plantillas pueden usarse. Se repartirán al azar entre las \(files.count) fotos marcadas.")
                .font(.callout).foregroundStyle(.secondary)
            TemplateFilters(photos: $photosFilter, aspect: $aspectFilter)
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
        .frame(width: 720, height: 560)
    }

    private var addSheet: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Añadir collage").font(.headline)
            Text("Quedan \(files.count - assignedCount) fotos sin asignar.").font(.callout).foregroundStyle(.secondary)
            TemplateFilters(photos: $photosFilter, aspect: $aspectFilter)
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
        let (grouped, _) = CollageRenderer.group(files: files, templates: templates, mode: .random)
        sequence = grouped.map { SequenceItem(templateID: $0.template.id, focusPoints: $0.focusPoints) }
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
