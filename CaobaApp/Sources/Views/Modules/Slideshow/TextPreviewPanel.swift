import SwiftUI
import CaobaCore

/// Vista previa en vivo de los textos del vídeo: título (pantalla propia o sobre
/// la primera foto), cierre y pie, renderizados con el motor a tamaño reducido.
struct TextPreviewPanel: View {
    @Bindable var doc: SlideshowDocument
    @State private var cardImage: CGImage?
    @State private var caption: CGImage?
    @State private var captionText: String?

    /// Todo lo que cambia la vista previa, para recalcular solo cuando toca.
    private struct Key: Equatable {
        var card: TextCard?; var cardPhoto: URL?
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

    /// La tarjeta seleccionada en el timeline o, si no, la primera.
    private var previewCard: TextCard? {
        if case .text(let id) = doc.selection, let card = doc.textCard(id) { return card }
        return doc.items.first(where: \.isText).flatMap { if case .text(let c) = $0.kind { return c } else { return nil } }
    }

    /// Foto del elemento que sigue a la tarjeta (para las superpuestas).
    private func photo(after card: TextCard) -> URL? {
        let items = doc.items
        guard let index = items.firstIndex(where: { $0.selection == .text(card.id) }) else { return firstPhoto }
        for item in items[(index + 1)...] {
            switch item.kind {
            case .photo(let url), .cover(let url), .credits(let url): return url
            case .collage(let row): return row.files.first
            default: continue
            }
        }
        return firstPhoto
    }

    private var key: Key {
        let id: String?
        let total: Int
        let template: String?
        switch doc.mode {
        case .photos: id = doc.files.first?.lastPathComponent; total = doc.files.count; template = nil
        case .collage: id = doc.rows.first?.id.uuidString; total = doc.rows.count; template = doc.rows.first?.template.name
        }
        let card = previewCard
        return Key(card: card, cardPhoto: card.flatMap { photo(after: $0) },
                   titleStyle: doc.titleStyle, captionStyle: doc.captionStyle, pattern: doc.captionPattern,
                   firstPhoto: firstPhoto, firstCaptionId: id, ownCaption: id.flatMap { doc.itemCaptions[$0] }, format: doc.format, total: total,
                   templateName: template)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Vista previa").font(.subheadline.weight(.semibold))
            if previewCard == nil, captionText == nil {
                Text("Añade una tarjeta de texto o un patrón de pie para ver cómo quedan sobre el vídeo.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            if let card = previewCard {
                preview(cardImage, label: card.background == nil ? "Texto · sobre el siguiente" : "Texto · pantalla propia")
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
        let result = await Task.detached(priority: .userInitiated) { () -> (CGImage?, CGImage?) in
            let photo = key.firstPhoto.flatMap { ThumbnailProvider.makeThumbnail(url: $0, maxPixelSize: 900) }
            var cardImage: CGImage?
            if let card = key.card {
                let style = card.style ?? key.titleStyle
                if let background = card.background {
                    cardImage = try? TextRenderer.card(lines: card.lines, style: style, background: background.fill, canvas: canvas)
                } else {
                    let under = key.cardPhoto.flatMap { ThumbnailProvider.makeThumbnail(url: $0, maxPixelSize: 900) } ?? photo
                    cardImage = Self.compose(photo: under, layer: TextRenderer.layer(lines: card.lines, style: style, canvas: canvas), canvas: canvas)
                }
            }
            let captionImage = text.flatMap { Self.compose(photo: photo, layer: TextRenderer.layer(lines: [$0], style: key.captionStyle, canvas: canvas), canvas: canvas) }
            return (cardImage, captionImage)
        }.value
        guard !Task.isCancelled else { return }
        cardImage = result.0
        caption = result.1
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
