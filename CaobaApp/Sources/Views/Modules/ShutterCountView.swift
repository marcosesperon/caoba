import SwiftUI
import UniformTypeIdentifiers
import CaobaCore

/// Shutter Count: analiza una foto (JPG o RAW) y muestra cámara, disparos y datos de la foto.
struct ShutterCountView: View {
    @State private var fileURL: URL?
    @State private var result: ShutterCountResult?
    @State private var errorText: String?
    @State private var isReading = false
    @State private var isTargeted = false

    private var exifToolAvailable: Bool { ShutterCountReader.locateExifTool() != nil }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            ModuleTitle(title: "Shutter Count")
            dropZone
            if isReading {
                ProgressView("Leyendo…").controlSize(.small)
            } else if let errorText {
                Label(errorText, systemImage: "exclamationmark.triangle").foregroundStyle(.orange)
            } else if let result {
                ScrollView {
                    VStack(alignment: .leading, spacing: 12) {
                        shutterSection(result)
                        HStack(alignment: .top, spacing: 12) {
                            cameraSection(result)
                            photoSection(result)
                        }
                        Text(result.source == .exiftool ? "Datos leídos con exiftool." : "Datos leídos con ImageIO: sin exiftool, el contador solo está disponible en cámaras Nikon.")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                }
            } else {
                ContentUnavailableView("Elige una foto", systemImage: "camera.aperture",
                                       description: Text("Acepta JPG y RAW (NEF, CR2, CR3, ARW, DNG…). El contador de disparos depende de la marca: Nikon, Sony y Pentax lo guardan; Canon, en los RAW CR3 (los JPG y los CR2 antiguos no lo traen)."))
            }
            Spacer()
            if !exifToolAvailable {
                Label("exiftool no está disponible: solo se leerá el contador de cámaras Nikon. Ejecuta Tools/fetch-exiftool.sh y vuelve a compilar, o instálalo con Homebrew.", systemImage: "info.circle")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
    }

    private var dropZone: some View {
        HStack(spacing: 10) {
            Image(systemName: "photo").foregroundStyle(.secondary)
            Text(fileURL?.path ?? String(localized: "Elige o arrastra una foto"))
                .lineLimit(1).truncationMode(.middle)
                .foregroundStyle(fileURL == nil ? .secondary : .primary)
                .frame(maxWidth: .infinity, alignment: .leading)
            Button("Elegir foto…") { choose() }
        }
        .padding(10)
        .background(isTargeted ? Color.accentColor.opacity(0.15) : Color(nsColor: .controlBackgroundColor))
        .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(isTargeted ? Color.accentColor : .clear, lineWidth: 2))
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .onDrop(of: [.fileURL], isTargeted: $isTargeted) { providers in
            guard let provider = providers.first else { return false }
            _ = provider.loadObject(ofClass: URL.self) { url, _ in
                guard let url else { return }
                Task { @MainActor in analyze(url) }
            }
            return true
        }
    }

    private func choose() {
        let panel = NSOpenPanel()
        var types: [UTType] = [.jpeg, .png, .tiff, .heic, .rawImage]
        for ext in SupportedFormats.rawExtensions { if let t = UTType(filenameExtension: ext) { types.append(t) } }
        panel.allowedContentTypes = types
        panel.prompt = L("Analizar")
        if panel.runModal() == .OK, let url = panel.url { analyze(url) }
    }

    private func analyze(_ url: URL) {
        fileURL = url
        result = nil
        errorText = nil
        isReading = true
        Task {
            do {
                result = try await ShutterCountReader.read(url)
            } catch {
                errorText = JobRunner.describe(error)
            }
            isReading = false
        }
    }

    // MARK: Secciones

    private func shutterSection(_ r: ShutterCountResult) -> some View {
        OptionGroup(title: "Obturador") {
            if let count = r.shutter.count {
                HStack(alignment: .firstTextBaseline, spacing: 12) {
                    Text(count.formatted()).font(.caobaTitle(40))
                    Text("disparos").foregroundStyle(.secondary)
                    if let mech = r.shutter.mechanicalCount, mech != count {
                        Text("· \(mech.formatted()) mecánicos").foregroundStyle(.secondary)
                    }
                }
                if let life = r.shutter.lifeExpectancy, let percent = r.shutter.percentUsed {
                    ProgressView(value: min(percent, 100), total: 100)
                        .tint(percent < 50 ? .green : (percent < 80 ? .orange : .red))
                    Text("\(percent, specifier: "%.1f") % de los \(life.formatted()) disparos de vida útil \(r.shutter.isEstimate ? String(localized: "(estimación genérica de la marca)") : String(localized: "estimados para este modelo"))")
                        .font(.callout).foregroundStyle(.secondary)
                    Text(statusText(percent: percent)).font(.callout)
                }
            } else {
                Text("Esta foto no incluye el contador de disparos.").foregroundStyle(.secondary)
                if r.source == .imageIO, !(r.camera.make ?? "").lowercased().contains("nikon") {
                    Text("Con exiftool se podría leer en cámaras Sony y Pentax.").font(.caption).foregroundStyle(.secondary)
                }
            }
        }
    }

    private func statusText(percent: Double) -> LocalizedStringKey {
        switch percent {
        case ..<25: return "Obturador casi nuevo."
        case ..<50: return "Uso moderado."
        case ..<80: return "Uso alto: conviene tenerlo en cuenta al comprar o vender."
        case ..<100: return "Cerca del final de la vida útil estimada."
        default: return "Ha superado la vida útil estimada; puede seguir funcionando, pero sin garantía."
        }
    }

    private func cameraSection(_ r: ShutterCountResult) -> some View {
        OptionGroup(title: "Cámara") {
            infoRow("Modelo", r.camera.displayName)
            infoRow("Nº de serie", r.camera.serial)
            infoRow("Firmware", r.camera.firmware)
            infoRow("Objetivo", r.camera.lens)
        }
    }

    private func photoSection(_ r: ShutterCountResult) -> some View {
        OptionGroup(title: "Foto") {
            infoRow("Fecha", r.photo.dateTime)
            infoRow("ISO", r.photo.iso.map(String.init))
            infoRow("Apertura", r.photo.fNumber.map { "f/\($0.formatted())" })
            infoRow("Exposición", r.photo.exposureTime.map(formatExposure))
            infoRow("Focal", r.photo.focalLength.map { "\($0.formatted()) mm" })
            infoRow("Tamaño", (r.photo.width != nil && r.photo.height != nil) ? "\(r.photo.width!) × \(r.photo.height!)" : nil)
        }
    }

    private func infoRow(_ label: LocalizedStringKey, _ value: String?) -> some View {
        HStack(alignment: .top) {
            Text(label).foregroundStyle(.secondary).frame(width: 100, alignment: .leading)
            Text(value ?? "—").textSelection(.enabled)
        }
        .font(.callout)
    }

    private func formatExposure(_ seconds: Double) -> String {
        if seconds >= 1 { return "\(seconds.formatted()) s" }
        return "1/\(Int((1 / seconds).rounded())) s"
    }
}
