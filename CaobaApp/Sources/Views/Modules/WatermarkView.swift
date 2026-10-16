import SwiftUI
import CaobaCore

/// Marca de agua suelta o en mosaico, con vista previa sobre una de las fotos.
struct WatermarkView: View {
    @Environment(AppState.self) private var appState

    @State private var watermarkURL: URL?
    @State private var options = WatermarkOptions()
    @State private var previewIndex = 0
    @State private var preview: CGImage?
    @State private var previewTask: Task<Void, Never>?

    @State private var presetWarning: String?

    private var canRun: Bool { watermarkURL != nil && !appState.checkedFiles.isEmpty }

    private var settings: WatermarkSettings { WatermarkSettings(watermarkPath: watermarkURL?.path, options: options) }

    /// Aplica un preset; si su PNG ya no existe, se aplica el resto y se avisa.
    private func apply(_ s: WatermarkSettings) {
        options = s.options
        if let path = s.watermarkPath {
            if FileManager.default.fileExists(atPath: path) {
                watermarkURL = URL(fileURLWithPath: path)
                presetWarning = nil
            } else {
                watermarkURL = nil
                presetWarning = L("No se encuentra el PNG de la marca: ") + (path as NSString).lastPathComponent
            }
        } else {
            watermarkURL = nil
            presetWarning = nil
        }
    }

    var body: some View {
        HSplitView {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    ModuleTitle(title: "Marca de agua")
                    Spacer()
                    PresetBar(module: .watermark, current: settings, defaults: WatermarkSettings(), apply: apply)
                }
                if let presetWarning {
                    Text(presetWarning).font(.caption).foregroundStyle(Color.accentColor)
                }
                ScrollView {
                    VStack(alignment: .leading, spacing: 12) {
                        OptionGroup(title: "Imagen de la marca") {
                            HStack {
                                Text(watermarkURL?.lastPathComponent ?? String(localized: "Ningún PNG elegido"))
                                    .lineLimit(1).truncationMode(.middle)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                Button("Elegir PNG…") { chooseWatermark() }
                            }
                        }
                        OptionGroup(title: "Colocación") {
                            LabeledRow("Modo") {
                                Picker("", selection: $options.mode) {
                                    Text("Una sola").tag(WatermarkOptions.Mode.single)
                                    Text("Mosaico").tag(WatermarkOptions.Mode.tiled)
                                }
                                .pickerStyle(.segmented)
                                .labelsHidden()
                            }
                            if options.mode == .single {
                                LabeledRow("Posición") {
                                    Picker("", selection: $options.position) {
                                        Text("Abajo derecha").tag(OverlayPosition.bottomRight)
                                        Text("Abajo izquierda").tag(OverlayPosition.bottomLeft)
                                        Text("Arriba derecha").tag(OverlayPosition.topRight)
                                        Text("Arriba izquierda").tag(OverlayPosition.topLeft)
                                        Text("Centro").tag(OverlayPosition.center)
                                    }
                                    .labelsHidden()
                                }
                            } else {
                                LabeledRow("Separación") {
                                    TextField("", value: $options.spacing, format: .number).frame(width: 80)
                                    Picker("", selection: $options.spacingUnit) {
                                        Text("px").tag(WatermarkOptions.SpacingUnit.pixels)
                                        Text("%").tag(WatermarkOptions.SpacingUnit.percent)
                                    }
                                    .labelsHidden().fixedSize()
                                }
                                LabeledRow("Giro") {
                                    Picker("", selection: $options.rotation) {
                                        ForEach([0.0, 30, -30, 45, -45], id: \.self) { Text("\(Int($0))°").tag($0) }
                                    }
                                    .labelsHidden()
                                }
                            }
                            LabeledSlider(title: "Tamaño", value: $options.sizePercent, in: 1...100, step: 1) { Text("\(Int(options.sizePercent)) %") }
                            LabeledSlider(title: "Opacidad", value: $options.opacity, in: 0...100, step: 1) { Text("\(Int(options.opacity)) %") }
                        }
                    }
                }
                Spacer()
                HStack {
                    Spacer()
                    Button("Aplicar") { run() }
                        .buttonStyle(.borderedProminent)
                        .disabled(!canRun)
                }
            }
            .padding(.trailing, 8)
            .frame(minWidth: 340, idealWidth: 380)

            VStack {
                HStack {
                    Button { previewIndex = max(0, previewIndex - 1) } label: { Image(systemName: "chevron.left") }
                        .disabled(previewIndex == 0)
                    Text(previewFile?.lastPathComponent ?? String(localized: "Vista previa"))
                        .font(.callout).lineLimit(1).truncationMode(.middle)
                    Button { previewIndex = min(appState.checkedFiles.count - 1, previewIndex + 1) } label: { Image(systemName: "chevron.right") }
                        .disabled(previewIndex >= appState.checkedFiles.count - 1)
                }
                CGImageView(image: preview)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(Color(nsColor: .windowBackgroundColor))
                FileListView().frame(minHeight: 160)
            }
            .frame(minWidth: 360)
        }
        .onAppear {
            // Arranca como se dejó la última vez.
            if let last = PresetStore.shared.last(.watermark, as: WatermarkSettings.self) { apply(last) }
            // Para capturas desde línea de comandos: `--state watermark.png=/ruta/marca.png`
            if let path = appState.launchState["watermark.png"] { watermarkURL = URL(fileURLWithPath: path) }
        }
        .onChange(of: settings) { PresetStore.shared.saveLast(settings, module: .watermark) }
        .onChange(of: options) { schedulePreview() }
        .onChange(of: watermarkURL) { schedulePreview() }
        .onChange(of: previewIndex) { schedulePreview() }
        .onChange(of: appState.checkedFiles) { schedulePreview() }
    }

    private var previewFile: URL? {
        let files = appState.checkedFiles
        guard !files.isEmpty else { return nil }
        return files[min(previewIndex, files.count - 1)]
    }

    private func chooseWatermark() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.png]
        panel.prompt = L("Elegir")
        if panel.runModal() == .OK { watermarkURL = panel.url }
    }

    /// Espera medio segundo sin cambios antes de regenerar la vista previa.
    private func schedulePreview() {
        previewTask?.cancel()
        guard let mark = watermarkURL, let file = previewFile else { preview = nil; return }
        let opts = options
        previewTask = Task {
            try? await Task.sleep(for: .milliseconds(400))
            guard !Task.isCancelled else { return }
            let image = await Task.detached { try? Watermarker().preview(file: file, watermark: mark, options: opts) }.value
            guard !Task.isCancelled else { return }
            preview = image
        }
    }

    private func run() {
        guard let mark = watermarkURL else { return }
        let files = appState.checkedFiles
        let opts = options
        let mode = appState.saveMode
        let openURL = appState.destinationMode == .newCopy ? appState.destinationFolder : appState.sourceFolder
        appState.jobRunner.run(openURL: openURL) { progress in
            try await Watermarker().process(files: files, watermark: mark, options: opts, saveMode: mode, progress: progress)
        }
    }
}
