import SwiftUI
import CaobaCore

/// Hoja de contactos: rejilla o masonry con título, etiquetas, borde y logo.
struct ContactSheetView: View {
    @Environment(AppState.self) private var appState

    @State private var columns = 5
    @State private var thumbSize = 200
    @State private var layout: ContactSheetOptions.Layout = .grid
    @State private var cropMode: ContactSheetOptions.CropMode = .contain
    @State private var showFilenames = true
    @State private var showNumbering = false
    @State private var title = ""
    @State private var background: CanvasColor = .white
    @State private var showBorder = false
    @State private var borderWidth = 1.0
    @State private var quality = 90.0
    @State private var logoURL: URL?
    @State private var logoPosition: OverlayPosition = .bottomRight
    @State private var logoSize = 20.0
    @State private var logoOpacity = 80.0

    private var options: ContactSheetOptions {
        ContactSheetOptions(columns: columns, thumbSize: thumbSize, layout: layout, cropMode: cropMode,
                            showFilenames: showFilenames, showNumbering: showNumbering, title: title, background: background,
                            showBorder: showBorder, borderWidth: borderWidth,
                            logo: logoURL.map { LogoOptions(url: $0, position: logoPosition, sizePercent: logoSize, opacity: logoOpacity) },
                            quality: Int(quality))
    }

    private var estimate: String {
        let count = appState.checkedFiles.count
        guard count > 0 else { return "" }
        if layout == .masonry {
            return String(localized: "≈ \(columns * thumbSize) px de ancho; la altura depende de las fotos")
        }
        let size = ContactSheetRenderer.estimatedSize(fileCount: count, options: options)
        let warning = (size.width > ContactSheetOptions.maxDimension || size.height > ContactSheetOptions.maxDimension) ? " ⚠︎" : ""
        return "≈ \(size.width) × \(size.height) px\(warning)"
    }

    var body: some View {
        HSplitView {
            VStack(alignment: .leading, spacing: 12) {
                ModuleTitle(title: "Contact Sheet")
                ScrollView {
                    VStack(alignment: .leading, spacing: 12) {
                        OptionGroup(title: "Disposición") {
                            LabeledRow("Modo") {
                                Picker("", selection: $layout) {
                                    Text("Rejilla").tag(ContactSheetOptions.Layout.grid)
                                    Text("Masonry").tag(ContactSheetOptions.Layout.masonry)
                                }
                                .pickerStyle(.segmented)
                                .labelsHidden()
                            }
                            LabeledRow("Columnas") { Stepper("\(columns)", value: $columns, in: 1...20).fixedSize() }
                            LabeledRow("Miniatura") {
                                TextField("", value: $thumbSize, format: .number).frame(width: 80)
                                Text("px").foregroundStyle(.secondary)
                            }
                            if layout == .grid {
                                LabeledRow("Recorte") {
                                    Picker("", selection: $cropMode) {
                                        Text("Entera").tag(ContactSheetOptions.CropMode.contain)
                                        Text("Rellenar").tag(ContactSheetOptions.CropMode.cover)
                                    }
                                    .labelsHidden()
                                }
                            }
                            Text(estimate).font(.caption).foregroundStyle(.secondary)
                        }
                        OptionGroup(title: "Etiquetas y estilo") {
                            TextField("Título", text: $title)
                            Toggle("Nombres de archivo", isOn: $showFilenames)
                            Toggle("Numeración", isOn: $showNumbering)
                            LabeledRow("Fondo") {
                                BackgroundPicker(selection: $background)
                            }
                            Toggle("Borde", isOn: $showBorder)
                            if showBorder { LabeledRow("Grosor") { Stepper("\(Int(borderWidth)) px", value: $borderWidth, in: 1...20).fixedSize() } }
                            LabeledSlider(title: "Calidad", value: $quality, in: 1...100, step: 1) { Text("\(Int(quality))") }
                        }
                        LogoOptionsGroup(url: $logoURL, position: $logoPosition, size: $logoSize, opacity: $logoOpacity)
                    }
                }
                Spacer()
                HStack {
                    Spacer()
                    Button("Generar") { run() }
                        .buttonStyle(.borderedProminent)
                        .disabled(appState.checkedFiles.isEmpty || appState.destinationFile == nil)
                }
            }
            .padding(.trailing, 8)
            .frame(minWidth: 340, idealWidth: 380)

            FileListView(allowsReorder: true).frame(minWidth: 320)
        }
        .onAppear { appState.destinationFileDefaultName = "contact_sheet_\(AppState.timestampSuffix()).jpg" }
    }

    private func run() {
        guard let output = appState.destinationFile else { return }
        let files = appState.checkedFiles
        let opts = options
        appState.jobRunner.run(openURL: output) { progress in
            try await ContactSheetRenderer.generate(files: files, options: opts, output: output, progress: progress)
        }
    }
}
