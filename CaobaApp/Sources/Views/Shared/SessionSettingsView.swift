import SwiftUI
import CaobaCore

/// Ajustes › Sesiones: cómo organiza el estudio sus carpetas. Empieza con la estructura de
/// CAOBA (`2026/2026-11-15 Nombre de la sesión` con `RAW`, `JPG` y `Lightroom`); otros estudios
/// pueden cambiar el formato del nombre, las subcarpetas y dónde guarda cada módulo.
struct SessionSettingsView: View {
    @Environment(AppModel.self) private var app
    @State private var presetStore = PresetStore.shared

    private var sessions: StudioSessions { app.sessions }

    var body: some View {
        @Bindable var sessions = app.sessions
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                LabeledRow("Carpeta raíz") {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(sessions.layout.rootPath ?? String(localized: "Sin elegir"))
                            .lineLimit(1).truncationMode(.middle)
                            .foregroundStyle(sessions.layout.rootPath == nil ? .secondary : .primary)
                            .frame(maxWidth: 260, alignment: .leading)
                        HStack {
                            Button("Elegir…") { chooseRoot() }
                            Button("Quitar") { sessions.layout.rootPath = nil }
                                .disabled(sessions.layout.rootPath == nil)
                        }
                        Text("Donde están las carpetas de los años o de las sesiones. Los diálogos de elegir carpeta empiezan aquí si no hay sesión activa.")
                            .font(.caption).foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                LabeledRow("Años") {
                    Toggle("Una carpeta por año", isOn: $sessions.layout.folderPerYear)
                }
                LabeledRow("Nombre") {
                    VStack(alignment: .leading, spacing: 6) {
                        HStack {
                            Picker("", selection: $sessions.layout.datePosition) {
                                Text("Fecha y nombre").tag(SessionDatePosition.beforeName)
                                Text("Nombre y fecha").tag(SessionDatePosition.afterName)
                            }
                            .labelsHidden().fixedSize()
                            Picker("", selection: $sessions.layout.dateFormat) {
                                // Primero los de año delante y, tras una línea, los de día delante.
                                ForEach(SessionDateFormat.allCases.filter(\.yearFirst), id: \.self) { format in
                                    Text(exampleDate(format)).tag(format)
                                }
                                Divider()
                                ForEach(SessionDateFormat.allCases.filter { !$0.yearFirst }, id: \.self) { format in
                                    Text(exampleDate(format)).tag(format)
                                }
                            }
                            .labelsHidden().fixedSize()
                        }
                        Text("Ejemplo: \(example)").font(.caption).foregroundStyle(.secondary)
                    }
                }

                Divider()
                LabeledRow("Subcarpetas") {
                    VStack(alignment: .leading, spacing: 6) {
                        ForEach(sessions.layout.subfolders.indices, id: \.self) { index in
                            HStack {
                                TextField("", text: subfolderBinding(index)).labelsHidden().frame(width: 180)
                                Button { removeSubfolder(at: index) } label: { Image(systemName: "minus.circle") }
                                    .buttonStyle(.borderless)
                                    .disabled(sessions.layout.subfolders.count <= 1)
                            }
                        }
                        Button("Añadir subcarpeta") { sessions.layout.subfolders.append(String(localized: "Nueva")) }
                        Text("Se crean al hacer una sesión nueva.").font(.caption).foregroundStyle(.secondary)
                    }
                }
                LabeledRow("Fotos finales en") {
                    folderPicker($sessions.layout.finalsFolder)
                }
                Text("Es el origen de Slideshow, Collage, Contact Sheet, Procesador, Marca de agua, Renombrador y Metadatos.")
                    .font(.caption).foregroundStyle(.secondary)
                    .padding(.leading, 142)
                    .fixedSize(horizontal: false, vertical: true)
                LabeledRow("Descargas en") {
                    folderPicker($sessions.layout.downloadsFolder)
                }

                Divider()
                Text("Dónde guarda cada módulo dentro de la sesión. Puedes usar {sesion} y {fecha_sesion}.")
                    .font(.caption).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                outputRow("Procesador", .processor)
                outputRow("Marca de agua", .watermark)
                outputRow("Collage", .collage)
                outputRow("Álbum", .album)
                outputRow("Slideshow", .slideshow)
                outputRow("Contact Sheet", .contactSheet)

                Divider()
                Text("Lo que se pone solo con fotos de una sesión. Las plantillas y los presets se guardan desde cada módulo.")
                    .font(.caption).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                LabeledRow("Slideshow") {
                    VStack(alignment: .leading, spacing: 4) {
                        presetPicker(.slideshow, as: SlideshowPreset.self, selection: $sessions.layout.slideshowTemplate,
                                     none: String(localized: "Ninguna"))
                        Text("Plantilla que se aplica al abrir una sesión que todavía no tiene montaje.")
                            .font(.caption).foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                LabeledRow("Contact Sheet") {
                    presetPicker(.contactSheet, as: ContactSheetSettings.self, selection: $sessions.layout.contactSheetPreset,
                                 none: String(localized: "Ninguno"))
                }
                LabeledRow("Renombrador") {
                    presetPicker(.renamer, as: RenamerSettings.self, selection: $sessions.layout.renamerPreset,
                                 none: String(localized: "Ninguno: \(SessionLayout.defaultRenamePattern)"))
                }

                HStack {
                    Spacer()
                    Button("Volver a los valores de partida") {
                        let root = sessions.layout.rootPath
                        sessions.layout = SessionLayout()
                        sessions.layout.rootPath = root
                    }
                }
            }
            .padding(20)
        }
    }

    /// Ejemplo con la fecha de hoy, para ver cómo quedará la carpeta.
    private var example: String {
        let layout = sessions.layout
        let name = layout.folderName(date: Date(), name: String(localized: "Nombre de la sesión"))
        return layout.folderPerYear ? "\(Calendar.current.component(.year, from: Date()))/\(name)" : name
    }

    private func exampleDate(_ format: SessionDateFormat) -> String {
        var layout = sessions.layout
        layout.dateFormat = format
        return layout.dateText(Date())
    }

    /// Elegir el preset (o plantilla) de un módulo para las sesiones. «Ninguno», o uno que ya se
    /// borró, deja los valores de partida.
    private func presetPicker<S: Codable & Equatable>(_ module: PresetModule, as type: S.Type,
                                                       selection: Binding<String?>, none: String) -> some View {
        let presets = presetStore.presets(module, as: S.self)
        let current = Binding<String?>(
            get: { presets.contains { $0.name == selection.wrappedValue } ? selection.wrappedValue : nil },
            set: { selection.wrappedValue = $0 }
        )
        return Picker("", selection: current) {
            Text(none).tag(String?.none)
            if !presets.isEmpty { Divider() }
            ForEach(presets) { Text($0.name).tag(Optional($0.name)) }
        }
        .labelsHidden().fixedSize()
    }

    /// Selector entre las subcarpetas.
    private func folderPicker(_ selection: Binding<String>) -> some View {
        Picker("", selection: selection) {
            ForEach(sessions.layout.subfolders, id: \.self) { Text($0).tag($0) }
        }
        .labelsHidden().fixedSize()
    }

    private func outputRow(_ title: LocalizedStringKey, _ output: SessionOutput) -> some View {
        LabeledRow(title) {
            TextField("", text: Binding(
                get: { sessions.layout.outputs[output] ?? "" },
                set: { sessions.layout.outputs[output] = $0 }
            ), prompt: Text(SessionLayout.defaultOutputs[output] ?? ""))
            .labelsHidden()
            .frame(width: 260)
        }
    }

    /// Al renombrar una subcarpeta, si era la de descargas o la de finales, la sigue siendo.
    private func subfolderBinding(_ index: Int) -> Binding<String> {
        Binding(
            get: { sessions.layout.subfolders.indices.contains(index) ? sessions.layout.subfolders[index] : "" },
            set: { newValue in
                guard sessions.layout.subfolders.indices.contains(index) else { return }
                var layout = sessions.layout
                let old = layout.subfolders[index]
                layout.subfolders[index] = newValue
                if layout.downloadsFolder == old { layout.downloadsFolder = newValue }
                if layout.finalsFolder == old { layout.finalsFolder = newValue }
                sessions.layout = layout
            }
        )
    }

    /// Quitar una subcarpeta; si era la de descargas o la de finales, pasa a serlo la primera.
    private func removeSubfolder(at index: Int) {
        var layout = sessions.layout
        let removed = layout.subfolders.remove(at: index)
        if layout.downloadsFolder == removed { layout.downloadsFolder = layout.subfolders.first ?? "" }
        if layout.finalsFolder == removed { layout.finalsFolder = layout.subfolders.first ?? "" }
        sessions.layout = layout
    }

    private func chooseRoot() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.canCreateDirectories = true
        panel.prompt = L("Elegir carpeta")
        // Si ya hay raíz, se abre en ella; si no, donde toque.
        let response: NSApplication.ModalResponse
        if let root = sessions.layout.root {
            panel.directoryURL = root
            response = panel.runKeepingFolder()
        } else {
            response = panel.runFromStartFolder()
        }
        guard response == .OK, let url = panel.url else { return }
        sessions.layout.rootPath = url.path
    }
}
