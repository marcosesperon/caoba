import Foundation
import AVFoundation
import CoreImage
import CoreImage.CIFilterBuiltins
import CoreGraphics

/// Escribe el vídeo (sin audio) fotograma a fotograma con AVAssetWriter.
/// Cada fotograma se compone en Core Image: foto escalada o con Ken Burns,
/// fundido con la siguiente y marca de agua.
public final class VideoWriter {
    private let spec: SlideshowSpec
    private let timeline: SlideshowTimeline
    private let size: PixelSize
    private let context: CIContext
    private var cache: [Int: CIImage] = [:]
    private var watermarkImage: CIImage?
    /// Pies y títulos ya dibujados, por índice de foto (y por caracteres visibles en la máquina de escribir).
    private var captionLayers: [Int: TextLayer] = [:]
    private var overlayLayers: [Int: TextLayer] = [:]
    private var typewriterLayers: [String: TextLayer] = [:]

    public init(spec: SlideshowSpec, timeline: SlideshowTimeline) {
        self.spec = spec
        self.timeline = timeline
        size = spec.renderSize
        let srgb = CGColorSpace(name: CGColorSpace.sRGB)!
        context = CIContext(options: [.workingColorSpace: srgb, .outputColorSpace: srgb, .cacheIntermediates: false])
    }

    /// Bitrate medio según resolución (alto, para fotos con detalle). La vista previa usa la
    /// misma fórmula que el vídeo final: así el codificador recibe los mismos ajustes que al
    /// generar (antes iba a la cuarta parte y en un iMac Intel la app se cerraba al empezar).
    static func bitrate(for size: PixelSize) -> Int {
        let pixels = size.width * size.height
        return Int(Double(pixels) * 6.0) // ≈ 12 Mbps a 1080p
    }

    /// Renderiza todo el vídeo en `url`.
    public func write(to url: URL, progress: ProgressHandler?) async throws {
        TempFiles.remove(url)
        let writer = try AVAssetWriter(outputURL: url, fileType: .mp4)
        let settings: [String: Any] = [
            AVVideoCodecKey: AVVideoCodecType.h264,
            AVVideoWidthKey: size.width,
            AVVideoHeightKey: size.height,
            AVVideoCompressionPropertiesKey: [
                AVVideoAverageBitRateKey: Self.bitrate(for: size),
                AVVideoProfileLevelKey: AVVideoProfileLevelH264HighAutoLevel,
                AVVideoExpectedSourceFrameRateKey: spec.fps,
                AVVideoMaxKeyFrameIntervalKey: spec.fps * 2,
                AVVideoAllowFrameReorderingKey: true,
            ],
            AVVideoColorPropertiesKey: [
                AVVideoColorPrimariesKey: AVVideoColorPrimaries_ITU_R_709_2,
                AVVideoTransferFunctionKey: AVVideoTransferFunction_ITU_R_709_2,
                AVVideoYCbCrMatrixKey: AVVideoYCbCrMatrix_ITU_R_709_2,
            ],
        ]
        let input = AVAssetWriterInput(mediaType: .video, outputSettings: settings)
        input.expectsMediaDataInRealTime = false
        let adaptor = AVAssetWriterInputPixelBufferAdaptor(assetWriterInput: input, sourcePixelBufferAttributes: [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
            kCVPixelBufferWidthKey as String: size.width,
            kCVPixelBufferHeightKey as String: size.height,
            kCVPixelBufferCGImageCompatibilityKey as String: true,
        ])
        guard writer.canAdd(input) else { throw CaobaError.cannotWriteImage("video input") }
        writer.add(input)
        writer.metadata = spec.metadata.items()
        guard writer.startWriting() else { throw CaobaError.cannotWriteImage(writer.error?.localizedDescription ?? "startWriting") }
        writer.startSession(atSourceTime: .zero)

        let totalFrames = Int((timeline.totalDuration * Double(spec.fps)).rounded())
        let frameDuration = CMTime(value: 1, timescale: CMTimeScale(spec.fps))
        try loadWatermarkInternal()

        for frame in 0..<totalFrames {
            if Task.isCancelled {
                writer.cancelWriting()
                throw CaobaError.cancelled
            }
            let t = Double(frame) / Double(spec.fps)
            let image = try composeFrame(at: t)
            while !input.isReadyForMoreMediaData {
                try await Task.sleep(for: .milliseconds(2))
            }
            guard let pool = adaptor.pixelBufferPool else { throw CaobaError.cannotWriteImage("pixel pool") }
            var buffer: CVPixelBuffer?
            CVPixelBufferPoolCreatePixelBuffer(nil, pool, &buffer)
            guard let buffer else { throw CaobaError.cannotWriteImage("pixel buffer") }
            context.render(image, to: buffer, bounds: CGRect(x: 0, y: 0, width: size.width, height: size.height),
                           colorSpace: CGColorSpace(name: CGColorSpace.sRGB))
            let time = CMTimeMultiply(frameDuration, multiplier: Int32(frame))
            guard adaptor.append(buffer, withPresentationTime: time) else {
                throw CaobaError.cannotWriteImage(writer.error?.localizedDescription ?? "append")
            }
            if frame % 5 == 0 {
                let current = timeline.frame(at: t)?.current ?? 0
                progress?(JobProgress(phase: .encodingVideo, fraction: Double(frame) / Double(max(1, totalFrames)),
                                      currentFile: spec.photos.indices.contains(current) ? spec.photos[current].displayName : nil))
            }
        }
        input.markAsFinished()
        await writer.finishWriting()
        if writer.status != .completed {
            throw CaobaError.cannotWriteImage(writer.error?.localizedDescription ?? "finishWriting")
        }
        cache = [:]
    }

    // MARK: Composición de fotogramas

    private var canvasRect: CGRect { CGRect(x: 0, y: 0, width: size.width, height: size.height) }

    /// Fotograma completo en el instante `t`.
    func composeFrame(at t: Double) throws -> CIImage {
        guard let visible = timeline.entry(at: t) else { return black }
        var frame = try photoFrame(index: visible.current, time: t)
        if let next = visible.incoming {
            // Transición de entrada de la foto que llega, sobre la que se va.
            let incoming = try photoFrame(index: next, time: t)
            let kind = spec.resolvedTransition(for: next).kind
            frame = Transitions.compose(from: frame, to: incoming, kind: kind, progress: visible.progress, size: size)
        } else if visible.fromBlack {
            let kind = spec.resolvedTransition(for: visible.current).kind
            frame = Transitions.compose(from: nil, to: frame, kind: kind, progress: visible.progress, size: size)
        }
        if let watermarkImage {
            frame = watermarkImage.composited(over: frame)
        }
        // Liberamos fotos (y sus textos) que ya no van a volver a verse.
        for key in cache.keys where key < visible.current - 1 { cache.removeValue(forKey: key) }
        for key in captionLayers.keys where key < visible.current - 1 { captionLayers.removeValue(forKey: key) }
        for key in overlayLayers.keys where key < visible.current - 1 { overlayLayers.removeValue(forKey: key) }
        if visible.current > 0 {
            for key in typewriterLayers.keys where key.hasPrefix("c\(visible.current - 2)-") || key.hasPrefix("o\(visible.current - 2)-") { typewriterLayers.removeValue(forKey: key) }
        }
        return frame.cropped(to: canvasRect)
    }

    private var black: CIImage { CIImage(color: .black).cropped(to: canvasRect) }

    /// Fotograma de una foto concreta en el instante global `t`.
    private func photoFrame(index: Int, time t: Double) throws -> CIImage {
        let photo = spec.photos[index]
        let segment = timeline.segments[index]
        let image = try cachedImage(for: index)
        let imageSize = PixelSize(width: Int(image.extent.width), height: Int(image.extent.height))
        let local = max(0, t - segment.start)

        var frame: CIImage
        if photo.kenBurns != nil, photo.points?.fit != .contain,
           let crop = KenBurns.cropRect(for: photo, imageSize: imageSize, targetSize: size, time: local,
                                        segmentDuration: segment.duration, settings: spec.kenBurns) {
            frame = fill(image, crop: crop)
        } else {
            frame = fit(image)
        }
        // Pie y título van dentro del fotograma de la foto: las transiciones los arrastran con ella.
        // El pie entra al empezar la foto y sale antes de que empiece la transición a la siguiente.
        if let caption = captionLayer(for: index) {
            var style = spec.captionStyle
            if let own = photo.captionAnimation { style.animation = own }
            // Con tiempo de muestra propio el pie se va antes; si no, dura toda la foto.
            let total = style.holdSeconds.map { min(photo.duration, TextPhase.totalDuration(style: style, hold: $0)) } ?? photo.duration
            if let phase = TextPhase.at(local, total: total, style: style, entry: photo.captionEntry, exit: photo.captionExit) {
                frame = animatedLayer(caption, lines: [photo.caption ?? ""], style: style, phase: phase, key: "c\(index)").composited(over: frame)
            }
        }
        if let overlay = photo.overlay, let layer = overlayLayer(for: index), let phase = overlay.phase(at: local) {
            frame = animatedLayer(layer, lines: overlay.lines, style: overlay.style, phase: phase, key: "o\(index)").composited(over: frame)
        }
        return frame
    }

    /// Capa en su punto de animación (entrada o salida); la máquina de escribir vuelve a dibujar con los caracteres que tocan.
    private func animatedLayer(_ layer: TextLayer, lines: [String], style: TextStyle, phase: TextPhase, key: String) -> CIImage {
        let animation = phase.exiting ? style.resolvedExit : style.animation
        guard animation == .typewriter, phase.progress < 0.999 else {
            return TextRenderer.animated(layer, animation: animation, phase: phase, canvas: size)
        }
        let count = Int((phase.progress * Double(layer.characters)).rounded())
        let cacheKey = "\(key)-\(count)"
        if let cached = typewriterLayers[cacheKey] { return CIImage(cgImage: cached.image) }
        guard let partial = TextRenderer.render(lines: lines, style: style, canvas: size, visibleCharacters: count) else { return CIImage(cgImage: layer.image) }
        typewriterLayers[cacheKey] = partial
        return CIImage(cgImage: partial.image)
    }

    private func captionLayer(for index: Int) -> TextLayer? {
        if let cached = captionLayers[index] { return cached }
        guard let text = spec.photos[index].caption, !text.isEmpty,
              let layer = TextRenderer.render(lines: [text], style: spec.captionStyle, canvas: size) else { return nil }
        captionLayers[index] = layer
        return layer
    }

    private func overlayLayer(for index: Int) -> TextLayer? {
        if let cached = overlayLayers[index] { return cached }
        guard let overlay = spec.photos[index].overlay,
              let layer = TextRenderer.render(lines: overlay.lines, style: overlay.style, canvas: size) else { return nil }
        overlayLayers[index] = layer
        return layer
    }

    /// Recorte (origen arriba-izquierda) escalado para llenar el lienzo.
    private func fill(_ image: CIImage, crop: CGRect) -> CIImage {
        let h = image.extent.height
        // Core Image tiene el origen abajo: convertimos el recorte.
        let ciCrop = CGRect(x: crop.minX, y: h - crop.maxY, width: crop.width, height: crop.height)
        let cropped = image.cropped(to: ciCrop).transformed(by: CGAffineTransform(translationX: -ciCrop.minX, y: -ciCrop.minY))
        let sx = Double(size.width) / crop.width, sy = Double(size.height) / crop.height
        return cropped.transformed(by: CGAffineTransform(scaleX: sx, y: sy)).composited(over: black).cropped(to: canvasRect)
    }

    /// Foto entera centrada sobre negro (escalado "contain", como el pad antiguo).
    private func fit(_ image: CIImage) -> CIImage {
        let scale = min(Double(size.width) / image.extent.width, Double(size.height) / image.extent.height)
        let w = image.extent.width * scale, h = image.extent.height * scale
        let dx = (Double(size.width) - w) / 2, dy = (Double(size.height) - h) / 2
        return image
            .transformed(by: CGAffineTransform(translationX: -image.extent.minX, y: -image.extent.minY))
            .transformed(by: CGAffineTransform(scaleX: scale, y: scale))
            .transformed(by: CGAffineTransform(translationX: dx, y: dy))
            .composited(over: black).cropped(to: canvasRect)
    }

    /// Decodifica (reducida a lo necesario) y cachea la foto.
    private func cachedImage(for index: Int) throws -> CIImage {
        if let cached = cache[index] { return cached }
        let photo = spec.photos[index]
        // Con Ken Burns y zoom hasta 2x hace falta más resolución que el lienzo.
        let factor = photo.kenBurns == nil ? 1.2 : 2.4
        let needed = PixelSize(width: Int(Double(size.width) * factor), height: Int(Double(size.height) * factor))
        let cg = try PhotoLoader.load(photo.url, fittingAtLeast: needed)
        let image = CIImage(cgImage: cg)
        cache[index] = image
        return image
    }

    func loadWatermarkInternal() throws {
        guard let wm = spec.watermark else { return }
        let cg = try ImageIOHelpers.loadImage(from: wm.url)
        let shortSide = min(size.width, size.height)
        let targetW = max(1, Double(shortSide) * wm.sizePercent / 100)
        let scale = targetW / Double(cg.width)
        let targetH = Double(cg.height) * scale
        let pixelSize = PixelSize(width: Int(targetW.rounded()), height: Int(targetH.rounded()))
        let origin = wm.position.origin(for: pixelSize, in: size)
        let alpha = min(100, max(0, wm.opacity)) / 100
        let faded = CIImage(cgImage: cg)
            .transformed(by: CGAffineTransform(scaleX: scale, y: scale))
            .applyingFilter("CIColorMatrix", parameters: ["inputAVector": CIVector(x: 0, y: 0, z: 0, w: alpha)])
        // Posición: convertimos la Y de arriba-izquierda a abajo-izquierda.
        let y = Double(size.height) - origin.y - targetH
        watermarkImage = faded.transformed(by: CGAffineTransform(translationX: origin.x, y: y))
    }
}
