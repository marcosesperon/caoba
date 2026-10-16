import SwiftUI
import CaobaCore

/// Renombrador con cuatro modos y vista previa en vivo.
struct RenamerView: View {
    @Environment(AppState.self) private var appState

    enum Mode: String, CaseIterable, Identifiable {
        case pattern, autofix, searchReplace, prefixSuffix
        var id: String { rawValue }
        var title: LocalizedStringKey {
            switch self {
            case .pattern: return "Patrón"
            case .autofix: return "Corregir numeración"
            case .searchReplace: return "Buscar y reemplazar"
            case .prefixSuffix: return "Prefijo / sufijo"
            }
        }
    }

    @State private var mode: Mode = .pattern
    @State private var pattern = "{nombre}"
    @State private var sortBy: SortMode = .name
    @State private var digits = 0
    @State private var start = 1
    @State private var textCase: TextCase = .none
    @State private var sanitize = SanitizeOptions()
    @State private var search = ""
    @State private var replace = ""
    @State private var prefix = ""
    @State private var suffix = ""
    @State private var plan: [RenameEntry] = []
    @State private var planTask: Task<Void, Never>?
    /// Última operación en sitio registrada en la carpeta, si la hay.
    @State private var lastOperation: RenameOperation?

    var body: some View {
        HSplitView {
            VStack(alignment: .leading, spacing: 12) {
                ModuleTitle(title: "Renombrador")
                LabeledRow("Modo") {
                    Picker("", selection: $mode) {
                        ForEach(Mode.allCases) { Text($0.title).tag($0) }
                    }
                    .labelsHidden()
                    .frame(maxWidth: 260)
                }
                ScrollView {
                    VStack(alignment: .leading, spacing: 12) {
                        switch mode {
                        case .pattern:
                            OptionGroup(title: "Patrón") {
                                TextField("Patrón", text: $pattern)
                                Text("Variables: {nombre} {n} {camara} {objetivo} {ancho} {alto} {orientacion} y fecha YYYY MM DD hh mm ss")
                                    .font(.caption).foregroundStyle(.secondary)
                                LabeledRow("Ordenar por") {
                                    Picker("", selection: $sortBy) {
                                        Text("Nombre").tag(SortMode.name)
                                        Text("Fecha de captura").tag(SortMode.date)
                                    }
                                    .labelsHidden()
                                }
                                LabeledRow("Dígitos") { Stepper("\(digits == 0 ? String(localized: "auto") : String(digits))", value: $digits, in: 0...8).fixedSize() }
                                LabeledRow("Empezar en") { Stepper("\(start)", value: $start, in: 0...100_000).fixedSize() }
                                LabeledRow("Mayúsculas") {
                                    Picker("", selection: $textCase) {
                                        Text("Sin cambios").tag(TextCase.none)
                                        Text("minúsculas").tag(TextCase.lowercase)
                                        Text("MAYÚSCULAS").tag(TextCase.uppercase)
                                        Text("Capitalizar").tag(TextCase.capitalize)
                                    }
                                    .labelsHidden()
                                }
                                Toggle("Quitar acentos", isOn: $sanitize.removeAccents)
                                Toggle("Espacios → guion bajo", isOn: $sanitize.removeSpaces)
                                Toggle("Quitar caracteres especiales", isOn: $sanitize.removeSpecialCharacters)
                            }
                        case .autofix:
                            OptionGroup(title: "Corregir numeración") {
                                Text("Detecta secuencias como Foto-1, Foto-2… Foto-100 y rellena con ceros: Foto-001, Foto-002…")
                                    .font(.callout).foregroundStyle(.secondary)
                            }
                        case .searchReplace:
                            OptionGroup(title: "Buscar y reemplazar") {
                                TextField("Buscar", text: $search)
                                TextField("Reemplazar por", text: $replace)
                            }
                        case .prefixSuffix:
                            OptionGroup(title: "Prefijo y sufijo") {
                                TextField("Prefijo", text: $prefix)
                                TextField("Sufijo", text: $suffix)
                            }
                        }
                    }
                }
                Spacer()
                if let lastOperation {
                    HStack {
                        Image(systemName: "arrow.uturn.backward.circle").foregroundStyle(.secondary)
                        Text("Último renombrado: \(lastOperation.entries.count) archivos, \(lastOperation.date.formatted(date: .abbreviated, time: .shortened))")
                            .font(.callout).foregroundStyle(.secondary).lineLimit(1)
                        Spacer()
                        Button("Deshacer") { undo() }
                    }
                    .padding(8)
                    .background(Color(nsColor: .controlBackgroundColor))
                    .clipShape(RoundedRectangle(cornerRadius: 6))
                }
                HStack {
                    Text("\(plan.count) cambios").font(.callout).foregroundStyle(.secondary)
                    Spacer()
                    Button("Renombrar") { run() }
                        .buttonStyle(.borderedProminent)
                        .disabled(plan.isEmpty)
                }
            }
            .padding(.trailing, 8)
            .frame(minWidth: 340, idealWidth: 400)

            VStack(spacing: 8) {
                Table(plan) {
                    TableColumn("Original") { Text($0.oldName) }
                    TableColumn("Nuevo nombre") { Text($0.newName) }
                }
                .overlay {
                    if plan.isEmpty {
                        ContentUnavailableView("Sin cambios", systemImage: "pencil.slash", description: Text("Ajusta las opciones para ver la vista previa."))
                    }
                }
                FileListView().frame(minHeight: 160)
            }
            .frame(minWidth: 360)
        }
        .onChange(of: mode) { schedulePlan() }
        .onChange(of: pattern) { schedulePlan() }
        .onChange(of: sortBy) { schedulePlan() }
        .onChange(of: digits) { schedulePlan() }
        .onChange(of: start) { schedulePlan() }
        .onChange(of: textCase) { schedulePlan() }
        .onChange(of: sanitize) { schedulePlan() }
        .onChange(of: search) { schedulePlan() }
        .onChange(of: replace) { schedulePlan() }
        .onChange(of: prefix) { schedulePlan() }
        .onChange(of: suffix) { schedulePlan() }
        .onChange(of: appState.checkedFiles) { schedulePlan() }
        .onChange(of: appState.sourceFolder) { refreshHistory() }
        .onAppear { schedulePlan(); refreshHistory() }
    }

    /// Recalcula el plan con un pequeño retardo para no leer EXIF en cada tecla.
    private func schedulePlan() {
        planTask?.cancel()
        let files = appState.checkedFiles
        let mode = mode
        let options = PatternRenameOptions(pattern: pattern, sortBy: sortBy, sequenceDigits: digits, sequenceStart: start, textCase: textCase, sanitize: sanitize)
        let (search, replace, prefix, suffix) = (search, replace, prefix, suffix)
        planTask = Task {
            try? await Task.sleep(for: .milliseconds(350))
            guard !Task.isCancelled else { return }
            let result = await Task.detached { () -> [RenameEntry] in
                switch mode {
                case .pattern: return Renamer.patternPlan(files: files, options: options).filter { $0.newName != $0.oldName }
                case .autofix: return Renamer.autofixPlan(files: files)
                case .searchReplace: return Renamer.searchReplacePlan(files: files, search: search, replace: replace)
                case .prefixSuffix: return Renamer.prefixSuffixPlan(files: files, prefix: prefix, suffix: suffix)
                }
            }.value
            guard !Task.isCancelled else { return }
            plan = result
        }
    }

    private func refreshHistory() {
        lastOperation = appState.sourceFolder.flatMap(RenameHistory.last(in:))
    }

    private func run() {
        let currentPlan = plan
        let saveMode = appState.saveMode
        let label = String(describing: mode)
        let openURL = appState.destinationMode == .newCopy ? appState.destinationFolder : appState.sourceFolder
        appState.jobRunner.run(openURL: openURL) { progress in
            try await Renamer().execute(plan: currentPlan, saveMode: saveMode, modeLabel: label, progress: progress)
        }
        afterJob()
    }

    /// Deshace la última operación en sitio registrada en la carpeta.
    private func undo() {
        guard let folder = appState.sourceFolder else { return }
        appState.jobRunner.run(openURL: folder) { progress in
            try await RenameHistory.undoLast(in: folder, progress: progress)
        }
        afterJob()
    }

    /// Al renombrar en sitio, la lista y el historial tienen que volver a leerse.
    private func afterJob() {
        Task {
            while appState.jobRunner.isRunning { try? await Task.sleep(for: .milliseconds(200)) }
            await appState.rescan()
            refreshHistory()
        }
    }
}
