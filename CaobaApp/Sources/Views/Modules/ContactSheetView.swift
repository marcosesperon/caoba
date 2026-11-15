import SwiftUI
import CaobaCore

/// Hoja de contactos: rejilla o masonry con título, etiquetas, borde y logo. Con fotos de una
/// sesión del estudio empieza con el preset de Ajustes › Sesiones › Contact Sheet.
struct ContactSheetView: View {
    @Environment(AppState.self) private var appState

    /// Todas las opciones (lo que guardan los presets).
    @State private var settings = ContactSheetSettings()

    private var logoURL: Binding<URL?> {
        Binding(get: { settings.logoPath.map { URL(fileURLWithPath: $0) } }, set: { settings.logoPath = $0?.path })
    }

    private var options: ContactSheetOptions {
        let s = settings
        return ContactSheetOptions(columns: s.columns, thumbSize: s.thumbSize, layout: s.layout, cropMode: s.cropMode,
                                   showFilenames: s.showFilenames, showNumbering: s.showNumbering, title: s.title, background: s.background,
                                   showBorder: s.showBorder, borderWidth: s.borderWidth,
                                   logo: s.logoPath.map { LogoOptions(url: URL(fileURLWithPath: $0), position: s.logoPosition, sizePercent: s.logoSize, opacity: s.logoOpacity) },
                                   quality: Int(s.quality))
    }

    // MARK: - Sesión

    /// Sesión del estudio de las fotos, para `{sesion}` y `{fecha_sesion}` del título.
    private var photoSession: RenameSession? {
        let layout = appState.sessions.layout
        return appState.sourceFolder.flatMap { layout.session(containing: $0) }
            .map { RenameSession(name: $0.name, dateText: layout.dateText($0.date)) }
    }

    /// Pone un preset: con fotos de una sesión, el título lleva ya su nombre y su fecha.
    private func apply(_ preset: ContactSheetSettings) {
        var filled = preset
        if let session = photoSession { filled.title = SlideshowPreset.fill(filled.title, session) }
        settings = filled
    }

    /// Con fotos de una sesión, el preset de Ajustes › Sesiones (o los valores de partida si no hay
    /// ninguno o se borró). Al entrar y al cambiar de carpeta; lo que se toque después se respeta.
    private func applySessionDefault() {
        guard photoSession != nil else { return }
        let name = appState.sessions.layout.contactSheetPreset
        let preset = PresetStore.shared.presets(.contactSheet, as: ContactSheetSettings.self).first { $0.name == name }
        apply(preset?.settings ?? ContactSheetSettings())
    }

    private var estimate: String {
        let count = appState.checkedFiles.count
        guard count > 0 else { return "" }
        if settings.layout == .masonry {
            return String(localized: "≈ \(settings.columns * settings.thumbSize) px de ancho; la altura depende de las fotos")
        }
        let size = ContactSheetRenderer.estimatedSize(fileCount: count, options: options)
        let warning = (size.width > ContactSheetOptions.maxDimension || size.height > ContactSheetOptions.maxDimension) ? " ⚠︎" : ""
        return "≈ \(size.width) × \(size.height) px\(warning)"
    }

    var body: some View {
        VStack(spacing: 12) {
            HSplitView {
                VStack(alignment: .leading, spacing: 12) {
                    HStack {
                        ModuleTitle(title: "Contact Sheet")
                        Spacer()
                        PresetBar(module: .contactSheet, current: settings, defaults: ContactSheetSettings(), apply: apply)
                    }
                    ScrollView {
                        VStack(alignment: .leading, spacing: 12) {
                            OptionGroup(title: "Disposición") {
                                LabeledRow("Modo") {
                                    Picker("", selection: $settings.layout) {
                                        Text("Rejilla").tag(ContactSheetOptions.Layout.grid)
                                        Text("Masonry").tag(ContactSheetOptions.Layout.masonry)
                                    }
                                    .pickerStyle(.segmented)
                                    .labelsHidden()
                                }
                                LabeledRow("Columnas") { Stepper("\(settings.columns)", value: $settings.columns, in: 1...20).fixedSize() }
                                LabeledRow("Miniatura") {
                                    TextField("", value: $settings.thumbSize, format: .number).frame(width: 80)
                                    Text("px").foregroundStyle(.secondary)
                                }
                                if settings.layout == .grid {
                                    LabeledRow("Recorte") {
                                        Picker("", selection: $settings.cropMode) {
                                            Text("Entera").tag(ContactSheetOptions.CropMode.contain)
                                            Text("Rellenar").tag(ContactSheetOptions.CropMode.cover)
                                        }
                                        .labelsHidden()
                                    }
                                }
                                Text(estimate).font(.caption).foregroundStyle(.secondary)
                            }
                            OptionGroup(title: "Etiquetas y estilo") {
                                TextField("Título", text: $settings.title)
                                Toggle("Nombres de archivo", isOn: $settings.showFilenames)
                                Toggle("Numeración", isOn: $settings.showNumbering)
                                LabeledRow("Fondo") {
                                    BackgroundPicker(selection: $settings.background)
                                }
                                Toggle("Borde", isOn: $settings.showBorder)
                                if settings.showBorder { LabeledRow("Grosor") { Stepper("\(Int(settings.borderWidth)) px", value: $settings.borderWidth, in: 1...20).fixedSize() } }
                                LabeledSlider(title: "Calidad", value: $settings.quality, in: 1...100, step: 1) { Text("\(Int(settings.quality))") }
                            }
                            LogoOptionsGroup(url: logoURL, position: $settings.logoPosition, size: $settings.logoSize, opacity: $settings.logoOpacity)
                        }
                    }
                }
                .padding(.trailing, 8)
                .frame(minWidth: 340, idealWidth: 380)

                FileListView(allowsReorder: true).frame(minWidth: 320)
            }
            DestinationBar(kind: .file) {
                Button("Generar") { run() }
                    .buttonStyle(.borderedProminent)
                    .disabled(appState.checkedFiles.isEmpty || appState.destinationFile == nil)
            }
        }
        .onAppear {
            appState.destinationFileDefaultName = "contact_sheet_\(AppState.timestampSuffix()).jpg"
            applySessionDefault()
        }
        .onChange(of: appState.sourceFolder) { applySessionDefault() }
    }

    private func run() {
        // Si alguien ha borrado, renombrado o añadido fotos desde que se leyó la carpeta, no se lanza: sale el aviso con «Recargar».
        guard appState.ensureFolderUnchanged() else { return }
        guard let output = appState.destinationFile else { return }
        let files = appState.checkedFiles
        let opts = options
        appState.jobRunner.run(openURL: output) { progress in
            try await ContactSheetRenderer.generate(files: files, options: opts, output: output, progress: progress)
        }
    }
}
