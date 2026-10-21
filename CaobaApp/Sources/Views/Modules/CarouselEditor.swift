import SwiftUI
import CaobaCore

/// Modo Carrusel del Collage: tramos encadenados que forman una tira ancha, que se
/// exporta cortada en diapositivas de Instagram. Reutiliza la secuencia del Collage
/// (cada tramo es un `SequenceItem`), Componer y el encuadre por celda.
struct CarouselEditor: View {
    @Environment(AppState.self) private var appState
    @Binding var format: CarouselFormat
    @Binding var sequence: [SequenceItem]
    /// Tramos marcados para Componer, sin formato («pano_2»…).
    @Binding var selectedBases: Set<String>
    @Binding var composeMode: ComposeMode
    @Binding var allowReorder: Bool
    let files: [URL]
    /// Opciones reales de salida, para la vista «Resultado».
    let options: CollageOptions

    @State private var showComposePicker = false
    @State private var showAddPicker = false
    @State private var changingIndex: Int?
    @State private var showResult = false
    @State private var isAdjustingFocus = false
    @State private var composeProgress: ComposeProgress?
    @State private var composeTask: Task<Void, Never>?
    private let detector = FocusDetector()

    private var rows: [CollageRow] { CollageSequenceEditor.rows(from: sequence, files: files) }
    private var slides: Int { Carousel.slideCount(rows) }
    private var assignedCount: Int { rows.reduce(0) { $0 + $1.files.count } }
    private var catalog: [CollageTemplate] { CarouselTemplates.templates(for: format) }
    private var combined: CollageRow? { Carousel.combine(rows, format: format) }

    var body: some View {
        OptionGroup(title: "Carrusel") {
            LabeledRow("Formato") {
                Picker("", selection: $format) {
                    ForEach(CarouselFormat.allCases) { f in
                        Text("\(f.label) · \(f.slideSize.width)×\(f.slideSize.height)").tag(f)
                    }
                }
                .pickerStyle(.segmented).fixedSize().labelsHidden()
            }
            HStack {
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
                CollageViewModePicker(showResult: $showResult)
            }
            Text("\(slides) de \(Carousel.maxSlides) diapositivas · \(assignedCount) de \(files.count) fotos · \(rows.count) tramos")
                .font(.caption).foregroundStyle(slides > Carousel.maxSlides ? Color.accentColor : .secondary)
            strip
            segmentChips
        }
        .onChange(of: format) { switchFormat() }
        .onChange(of: files) { prune(); autoComposeIfRequested() }
        .onAppear { autoComposeIfRequested() }
        .sheet(isPresented: $showComposePicker) { composeSheet }
        .sheet(isPresented: $showAddPicker) { addSheet }
        .sheet(item: Binding(get: { changingIndex.map { Target(index: $0) } }, set: { changingIndex = $0?.index })) { target in
            changeSheet(index: target.index)
        }
    }

    // MARK: Tira

    /// La tira completa con las líneas de corte y el número de cada diapositiva. En «Encuadre»
    /// cada foto se arrastra para encuadrarla; en «Resultado», con las opciones reales.
    @ViewBuilder
    private var strip: some View {
        if let combined {
            let height: CGFloat = 230
            let slideW = height * CGFloat(format.aspect.width) / CGFloat(format.aspect.height)
            let total = combined.template.slides ?? 1
            ScrollView(.horizontal) {
                ZStack(alignment: .topLeading) {
                    if showResult {
                        CollageResultView(row: combined, options: stripOptions, framed: false)
                    } else {
                        TemplateView(template: combined.template, files: combined.files, focusPoints: combined.focusPoints, gap: 2) { cell, point in
                            updateFocus(globalCell: cell, point: point)
                        }
                        .background(Color(cgColor: options.background.fill))
                    }
                    // Cortes y números de diapositiva (no estorban al arrastre).
                    ForEach(0..<total, id: \.self) { i in
                        if i > 0 {
                            Rectangle().fill(Color.accentColor).frame(width: 2, height: height)
                                .offset(x: slideW * CGFloat(i) - 1)
                        }
                        Text("\(i + 1)").font(.caption2.monospacedDigit().bold()).foregroundStyle(.white)
                            .padding(.horizontal, 4).padding(.vertical, 1)
                            .background(.black.opacity(0.55), in: RoundedRectangle(cornerRadius: 3))
                            .offset(x: slideW * CGFloat(i) + 4, y: 4)
                    }
                    .allowsHitTesting(false)
                }
                .frame(width: slideW * CGFloat(total), height: height)
            }
            Text(showResult
                 ? "Así quedará cada diapositiva con las opciones de salida actuales. Las líneas rojas son los cortes."
                 : "Arrastra cada foto para encuadrarla. Las líneas rojas son los cortes entre diapositivas.")
                .font(.caption).foregroundStyle(.secondary)
        } else {
            Text("Pulsa Componer o Añadir para empezar. Un carrusel tiene como mucho \(Carousel.maxSlides) diapositivas.")
                .font(.callout).foregroundStyle(.secondary).padding(.vertical, 20)
        }
    }

    /// Opciones para la vista «Resultado»: más pequeña que la salida real, mismo aspecto.
    private var stripOptions: CollageOptions {
        var o = options
        o.title = ""
        o.longestSide = 360 * max(1, slides)
        o.gap = options.gap / 3
        return o
    }

    /// Tramos en orden: se reordenan arrastrando; clic derecho para cambiar o quitar.
    private var segmentChips: some View {
        ScrollView(.horizontal) {
            HStack(spacing: 8) {
                ForEach(Array(rows.enumerated()), id: \.element.id) { index, row in
                    VStack(spacing: 2) {
                        TemplateView(template: row.template).frame(height: 36)
                        Text(row.template.name).font(.caption2).lineLimit(1).foregroundStyle(.secondary)
                    }
                    .frame(width: 30 * CGFloat(row.template.slides ?? 1) + 24)
                    .help("Arrastra para cambiar el orden; clic derecho para cambiar o quitar")
                    .contextMenu {
                        Button("Cambiar tramo…") { changingIndex = index }
                        Button("Quitar", role: .destructive) { sequence.removeAll { $0.id == row.id } }
                    }
                    .onTapGesture(count: 2) { changingIndex = index }
                    .draggable(row.id.uuidString)
                    .dropDestination(for: String.self) { items, _ in
                        guard let moved = items.first.flatMap(UUID.init), let from = sequence.firstIndex(where: { $0.id == moved }),
                              let to = sequence.firstIndex(where: { $0.id == row.id }) else { return false }
                        sequence.move(fromOffsets: IndexSet(integer: from), toOffset: to > from ? to + 1 : to)
                        return true
                    }
                }
            }
            .padding(.vertical, 2)
        }
        .frame(height: 60)
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
    /// cuanto hay fotos (con `carousel.result=1`, en la vista «Resultado»).
    private func autoComposeIfRequested() {
        guard sequence.isEmpty, !files.isEmpty, appState.launchState["carousel.compose"] != nil else { return }
        composeMode = .random
        compose()
        showResult = appState.launchState["carousel.result"] != nil
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
    private func updateFocus(globalCell: Int, point: CGPoint) {
        var cell = globalCell
        for row in rows {
            if cell < row.template.photos {
                guard let i = sequence.firstIndex(where: { $0.id == row.id }), sequence[i].focusPoints.indices.contains(cell) else { return }
                sequence[i].focusPoints[cell] = point
                sequence[i].manualCells.insert(cell)
                return
            }
            cell -= row.template.photos
        }
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

    private struct Target: Identifiable { let index: Int; var id: Int { index } }
}
