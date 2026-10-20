import SwiftUI
import CaobaCore

/// Editor de Foto en columnas fijas (`InspectorSplit`): a la izquierda lo que pase quien
/// llama (`leading`: efecto; `trailing`: tiempo, transición, pie); en el centro el grupo
/// «Encuadre» con Inicio y Fin en pequeño, arrastrables y con zoom, más ajuste, caras y
/// retardo, solo con el efecto «Personalizado» (los demás no usan Inicio y Fin); a la
/// derecha la previsualización animada, calculada igual que el motor.
struct KenBurnsFramingView<Leading: View, Trailing: View>: View {
    @Bindable var doc: SlideshowDocument
    let url: URL
    private let leading: Leading
    private let trailing: Trailing

    init(doc: SlideshowDocument, url: URL, @ViewBuilder leading: () -> Leading, @ViewBuilder trailing: () -> Trailing) {
        self.doc = doc
        self.url = url
        self.leading = leading()
        self.trailing = trailing()
    }

    @State private var isPlaying = false
    @State private var playStart = Date()
    @State private var imageSize: PixelSize?
    @State private var isDetecting = false

    private var name: String { url.lastPathComponent }
    private var choice: EffectChoice { doc.choice(for: url) }
    private var current: KenBurnsPoints { doc.kbPoints[name] ?? KenBurnsPoints() }
    /// La foto sigue en pantalla mientras entra la siguiente: su duración más esa transición.
    private var segmentDuration: Double {
        let files = doc.files
        let next = files.firstIndex(of: url).flatMap { files.indices.contains($0 + 1) ? files[$0 + 1] : nil }
        return doc.duration(of: url) + (next.map { doc.entryDuration(for: $0.lastPathComponent) } ?? 0)
    }

    var body: some View {
        // La previsualización toma lo justo para llenar el alto, como mucho un tercio del
        // ancho, y encoge si las columnas de controles no caben.
        InspectorSplit(minSettingsWidth: isCustom ? 2 * Self.columnWidth + 16 : Self.columnWidth, balancesSettings: false,
                       previewOnTrailingSide: true, maxPreviewFraction: 1.0 / 3,
                       previewWidth: { height in (height - Self.previewControlsHeight) * doc.format.aspectRatio }) {
            previewRow
        } settings: {
            HStack(alignment: .top, spacing: 16) {
                InspectorScroll {
                    VStack(alignment: .leading, spacing: 12) {
                        leading
                        trailing
                    }
                }
                if isCustom {
                    InspectorScroll {
                        OptionGroup(title: "Encuadre") {
                            stackedPanels
                            framingButtons
                        }
                    }
                }
            }
        }
        .onAppear { imageSize = ImageIOHelpers.displaySize(of: url) }
        .onChange(of: url) { imageSize = ImageIOHelpers.displaySize(of: url); isPlaying = false }
    }

    /// Ancho mínimo de cada columna de controles del inspector.
    private static var columnWidth: CGFloat { 280 }
    /// Alto de «Reproducir» y la duración bajo la previsualización.
    private static var previewControlsHeight: CGFloat { 34 }

    private var isCustom: Bool {
        if case .effect(.custom) = choice { return true }
        return false
    }

    /// Inicio y Fin en pequeño, uno encima del otro en la columna central, con tope de ancho
    /// para que no se coman el editor.
    private var stackedPanels: some View {
        VStack(alignment: .leading, spacing: 10) {
            startPanel.frame(maxWidth: 260, alignment: .leading)
            endPanel.frame(maxWidth: 260, alignment: .leading)
        }
    }

    private var startPanel: some View {
        flexiblePanel(title: "Inicio", focus: current.startFocus, zoom: current.startZoom,
                      focusChanged: { f in update { $0.startFocus = f } }, zoomChanged: { z in update { $0.startZoom = z } })
    }

    private var endPanel: some View {
        flexiblePanel(title: "Fin", focus: current.endFocus, zoom: current.endZoom,
                      focusChanged: { f in update { $0.endFocus = f } }, zoomChanged: { z in update { $0.endZoom = z } })
    }

    /// Ajuste, caras, inicio/fin y retardo.
    @ViewBuilder
    private var framingButtons: some View {
        LabeledRow("Ajuste") {
            Picker("", selection: Binding(get: { current.fit }, set: { newFit in update { $0.fit = newFit } })) {
                Text("Rellenar").tag(KenBurnsPoints.Fit.cover)
                Text("Entera").tag(KenBurnsPoints.Fit.contain)
            }
            .labelsHidden()
        }
        HStack {
            Button("Enfocar caras") { focusOnFaces() }.disabled(isDetecting)
            if isDetecting { ProgressView().controlSize(.small) }
        }
        HStack {
            Button("Inicio → Fin") { update { $0.endFocus = $0.startFocus; $0.endZoom = $0.startZoom } }
            Button("Intercambiar") { update { let f = $0.startFocus, z = $0.startZoom; $0.startFocus = $0.endFocus; $0.startZoom = $0.endZoom; $0.endFocus = f; $0.endZoom = z } }
        }
        Button("Restablecer") { doc.kbPoints[name] = nil }
        HStack {
            Text("Retardo").foregroundStyle(.secondary)
            Slider(value: Binding(get: { current.delayPercent }, set: { v in update { $0.delayPercent = v } }), in: 0...80, step: 5)
            Text("\(Int(current.delayPercent)) %").monospacedDigit().frame(width: 40)
        }
    }

    private func update(_ change: (inout KenBurnsPoints) -> Void) {
        var p = current
        change(&p)
        doc.kbPoints[name] = p
        // Editar los puntos implica usar el efecto personalizado.
        if case .effect(.custom) = choice {} else { doc.setChoice(.effect(.custom), for: url) }
    }

    private func focusOnFaces() {
        isDetecting = true
        let target = url
        Task {
            let result = await doc.detector.focus(for: target, mode: .faces)
            update { $0.startFocus = result.point; $0.endFocus = result.point }
            isDetecting = false
        }
    }

    /// Panel de Inicio o Fin a todo el ancho que le den, con la proporción del vídeo.
    private func flexiblePanel(title: LocalizedStringKey, focus: CGPoint, zoom: Double,
                               focusChanged: @escaping (CGPoint) -> Void, zoomChanged: @escaping @MainActor @Sendable (Double) -> Void) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(title).font(.caption).foregroundStyle(.secondary)
            GeometryReader { geo in
                panelImage(focus: focus, zoom: zoom, size: CGSize(width: geo.size.width, height: geo.size.width / doc.format.aspectRatio),
                           focusChanged: focusChanged)
            }
            .aspectRatio(doc.format.aspectRatio, contentMode: .fit)
            zoomRow(zoom: zoom, zoomChanged: zoomChanged)
        }
    }

    /// La foto del panel: entera sobre negro o recortada con su foco y zoom (arrastrable).
    @ViewBuilder
    private func panelImage(focus: CGPoint, zoom: Double, size: CGSize, focusChanged: @escaping (CGPoint) -> Void) -> some View {
        if current.fit == .contain {
            ThumbnailView(url: url, maxPixelSize: 1200, displaySize: min(size.width, size.height))
                .frame(width: size.width, height: size.height).background(Color.black)
        } else {
            CellPhotoView(url: url, focus: focus, size: size, zoom: zoom, onFocusChange: focusChanged)
                .background(Color.black)
        }
    }

    /// Zoom del panel, del 100 % al 200 %.
    private func zoomRow(zoom: Double, zoomChanged: @escaping @MainActor @Sendable (Double) -> Void) -> some View {
        HStack {
            Text("Zoom").font(.caption).foregroundStyle(.secondary)
            Slider(value: Binding(get: { zoom }, set: { v in Task { @MainActor in zoomChanged(v) } }), in: 1...2, step: 0.05)
            Text("\(Int((zoom * 100).rounded())) %").font(.caption.monospacedDigit()).frame(width: 44)
        }
    }

    /// Previsualización animada con el mismo cálculo que el motor.
    private var previewRow: some View {
        VStack(alignment: .leading, spacing: 6) {
            // Todo el ancho que le deja el reparto, con la proporción del vídeo.
            GeometryReader { geo in animatedPreview(width: geo.size.width) }
                .aspectRatio(doc.format.aspectRatio, contentMode: .fit)
            HStack {
                Button(isPlaying ? "Detener" : "Reproducir") { isPlaying.toggle(); playStart = Date() }.controlSize(.small)
                Text("Previsualización · \(segmentDuration, specifier: "%.1f") s").font(.caption).foregroundStyle(.secondary)
            }
        }
    }

    /// La foto moviéndose como en el vídeo, a ese ancho.
    private func animatedPreview(width: CGFloat) -> some View {
        let size = CGSize(width: width, height: width / doc.format.aspectRatio)
        return TimelineView(.animation(minimumInterval: 1 / 30, paused: !isPlaying)) { context in
            let elapsed = isPlaying ? context.date.timeIntervalSince(playStart).truncatingRemainder(dividingBy: segmentDuration) : 0
            let (focus, zoom) = frame(at: elapsed)
            CellPhotoView(url: url, focus: focus, size: size, zoom: zoom)
                .clipShape(RoundedRectangle(cornerRadius: 4))
                .background(Color.black)
        }
    }

    private func frame(at t: Double) -> (CGPoint, Double) {
        guard let imageSize else { return (CGPoint(x: 0.5, y: 0.5), 1) }
        let effect: KenBurnsEffect?
        switch choice {
        case .none: effect = nil
        case .random: effect = .zoomIn
        case .effect(let e): effect = e
        }
        let photoSpec = SlideshowPhoto(url: url, duration: segmentDuration, kenBurns: effect, points: doc.kbPoints[name])
        guard let crop = KenBurns.cropRect(for: photoSpec, imageSize: imageSize, targetSize: doc.format.size, time: t,
                                           segmentDuration: segmentDuration, settings: doc.kbSettings) else {
            return (CGPoint(x: 0.5, y: 0.5), 1)
        }
        let base = CropGeometry.rect(in: imageSize, ratio: doc.format.aspectRatio, focus: CGPoint(x: 0.5, y: 0.5))
        let zoom = base.width / max(1, crop.width)
        let focus = CGPoint(x: crop.midX / Double(imageSize.width), y: crop.midY / Double(imageSize.height))
        return (focus, zoom)
    }
}
