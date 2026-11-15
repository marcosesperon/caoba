import SwiftUI
import CaobaCore

/// Renombrador con cuatro modos y vista previa en vivo. Con fotos de una sesión del estudio
/// empieza con el preset de Ajustes › Sesiones (o `{fecha_sesion} {sesion} {n}`).
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
    /// Opciones del modo Patrón (lo que guardan los presets).
    @State private var settings = RenamerSettings()
    @State private var search = ""
    @State private var replace = ""
    @State private var prefix = ""
    @State private var suffix = ""
    @State private var plan: [RenameEntry] = []
    @State private var planTask: Task<Void, Never>?
    /// Última operación en sitio registrada en la carpeta, si la hay.
    @State private var lastOperation: RenameOperation?

    var body: some View {
        VStack(spacing: 12) {
            HSplitView {
                VStack(alignment: .leading, spacing: 12) {
                    HStack {
                        ModuleTitle(title: "Renombrador")
                        Spacer()
                        PresetBar(module: .renamer, current: settings, defaults: RenamerSettings()) { preset in
                            settings = preset
                            mode = .pattern
                        }
                    }
                    LabeledRow("Modo") {
                        Picker("", selection: $mode) {
                            ForEach(Mode.allCases) { Text($0.title).tag($0) }
                        }
                        .labelsHidden()
                        .frame(maxWidth: 260, alignment: .leading)
                    }
                    ScrollView {
                        VStack(alignment: .leading, spacing: 12) {
                            switch mode {
                            case .pattern:
                                OptionGroup(title: "Patrón") {
                                    TextField("Patrón", text: $settings.pattern)
                                    Text("Variables: {nombre} {n} {camara} {objetivo} {ancho} {alto} {orientacion}, fecha {YYYY} {MM} {DD} {hh} {mm} {ss} y de la sesión {sesion} {fecha_sesion}")
                                        .font(.caption).foregroundStyle(.secondary)
                                    if needsMissingSession {
                                        Label("Estas fotos no son de una sesión: {sesion} y {fecha_sesion} no tienen valor. Quítalas del patrón o elige una carpeta de una sesión.", systemImage: "exclamationmark.triangle")
                                            .font(.callout).foregroundStyle(.orange)
                                            .fixedSize(horizontal: false, vertical: true)
                                    }
                                    LabeledRow("Ordenar por") {
                                        Picker("", selection: $settings.sortBy) {
                                            Text("Nombre").tag(SortMode.name)
                                            Text("Fecha de captura").tag(SortMode.date)
                                        }
                                        .labelsHidden()
                                    }
                                    LabeledRow("Dígitos") { Stepper("\(settings.digits == 0 ? String(localized: "auto") : String(settings.digits))", value: $settings.digits, in: 0...8).fixedSize() }
                                    LabeledRow("Empezar en") { Stepper("\(settings.start)", value: $settings.start, in: 0...100_000).fixedSize() }
                                    LabeledRow("Mayúsculas") {
                                        Picker("", selection: $settings.textCase) {
                                            Text("Sin cambios").tag(TextCase.none)
                                            Text("minúsculas").tag(TextCase.lowercase)
                                            Text("MAYÚSCULAS").tag(TextCase.uppercase)
                                            Text("Capitalizar").tag(TextCase.capitalize)
                                        }
                                        .labelsHidden()
                                    }
                                    Toggle("Quitar acentos", isOn: $settings.sanitize.removeAccents)
                                    Toggle("Espacios → guion bajo", isOn: $settings.sanitize.removeSpaces)
                                    Toggle("Quitar caracteres especiales", isOn: $settings.sanitize.removeSpecialCharacters)
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
                        .caobaPanel(padding: 8)
                    }
                }
                .padding(.trailing, 8)
                .frame(minWidth: 340, idealWidth: 400)

                VStack(spacing: 8) {
                    Table(plan) {
                        TableColumn("Original") { Text($0.oldName) }
                        TableColumn("Nuevo nombre") { Text($0.newName) }
                    }
                    // Sin el fondo propio de la tabla, para que se vea el del bloque.
                    .scrollContentBackground(.hidden)
                    .overlay {
                        if plan.isEmpty {
                            ContentUnavailableView("Sin cambios", systemImage: "pencil.slash", description: Text("Ajusta las opciones para ver la vista previa."))
                        }
                    }
                    .caobaPanel(padding: 4)
                    FileListView().frame(minHeight: 160)
                }
                .frame(minWidth: 360)
            }
            DestinationBar(kind: .folder) {
                Text("\(plan.count) cambios").font(.callout).foregroundStyle(.secondary)
                Divider().frame(height: 18)
                Button("Renombrar") { run() }
                    .buttonStyle(.borderedProminent)
                    .disabled(plan.isEmpty || appState.needsDestinationFolder || needsMissingSession)
            }
        }
        .onAppear {
            applySessionDefault()
            // Para capturas desde línea de comandos: `--state renamer.pattern={fecha}_{n}`
            if let initial = appState.launchState["renamer.pattern"] { settings.pattern = initial }
        }
        .onChange(of: mode) { schedulePlan() }
        .onChange(of: settings) { schedulePlan() }
        .onChange(of: search) { schedulePlan() }
        .onChange(of: replace) { schedulePlan() }
        .onChange(of: prefix) { schedulePlan() }
        .onChange(of: suffix) { schedulePlan() }
        .onChange(of: appState.checkedFiles) { schedulePlan() }
        .onChange(of: appState.sourceFolder) {
            applySessionDefault()
            refreshHistory()
        }
        .onAppear { schedulePlan(); refreshHistory() }
    }

    // MARK: - Sesión

    /// Sesión del estudio donde están las fotos (no la activa: pueden ser de otra elegida a mano).
    private var photoSession: StudioSession? {
        appState.sourceFolder.flatMap { appState.sessions.layout.session(containing: $0) }
    }

    /// El patrón usa `{sesion}` o `{fecha_sesion}` y las fotos no son de ninguna sesión: no se renombra.
    private var needsMissingSession: Bool {
        mode == .pattern && Renamer.patternNeedsSession(settings.pattern) && photoSession == nil
    }

    /// Con fotos de una sesión, el modo Patrón con el preset de Ajustes › Sesiones (o el patrón
    /// de partida si no hay ninguno o se borró). Se hace al entrar y al cambiar de carpeta; lo que
    /// se toque después se respeta mientras no cambie la carpeta.
    private func applySessionDefault() {
        guard photoSession != nil else { return }
        let layout = appState.sessions.layout
        let preset = PresetStore.shared.presets(.renamer, as: RenamerSettings.self).first { $0.name == layout.renamerPreset }
        settings = preset?.settings ?? .sessionDefault
        mode = .pattern
    }

    /// Recalcula el plan con un pequeño retardo para no leer EXIF en cada tecla.
    private func schedulePlan() {
        planTask?.cancel()
        let files = appState.checkedFiles
        let mode = mode
        let session = photoSession.map { RenameSession(name: $0.name, dateText: appState.sessions.layout.dateText($0.date)) }
        let blocked = needsMissingSession
        let options = PatternRenameOptions(pattern: settings.pattern, sortBy: settings.sortBy, sequenceDigits: settings.digits,
                                           sequenceStart: settings.start, textCase: settings.textCase, sanitize: settings.sanitize,
                                           session: session)
        let (search, replace, prefix, suffix) = (search, replace, prefix, suffix)
        planTask = Task {
            try? await Task.sleep(for: .milliseconds(350))
            guard !Task.isCancelled else { return }
            let result = await Task.detached { () -> [RenameEntry] in
                switch mode {
                case .pattern:
                    // Sin sesión no hay con qué rellenar sus variables: mejor no enseñar nombres a medias.
                    guard !blocked else { return [] }
                    return Renamer.patternPlan(files: files, options: options).filter { $0.newName != $0.oldName }
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
        // Si alguien ha borrado, renombrado o añadido fotos desde que se leyó la carpeta, no se lanza: sale el aviso con «Recargar».
        guard appState.ensureFolderUnchanged() else { return }
        // Con «Copias nuevas» hace falta carpeta de destino (el botón ya está desactivado sin ella).
        guard !appState.needsDestinationFolder else { return }
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
