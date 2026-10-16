import SwiftUI
import CaobaCore

/// Encuadre Ken Burns de una foto: paneles de inicio y fin arrastrables, zoom,
/// retardo, ajuste, "Enfocar caras" y previsualización animada. En el
/// inspector va compacto (paneles apilados); ampliado, uno al lado del otro.
struct KenBurnsFramingView: View {
    @Bindable var doc: SlideshowDocument
    let url: URL
    let compact: Bool

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
        HStack(alignment: .top, spacing: 14) {
            // Paneles de inicio y fin: su tamaño sale de la altura disponible.
            GeometryReader { geo in
                let spacing: CGFloat = 10
                let labelsAndSlider: CGFloat = 44
                let panelHByWidth = ((geo.size.width - spacing) / 2) / doc.format.aspectRatio
                let panelH = max(80, min(geo.size.height - labelsAndSlider, panelHByWidth))
                let panelW = panelH * doc.format.aspectRatio
                HStack(alignment: .top, spacing: spacing) {
                    panel(title: "Inicio", focus: current.startFocus, zoom: current.startZoom, size: CGSize(width: panelW, height: panelH),
                          focusChanged: { f in update { $0.startFocus = f } }, zoomChanged: { z in update { $0.startZoom = z } })
                    panel(title: "Fin", focus: current.endFocus, zoom: current.endZoom, size: CGSize(width: panelW, height: panelH),
                          focusChanged: { f in update { $0.endFocus = f } }, zoomChanged: { z in update { $0.endZoom = z } })
                }
            }
            VStack(alignment: .leading, spacing: 8) {
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
                Divider()
                previewRow
                Spacer(minLength: 0)
            }
            .frame(width: compact ? 240 : 300)
        }
        .onAppear { imageSize = ImageIOHelpers.displaySize(of: url) }
        .onChange(of: url) { imageSize = ImageIOHelpers.displaySize(of: url); isPlaying = false }
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

    private func panel(title: LocalizedStringKey, focus: CGPoint, zoom: Double, size: CGSize,
                       focusChanged: @escaping (CGPoint) -> Void, zoomChanged: @escaping @MainActor @Sendable (Double) -> Void) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(title).font(.caption).foregroundStyle(.secondary)
            if current.fit == .contain {
                ThumbnailView(url: url, maxPixelSize: 1200, displaySize: min(size.width, size.height))
                    .frame(width: size.width, height: size.height).background(Color.black)
            } else {
                CellPhotoView(url: url, focus: focus, size: size, zoom: zoom, onFocusChange: focusChanged)
                    .background(Color.black)
            }
            HStack {
                Text("Zoom").font(.caption).foregroundStyle(.secondary)
                Slider(value: Binding(get: { zoom }, set: { v in Task { @MainActor in zoomChanged(v) } }), in: 1...2, step: 0.05)
                Text("\(Int((zoom * 100).rounded())) %").font(.caption.monospacedDigit()).frame(width: 44)
            }
        }
    }

    /// Previsualización animada con el mismo cálculo que el motor.
    private var previewRow: some View {
        let width: CGFloat = compact ? 220 : 280
        let size = CGSize(width: width, height: width / doc.format.aspectRatio)
        return VStack(alignment: .leading, spacing: 6) {
            TimelineView(.animation(minimumInterval: 1 / 30, paused: !isPlaying)) { context in
                let elapsed = isPlaying ? context.date.timeIntervalSince(playStart).truncatingRemainder(dividingBy: segmentDuration) : 0
                let (focus, zoom) = frame(at: elapsed)
                CellPhotoView(url: url, focus: focus, size: size, zoom: zoom)
                    .clipShape(RoundedRectangle(cornerRadius: 4))
                    .background(Color.black)
            }
            HStack {
                Button(isPlaying ? "Detener" : "Reproducir") { isPlaying.toggle(); playStart = Date() }.controlSize(.small)
                Text("Previsualización · \(segmentDuration, specifier: "%.1f") s").font(.caption).foregroundStyle(.secondary)
            }
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

/// El mismo encuadre a pantalla grande, con navegación entre fotos.
struct KenBurnsFramingSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Bindable var doc: SlideshowDocument
    @State var photo: URL

    private var index: Int { doc.files.firstIndex(of: photo) ?? 0 }

    var body: some View {
        VStack(spacing: 10) {
            HStack {
                Button { go(-1) } label: { Image(systemName: "chevron.left") }.disabled(index == 0)
                Text("\(index + 1) / \(doc.files.count) · \(photo.lastPathComponent)").font(.headline).lineLimit(1)
                Button { go(1) } label: { Image(systemName: "chevron.right") }.disabled(index >= doc.files.count - 1)
                Spacer()
                LabeledRow("Efecto") {
                    Picker("", selection: Binding(get: { doc.choice(for: photo) }, set: { doc.setChoice($0, for: photo) })) {
                        ForEach(EffectChoice.all, id: \.self) { Text($0.title).tag($0) }
                    }
                    .frame(maxWidth: 260)
                    .labelsHidden()
                }
            }
            KenBurnsFramingView(doc: doc, url: photo, compact: false)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            HStack { Spacer(); Button("Hecho") { dismiss() }.keyboardShortcut(.defaultAction) }
        }
        .padding(16)
        .frame(minWidth: 940, minHeight: 640)
    }

    private func go(_ delta: Int) {
        let i = index + delta
        guard doc.files.indices.contains(i) else { return }
        photo = doc.files[i]
        doc.selection = .photo(photo.lastPathComponent)
    }
}
