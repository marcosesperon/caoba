import SwiftUI
import CaobaCore

/// Procesador por lotes: rotar, recortar, redimensionar, calidad y formato.
struct ProcessorView: View {
    @Environment(AppState.self) private var appState

    @State private var autorotate = true
    @State private var cropEnabled = false
    @State private var cropPreset: CropPreset = .square
    @State private var customRatioW = 4
    @State private var customRatioH = 3
    @State private var cropAnchor: CropAnchor = .center
    @State private var resizeEnabled = false
    @State private var maxDimension = 2048
    @State private var quality = 90.0
    @State private var keepFormat = true
    @State private var outputFormat: OutputFormat = .jpeg
    @State private var compare: (before: CGImage, after: CGImage)?
    @State private var previewError: String?

    enum CropPreset: String, CaseIterable, Identifiable, Codable {
        case square = "1:1", r4x5 = "4:5", r5x4 = "5:4", r3x2 = "3:2", r2x3 = "2:3", r16x9 = "16:9", r9x16 = "9:16", custom
        var id: String { rawValue }
        /// En el selector: "16:9 · TV, YouTube".
        var menuText: Text { self == .custom ? Text("Personalizado") : AspectUsage.text(for: rawValue) }
        var ratio: AspectRatio? {
            switch self {
            case .square: return .square
            case .r4x5: return .r4x5
            case .r5x4: return .r5x4
            case .r3x2: return .r3x2
            case .r2x3: return .r2x3
            case .r16x9: return .r16x9
            case .r9x16: return .r9x16
            case .custom: return nil
            }
        }
    }

    /// Ajustes actuales, para presets y para recordarlos entre sesiones.
    private var settings: ProcessorSettings {
        ProcessorSettings(autorotate: autorotate, cropEnabled: cropEnabled, cropPreset: cropPreset, customRatioW: customRatioW, customRatioH: customRatioH,
                          cropAnchor: cropAnchor, resizeEnabled: resizeEnabled, maxDimension: maxDimension, quality: quality, keepFormat: keepFormat, outputFormat: outputFormat)
    }

    private func apply(_ s: ProcessorSettings) {
        autorotate = s.autorotate; cropEnabled = s.cropEnabled; cropPreset = s.cropPreset
        customRatioW = s.customRatioW; customRatioH = s.customRatioH; cropAnchor = s.cropAnchor
        resizeEnabled = s.resizeEnabled; maxDimension = s.maxDimension; quality = s.quality
        keepFormat = s.keepFormat; outputFormat = s.outputFormat
    }

    /// Operaciones tal como las entiende el motor.
    private var operations: ProcessingOperations {
        let ratio = cropPreset.ratio ?? AspectRatio(customRatioW, customRatioH)
        return ProcessingOperations(
            autorotate: autorotate,
            crop: cropEnabled ? (ratio, cropAnchor) : nil,
            resizeMaxDimension: resizeEnabled ? maxDimension : nil,
            quality: Int(quality),
            format: keepFormat ? nil : outputFormat
        )
    }

    private var canRun: Bool { !appState.checkedFiles.isEmpty && !operations.isEmpty }

    var body: some View {
        VStack(spacing: 12) {
            HSplitView {
                VStack(alignment: .leading, spacing: 12) {
                    HStack {
                        ModuleTitle(title: "Procesador")
                        Spacer()
                        PresetBar(module: .processor, current: settings, defaults: ProcessorSettings(), apply: apply)
                    }
                    ScrollView {
                        VStack(alignment: .leading, spacing: 12) {
                            OptionGroup(title: "Operaciones") {
                                Toggle("Autorrotar según EXIF", isOn: $autorotate)
                                Toggle("Recortar", isOn: $cropEnabled)
                                if cropEnabled {
                                    LabeledRow("Proporción") {
                                        Picker("", selection: $cropPreset) {
                                            ForEach(CropPreset.allCases) { $0.menuText.tag($0) }
                                        }
                                        .labelsHidden()
                                    }
                                    if cropPreset == .custom {
                                        LabeledRow("Personalizado") {
                                            Stepper("Ancho \(customRatioW)", value: $customRatioW, in: 1...100).fixedSize()
                                            Stepper("Alto \(customRatioH)", value: $customRatioH, in: 1...100).fixedSize()
                                        }
                                    }
                                    LabeledRow("Anclaje") {
                                        Picker("", selection: $cropAnchor) {
                                            Text("Centro").tag(CropAnchor.center)
                                            Text("Arriba").tag(CropAnchor.top)
                                            Text("Abajo").tag(CropAnchor.bottom)
                                            Text("Izquierda").tag(CropAnchor.left)
                                            Text("Derecha").tag(CropAnchor.right)
                                        }
                                        .labelsHidden()
                                    }
                                }
                                Toggle("Redimensionar", isOn: $resizeEnabled)
                                if resizeEnabled {
                                    LabeledRow("Lado mayor") {
                                        TextField("", value: $maxDimension, format: .number)
                                            .frame(width: 100)
                                        Text("px, sin ampliar").foregroundStyle(.secondary)
                                    }
                                }
                            }
                            OptionGroup(title: "Salida") {
                                Toggle("Mantener el formato original", isOn: $keepFormat)
                                if !keepFormat {
                                    LabeledRow("Formato") {
                                        Picker("", selection: $outputFormat) {
                                            ForEach(OutputFormat.allCases, id: \.self) { Text($0.rawValue.uppercased()).tag($0) }
                                        }
                                        .labelsHidden()
                                    }
                                }
                                if keepFormat || outputFormat.supportsQuality {
                                    LabeledSlider(title: "Calidad", value: $quality, in: 1...100, step: 1) { Text("\(Int(quality))") }
                                }
                            }
                            if let previewError {
                                Text(previewError).foregroundStyle(.red).font(.callout)
                            }
                        }
                    }
                }
                .padding(.trailing, 8)
                .frame(minWidth: 340, idealWidth: 380)

                FileListView().frame(minWidth: 320)
            }
            DestinationBar(kind: .folder) {
                // Texto corto para que la barra quepa a 1000 pt; el largo sale al pasar el ratón.
                Button("Comparar") { makePreview() }
                    .help("Comparar antes / después")
                    .disabled(appState.checkedFiles.isEmpty)
                Divider().frame(height: 18)
                Button("Procesar") { run() }
                    .buttonStyle(.borderedProminent)
                    .disabled(!canRun)
            }
        }
        .onAppear {
            // Arranca como se dejó la última vez.
            if let last = PresetStore.shared.last(.processor, as: ProcessorSettings.self) { apply(last) }
            // Para pruebas: `--state processor.demo=1` guarda y aplica un preset de ejemplo.
            if appState.launchState["processor.demo"] != nil {
                var demo = ProcessorSettings(); demo.resizeEnabled = true; demo.maxDimension = 2048; demo.quality = 80
                PresetStore.shared.save(demo, named: "Web 2048", module: .processor)
                apply(demo)
            }
        }
        .onChange(of: settings) { PresetStore.shared.saveLast(settings, module: .processor) }
        .sheet(isPresented: Binding(get: { compare != nil }, set: { if !$0 { compare = nil } })) {
            if let compare {
                CompareSheet(before: compare.before, after: compare.after)
            }
        }
    }

    private func makePreview() {
        guard let first = appState.checkedFiles.first else { return }
        let ops = operations
        previewError = nil
        Task.detached {
            do {
                let result = try ImageProcessor().preview(file: first, ops: ops)
                await MainActor.run { compare = result }
            } catch {
                await MainActor.run { previewError = JobRunner.describe(error) }
            }
        }
    }

    private func run() {
        let files = appState.checkedFiles
        let ops = operations
        let mode = appState.saveMode
        let openURL = appState.destinationMode == .newCopy ? appState.destinationFolder : appState.sourceFolder
        appState.jobRunner.run(openURL: openURL) { progress in
            try await ImageProcessor().process(files: files, ops: ops, saveMode: mode, progress: progress)
        }
    }
}

/// Comparador antes / después con un divisor que se arrastra.
struct CompareSheet: View {
    @Environment(\.dismiss) private var dismiss
    let before: CGImage
    let after: CGImage
    @State private var split: CGFloat = 0.5

    var body: some View {
        VStack {
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Image(decorative: before, scale: 1).resizable().scaledToFit()
                    Image(decorative: after, scale: 1).resizable().scaledToFit()
                        .mask(alignment: .leading) {
                            Rectangle().frame(width: geo.size.width * split)
                        }
                    Rectangle().fill(Color.accentColor).frame(width: 2)
                        .offset(x: geo.size.width * split)
                }
                .contentShape(Rectangle())
                .gesture(DragGesture(minimumDistance: 0).onChanged { value in
                    split = min(1, max(0, value.location.x / geo.size.width))
                })
            }
            HStack {
                Text("Después").font(.caption).foregroundStyle(.secondary)
                Spacer()
                Text("Arrastra para comparar").font(.caption).foregroundStyle(.secondary)
                Spacer()
                Text("Antes").font(.caption).foregroundStyle(.secondary)
            }
            HStack { Spacer(); Button("Cerrar") { dismiss() }.keyboardShortcut(.cancelAction) }
        }
        .padding()
        .frame(minWidth: 800, minHeight: 560)
    }
}
