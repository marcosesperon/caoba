import SwiftUI
import CaobaCore

/// Bloque de abajo de Collage en modo Carrusel: tramos encadenados que forman una tira ancha,
/// que se exporta cortada en diapositivas de Instagram. Cabecera con Componer, Añadir, Ajustar
/// foco y Vaciar; debajo, el carrusel dibujado de verdad (clic en un tramo para encuadrarlo,
/// arrastrar para reordenar, clic derecho para cambiarlo o quitarlo). El formato se elige
/// en la columna de opciones. Cada tramo es un `SequenceItem`, como en la secuencia.
struct CarouselEditor: View {
    @Environment(AppState.self) private var appState
    @Binding var format: CarouselFormat
    @Binding var sequence: [SequenceItem]
    /// Tramos marcados para Componer, sin formato («pano_2»…).
    @Binding var selectedBases: Set<String>
    @Binding var composeMode: ComposeMode
    @Binding var allowReorder: Bool
    let files: [URL]
    /// Opciones reales de salida, para dibujar el carrusel.
    let options: CollageOptions

    @State private var showComposePicker = false
    @State private var showAddPicker = false
    @State private var changingIndex: Int?
    @State private var editingIndex: Int?
    @State private var isAdjustingFocus = false
    @State private var composeProgress: ComposeProgress?
    @State private var composeTask: Task<Void, Never>?
    private let detector = FocusDetector()

    private var rows: [CollageRow] { CollageSequenceEditor.rows(from: sequence, files: files) }
    private var slides: Int { Carousel.slideCount(rows) }
    private var assignedCount: Int { rows.reduce(0) { $0 + $1.files.count } }
    private var catalog: [CollageTemplate] { CarouselTemplates.templates(for: format) }

    var body: some View {
        SequenceBlock(title: "Carrusel") {
            Button("Componer") { showComposePicker = true }.disabled(files.isEmpty)
            Button("Añadir") { showAddPicker = true }.disabled(slides >= Carousel.maxSlides || assignedCount >= files.count)
            Menu("Ajustar foco") {
                Button("Automático (saliencia)") { adjustFocus(.saliency) }
                Button("Caras") { adjustFocus(.faces) }
                Button("Centrar todo") { adjustFocus(.center) }
            }
            .fixedSize()
            .disabled(sequence.isEmpty || isAdjustingFocus)
            Button("Vaciar") { sequence = [] }.disabled(sequence.isEmpty)
            if isAdjustingFocus { ProgressView().controlSize(.small) }
            if let composeProgress { ComposeProgressView(progress: composeProgress) { composeTask?.cancel() } }
            Spacer()
            Text("\(slides) de \(Carousel.maxSlides) diapositivas · \(assignedCount) de \(files.count) fotos · \(rows.count) tramos")
                .font(.caption).foregroundStyle(slides > Carousel.maxSlides ? Color.accentColor : .secondary)
        } content: {
            CollagePreview(rows: rows, options: options, carouselFormat: format,
                           emptyMessage: "Pulsa Componer o Añadir para empezar. Un carrusel tiene como mucho \(Carousel.maxSlides) diapositivas.",
                           onSelect: { editingIndex = $0 },
                           onMove: { moveItem(&sequence, moved: $0, onto: $1) }) { index in
                Button("Editar encuadre") { editingIndex = index }
                Button("Cambiar tramo…") { changingIndex = index }
                Button("Quitar", role: .destructive) { if rows.indices.contains(index) { let id = rows[index].id; sequence.removeAll { $0.id == id } } }
            }
        }
        .onChange(of: format) { switchFormat() }
        .onChange(of: files) { prune(); autoComposeIfRequested() }
        .onChange(of: sequence) { openEditorIfRequested() }
        .onAppear { autoComposeIfRequested() }
        .sheet(isPresented: $showComposePicker) { composeSheet }
        .sheet(isPresented: $showAddPicker) { addSheet }
        .sheet(item: Binding(get: { changingIndex.map { Target(index: $0) } }, set: { changingIndex = $0?.index })) { target in
            changeSheet(index: target.index)
        }
        .sheet(item: Binding(get: { editingIndex.map { Target(index: $0) } }, set: { editingIndex = $0?.index })) { target in
            CarouselFocusEditorSheet(sequence: $sequence, rows: rows, index: target.index, format: format, options: options)
        }
    }

    // MARK: Hojas

    private var composeSheet: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Componer carrusel").font(.headline)
            Text(composeMode == .random
                 ? "Elige qué tramos pueden usarse. Se repartirán al azar entre las \(files.count) fotos marcadas, hasta \(Carousel.maxSlides) diapositivas."
                 : "Elige qué tramos pueden usarse. Se analizarán las fotos para dar a cada grupo el tramo que mejor le encaje, hasta \(Carousel.maxSlides) diapositivas.")
                .font(.callout).foregroundStyle(.secondary)
            ComposeModeControls(mode: $composeMode, allowReorder: $allowReorder)
            TemplatePicker(templates: catalog, selected: Set(catalog.filter { selectedBases.contains(CarouselTemplates.baseID(of: $0)) }.map(\.id))) { t in
                let base = CarouselTemplates.baseID(of: t)
                if selectedBases.contains(base) { selectedBases.remove(base) } else { selectedBases.insert(base) }
            }
            .frame(minHeight: 340)
            HStack {
                Toggle("Todos", isOn: Binding(
                    get: { catalog.allSatisfy { selectedBases.contains(CarouselTemplates.baseID(of: $0)) } },
                    set: { on in selectedBases = on ? Set(catalog.map(CarouselTemplates.baseID(of:))) : [] }
                )).toggleStyle(.checkbox)
                Spacer()
                Button("Cancelar") { showComposePicker = false }.keyboardShortcut(.cancelAction)
                Button("Componer") { compose(); showComposePicker = false }
                    .buttonStyle(.borderedProminent).disabled(selectedBases.isEmpty)
            }
        }
        .padding(20)
        .frame(width: 760, height: 600)
    }

    private var addSheet: some View {
        let freeSlides = Carousel.maxSlides - slides
        let freePhotos = files.count - assignedCount
        return VStack(alignment: .leading, spacing: 10) {
            Text("Añadir tramo").font(.headline)
            Text("Quedan \(freeSlides) diapositivas y \(freePhotos) fotos sin asignar.").font(.callout).foregroundStyle(.secondary)
            TemplatePicker(templates: catalog.filter { ($0.slides ?? 1) <= freeSlides && $0.photos <= freePhotos }) { t in
                sequence.append(SequenceItem(templateID: t.id, focusPoints: Array(repeating: nil, count: t.photos)))
                showAddPicker = false
            }
            .frame(minHeight: 340)
            HStack { Spacer(); Button("Cancelar") { showAddPicker = false }.keyboardShortcut(.cancelAction) }
        }
        .padding(20)
        .frame(width: 760, height: 520)
    }

    /// Cambiar un tramo por otro que quepa (sin pasar de 10 diapositivas).
    private func changeSheet(index: Int) -> some View {
        let current = rows.indices.contains(index) ? rows[index].template : nil
        let freeSlides = Carousel.maxSlides - slides + (current?.slides ?? 1)
        return VStack(alignment: .leading, spacing: 10) {
            Text("Cambiar tramo \(index + 1)").font(.headline)
            TemplatePicker(templates: catalog.filter { ($0.slides ?? 1) <= freeSlides }, selected: Set([current?.id].compactMap { $0 })) { t in
                if sequence.indices.contains(index) {
                    sequence[index].templateID = t.id
                    sequence[index].focusPoints = Array(repeating: nil, count: t.photos)
                    sequence[index].manualCells = []
                }
                changingIndex = nil
            }
            .frame(minHeight: 340)
            HStack { Spacer(); Button("Cancelar") { changingIndex = nil }.keyboardShortcut(.cancelAction) }
        }
        .padding(20)
        .frame(width: 760, height: 480)
    }

    // MARK: Acciones

    /// Componer con los tramos marcados, sin pasar de 10 diapositivas.
    private func compose() {
        let templates = catalog.filter { selectedBases.contains(CarouselTemplates.baseID(of: $0)) }
        guard composeMode == .content else {
            let grouped = Carousel.limited(CollageRenderer.group(files: files, templates: templates, mode: .random).rows)
            sequence = grouped.map { SequenceItem(templateID: $0.template.id, focusPoints: $0.focusPoints) }
            return
        }
        composeTask?.cancel()
        let snapshot = files
        composeProgress = ComposeProgress(done: 0, total: snapshot.count)
        composeTask = Task {
            defer { composeProgress = nil; composeTask = nil }
            do {
                let result = try await ContentComposition.compose(files: snapshot, templates: templates, allowReorder: allowReorder, detector: detector) { done in
                    composeProgress = ComposeProgress(done: done, total: snapshot.count)
                }
                appState.reorderCheckedFiles(to: result.order)
                sequence = limitedSequence(result.sequence)
            } catch {
                // Cancelado: se deja todo como estaba.
            }
        }
    }

    /// Para capturas: `--state carousel.compose=1` compone al azar con los tramos marcados en
    /// cuanto hay fotos (con `carousel.editor=1`, abre además el editor del primer tramo).
    private func autoComposeIfRequested() {
        guard sequence.isEmpty, !files.isEmpty, appState.launchState["carousel.compose"] != nil else { return }
        composeMode = .random
        compose()
    }

    /// Los primeros tramos de una secuencia que caben en 10 diapositivas.
    private func limitedSequence(_ items: [SequenceItem]) -> [SequenceItem] {
        var total = 0
        return items.prefix { item in
            total += item.template?.slides ?? 1
            return total <= Carousel.maxSlides
        }
    }

    /// Al cambiar de formato, cada tramo pasa al mismo tramo del formato nuevo (se conserva el encuadre).
    private func switchFormat() {
        for i in sequence.indices {
            guard let t = sequence[i].template else { continue }
            sequence[i].templateID = CarouselTemplates.id(base: CarouselTemplates.baseID(of: t), format: format)
        }
    }

    /// Encuadre arrastrado en la tira: la celda global se pasa a su tramo y su celda.
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

    private func openEditorIfRequested() {
        guard appState.launchState["carousel.editor"] != nil, editingIndex == nil, !rows.isEmpty else { return }
        editingIndex = 0
    }

    private struct Target: Identifiable { let index: Int; var id: Int { index } }
}

/// Editor de encuadre de un tramo del carrusel: el tramo en grande con los cortes entre
/// diapositivas; cada foto se arrastra dentro de su celda. Flechas para pasar de tramo.
struct CarouselFocusEditorSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Binding var sequence: [SequenceItem]
    let rows: [CollageRow]
    @State var index: Int
    let format: CarouselFormat
    let options: CollageOptions
    @State private var showResult = false

    private var row: CollageRow? { rows.indices.contains(index) ? rows[index] : nil }
    private var item: SequenceItem? { row.flatMap { r in sequence.first { $0.id == r.id } } }
    /// Número de la primera diapositiva del tramo dentro del carrusel.
    private var firstSlide: Int { Carousel.slideCount(Array(rows.prefix(index))) + 1 }

    var body: some View {
        VStack(spacing: 10) {
            HStack {
                Button { index -= 1 } label: { Image(systemName: "chevron.left") }.disabled(index <= 0)
                Text("Tramo \(index + 1) de \(rows.count)").font(.headline)
                Button { index += 1 } label: { Image(systemName: "chevron.right") }.disabled(index >= rows.count - 1)
                CollageViewModePicker(showResult: $showResult).padding(.leading, 8)
                Spacer()
                if !showResult { Button("Centrar celdas") { resetFocus() } }
            }
            if let row, let item {
                segmentView(row: row, item: item)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(Color(nsColor: .windowBackgroundColor))
            } else {
                ContentUnavailableView("Sin tramo", systemImage: "rectangle.split.3x1")
            }
            Text(showResult
                 ? "Así quedará el tramo con las opciones de salida actuales. Vuelve a «Encuadre» para corregir cualquier foto."
                 : "Arrastra cada foto para encuadrarla. Las líneas rojas son los cortes entre diapositivas.")
                .font(.caption).foregroundStyle(.secondary)
            HStack { Spacer(); Button("Hecho") { dismiss() }.keyboardShortcut(.defaultAction) }
        }
        .padding(16)
        .frame(minWidth: 960, minHeight: 560)
    }

    /// El tramo ajustado al hueco, con sus cortes encima.
    private func segmentView(row: CollageRow, item: SequenceItem) -> some View {
        let slides = row.template.slides ?? 1
        let ratio = CGFloat(format.aspect.width * slides) / CGFloat(format.aspect.height)
        return GeometryReader { geo in
            let width = min(geo.size.width, geo.size.height * ratio)
            let height = width / ratio
            ZStack(alignment: .topLeading) {
                if showResult {
                    CollageResultView(row: row, options: CarouselPreviewOptions.make(options, format: format, slides: slides), framed: false)
                } else {
                    TemplateView(template: row.template, files: row.files, focusPoints: item.focusPoints, gap: 4) { cell, point in
                        updateFocus(cell: cell, point: point)
                    }
                    .background(Color(cgColor: options.background.fill))
                }
                CarouselCuts(slides: slides, slideWidth: width / CGFloat(slides), height: height, firstNumber: firstSlide)
            }
            .frame(width: width, height: height)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
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
}
