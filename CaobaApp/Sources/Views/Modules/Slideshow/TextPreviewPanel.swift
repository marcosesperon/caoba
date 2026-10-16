import SwiftUI
import CaobaCore

/// Vista previa en vivo de los textos del vídeo: título (pantalla propia o sobre
/// la primera foto), cierre y pie, renderizados con el motor a tamaño reducido.
struct TextPreviewPanel: View {
    @Bindable var doc: SlideshowDocument
    @State private var title: CGImage?
    @State private var closing: CGImage?
    @State private var caption: CGImage?
    @State private var captionText: String?

    /// Todo lo que cambia la vista previa, para recalcular solo cuando toca.
    private struct Key: Equatable {
        var mode: TitleMode; var title: String; var subtitle: String; var background: CanvasBackground
        var closingEnabled: Bool; var closingText: String; var closingSubtitle: String
        var titleStyle: TextStyle; var captionStyle: TextStyle; var pattern: String
        var firstPhoto: URL?; var firstCaptionId: String?; var ownCaption: String?; var format: VideoFormat; var total: Int
        var templateName: String?
    }

    private var firstPhoto: URL? {
        switch doc.mode {
        case .photos: return doc.files.first
        case .collage: return doc.rows.first?.files.first ?? doc.files.first
        }
    }

    private var key: Key {
        let id: String?
        let total: Int
        let template: String?
        switch doc.mode {
        case .photos: id = doc.files.first?.lastPathComponent; total = doc.files.count; template = nil
        case .collage: id = doc.rows.first?.id.uuidString; total = doc.rows.count; template = doc.rows.first?.template.name
        }
        return Key(mode: doc.titleMode, title: doc.titleText, subtitle: doc.subtitleText, background: doc.titleBackground,
                   closingEnabled: doc.closingEnabled, closingText: doc.closingText, closingSubtitle: doc.closingSubtitle,
                   titleStyle: doc.titleStyle, captionStyle: doc.captionStyle, pattern: doc.captionPattern,
                   firstPhoto: firstPhoto, firstCaptionId: id, ownCaption: id.flatMap { doc.itemCaptions[$0] }, format: doc.format, total: total,
                   templateName: template)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Vista previa").font(.subheadline.weight(.semibold))
            if doc.titleMode == .none, !doc.closingEnabled, captionText == nil {
                Text("Activa un título, un cierre o un patrón de pie para ver cómo quedan sobre el vídeo.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            if doc.titleMode != .none {
                preview(title, label: doc.titleMode == .card ? "Título · pantalla propia" : "Título · sobre la primera foto")
            }
            if doc.closingEnabled {
                preview(closing, label: "Cierre")
            }
            if let captionText {
                preview(caption, label: "Pie: \(captionText)")
            }
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .task(id: key) { await render(key) }
    }

    @ViewBuilder
    private func preview(_ image: CGImage?, label: LocalizedStringKey) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            if let image {
                Image(decorative: image, scale: 1).resizable().scaledToFit()
                    .clipShape(RoundedRectangle(cornerRadius: 6))
                    .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(.quaternary))
            } else {
                RoundedRectangle(cornerRadius: 6).fill(.quaternary.opacity(0.4)).aspectRatio(doc.format.aspectRatio, contentMode: .fit)
                    .overlay(ProgressView().controlSize(.small))
            }
            Text(label).font(.caption).foregroundStyle(.secondary).lineLimit(1)
        }
    }

    /// Renderiza en segundo plano a un ancho de 720 px, suficiente para juzgar fuente y posición.
    private func render(_ key: Key) async {
        let canvas = Self.previewCanvas(for: key.format)
        let sampleInfo: RenameSourceInfo? = (key.firstPhoto != nil && doc.mode == .photos && !key.pattern.isEmpty)
            ? Renamer.gatherInfo(files: [key.firstPhoto!], pattern: key.pattern.replacingOccurrences(of: "{fecha}", with: "YYYY"), needsDates: key.pattern.contains("{fecha}")).first
            : nil
        let text = doc.caption(for: key.firstCaptionId ?? "", index: 1, total: max(1, key.total), info: sampleInfo, name: key.templateName)
        let titleLines = [key.title, key.subtitle].filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
        let closingLines = [key.closingText, key.closingSubtitle].filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
        let result = await Task.detached(priority: .userInitiated) { () -> (CGImage?, CGImage?, CGImage?) in
            let photo = key.firstPhoto.flatMap { ThumbnailProvider.makeThumbnail(url: $0, maxPixelSize: 900) }
            var titleImage: CGImage?
            switch key.mode {
            case .none: break
            case .card: titleImage = try? TextRenderer.card(lines: titleLines, style: key.titleStyle, background: key.background.fill, canvas: canvas)
            case .overlay: titleImage = Self.compose(photo: photo, layer: TextRenderer.layer(lines: titleLines, style: key.titleStyle, canvas: canvas), canvas: canvas)
            }
            let closingImage = key.closingEnabled ? try? TextRenderer.card(lines: closingLines, style: key.titleStyle, background: key.background.fill, canvas: canvas) : nil
            let captionImage = text.flatMap { Self.compose(photo: photo, layer: TextRenderer.layer(lines: [$0], style: key.captionStyle, canvas: canvas), canvas: canvas) }
            return (titleImage, closingImage, captionImage)
        }.value
        guard !Task.isCancelled else { return }
        title = result.0
        closing = result.1
        caption = result.2
        captionText = text
    }

    nonisolated private static func previewCanvas(for format: VideoFormat) -> PixelSize {
        let width = 720.0
        return PixelSize(width: Int(width), height: max(1, Int((width / format.aspectRatio).rounded())))
    }

    /// Foto entera centrada sobre negro con la capa de texto encima (como hará el vídeo).
    nonisolated private static func compose(photo: CGImage?, layer: CGImage?, canvas: PixelSize) -> CGImage? {
        guard let ctx = CGContext.rgba(width: canvas.width, height: canvas.height) else { return nil }
        ctx.setFillColor(CGColor(red: 0, green: 0, blue: 0, alpha: 1))
        ctx.fill(CGRect(x: 0, y: 0, width: canvas.width, height: canvas.height))
        if let photo {
            let scale = min(Double(canvas.width) / Double(photo.width), Double(canvas.height) / Double(photo.height))
            let w = Double(photo.width) * scale, h = Double(photo.height) * scale
            ctx.draw(photo, in: CGRect(x: (Double(canvas.width) - w) / 2, y: (Double(canvas.height) - h) / 2, width: w, height: h))
        }
        if let layer {
            ctx.draw(layer, in: CGRect(x: 0, y: 0, width: canvas.width, height: canvas.height))
        }
        return ctx.makeImage()
    }
}
