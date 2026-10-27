import Testing
import Foundation
import CoreGraphics
import AVFoundation
import CoreImage
@testable import CaobaCore

@Suite("AudioPlan")
struct AudioPlanTests {
    @Test("Encadenado automático con crossfade y fundido final")
    func automatic() {
        let timeline = SlideshowTimeline(durations: Array(repeating: 4, count: 10), transition: 1) // 41 s
        let a = AudioTrack(url: URL(fileURLWithPath: "/a.mp3"))
        let b = AudioTrack(url: URL(fileURLWithPath: "/b.mp3"))
        let segments = AudioPlan.build(tracks: [a, b], durations: [20, 60], gains: [0.5, 1.0], timeline: timeline, fadeOutAtEnd: true)
        #expect(segments.count == 2)
        #expect(segments[0].start == 0 && segments[0].end == 20 && segments[0].fadeInSeconds == 0 && segments[0].fadeOutSeconds == 3)
        #expect(segments[0].gain == 0.5)
        #expect(segments[1].start == 17 && segments[1].end == 41 && segments[1].fadeInSeconds == 3 && segments[1].fadeOutSeconds == 3)
    }

    @Test("Inicio en un segundo concreto del vídeo")
    func atTime() {
        let timeline = SlideshowTimeline(durations: [5, 5, 5, 5], transition: 0) // 20 s
        let a = AudioTrack(url: URL(fileURLWithPath: "/a.mp3"))
        let b = AudioTrack(url: URL(fileURLWithPath: "/b.mp3"), startMode: .atTime(7.5))
        let segments = AudioPlan.build(tracks: [a, b], durations: [100, 100], gains: nil, timeline: timeline, fadeOutAtEnd: false)
        #expect(segments[0].end == 10.5 && segments[1].start == 7.5 && segments[1].end == 20)
    }

    @Test("Inicio manual en una foto y sin fundido final")
    func manual() {
        let timeline = SlideshowTimeline(durations: [3, 3, 3, 3], transition: 0) // 12 s
        let a = AudioTrack(url: URL(fileURLWithPath: "/a.mp3"))
        let b = AudioTrack(url: URL(fileURLWithPath: "/b.mp3"), startMode: .atPhoto(2))
        let segments = AudioPlan.build(tracks: [a, b], durations: [100, 100], gains: nil, timeline: timeline, fadeOutAtEnd: false)
        #expect(segments[0].start == 0 && segments[0].end == 9 && segments[0].fadeOutSeconds == 3)
        #expect(segments[1].start == 6 && segments[1].end == 12 && segments[1].fadeOutSeconds == 0)
    }
}

@Suite("AudioPlan cruces")
struct AudioPlanCrossfadeTests {
    let a = AudioTrack(url: URL(fileURLWithPath: "/a.mp3"))
    let b = AudioTrack(url: URL(fileURLWithPath: "/b.mp3"))
    let timeline = SlideshowTimeline(durations: Array(repeating: 10, count: 6), transition: 0) // 60 s

    @Test("Cruce general de 6 s: la segunda entra 6 s antes y la primera baja en ese tiempo")
    func general() {
        let s = AudioPlan.build(tracks: [a, b], durations: [30, 60], gains: nil, timeline: timeline, fadeOutAtEnd: true, crossfade: 6, fadeOutDuration: 8)
        #expect(s[0].start == 0 && s[0].end == 30 && s[0].fadeOutSeconds == 6)
        #expect(s[1].start == 24 && s[1].fadeInSeconds == 6)
        // El fundido final usa su propia duración.
        #expect(s[1].end == 60 && s[1].fadeOutSeconds == 8)
        #expect(s[0].trackID == a.id && s[1].trackID == b.id)
    }

    @Test("La entrada propia de una pista manda sobre la general")
    func own() {
        var own = b; own.crossfade = 1.5
        let s = AudioPlan.build(tracks: [a, own], durations: [30, 60], gains: nil, timeline: timeline, fadeOutAtEnd: false, crossfade: 6)
        #expect(s[1].start == 28.5 && s[1].fadeInSeconds == 1.5 && s[0].fadeOutSeconds == 1.5 && s[0].end == 30)
    }

    @Test("Con 0 es un corte seco, también con inicio fijo")
    func cut() {
        var fixed = b; fixed.startMode = .atTime(20)
        let s = AudioPlan.build(tracks: [a, fixed], durations: [30, 60], gains: nil, timeline: timeline, fadeOutAtEnd: false, crossfade: 0)
        #expect(s[0].end == 20 && s[0].fadeOutSeconds == 0)
        #expect(s[1].start == 20 && s[1].fadeInSeconds == 0)
    }

    @Test("Al repetir la lista, cada vuelta entra con su cruce")
    func loop() {
        var own = a; own.crossfade = 2
        let s = AudioPlan.build(tracks: [own, b], durations: [25, 25], gains: nil, timeline: timeline, fadeOutAtEnd: false, loopPlaylist: true, crossfade: 5)
        // a (0–25), b entra en 20 con 5 s; a vuelve en 43 (45 − 2) con 2 s.
        #expect(s.map(\.start) == [0, 20, 43])
        #expect(s[2].fadeInSeconds == 2 && s[1].fadeOutSeconds == 2)
    }

    @Test("Fundido final al acabar el vídeo aunque una pista con inicio fijo empiece después")
    func fadeOutWithTrackAfterEnd() {
        // b empieza en 70 s, con el vídeo ya acabado (60 s): no suena, y a baja al final.
        var after = b; after.startMode = .atTime(70)
        let s = AudioPlan.build(tracks: [a, after], durations: [100, 100], gains: nil, timeline: timeline, fadeOutAtEnd: true, crossfade: 6, fadeOutDuration: 4)
        #expect(s.count == 1)
        #expect(s[0].trackID == a.id && s[0].end == 60 && s[0].fadeOutSeconds == 4)
        // Si b entra 1 s antes del final, las dos suenan al acabar y bajan juntas; a conserva su cruce de 6 s.
        var late = b; late.startMode = .atTime(59)
        let both = AudioPlan.build(tracks: [a, late], durations: [100, 100], gains: nil, timeline: timeline, fadeOutAtEnd: true, crossfade: 6, fadeOutDuration: 4)
        #expect(both.count == 2)
        #expect(both[0].end == 60 && both[0].fadeOutSeconds == 6)
        #expect(both[1].end == 60 && both[1].fadeOutSeconds == 4)
    }

    @Test("Los cruces van por orden de inicio en el vídeo, aunque la lista esté en otro orden")
    func listOrderDiffersFromTime() {
        var late = b; late.startMode = .atTime(24)
        var early = a; early.startMode = .atTime(0)
        // En la lista va primero la que empieza más tarde.
        let s = AudioPlan.build(tracks: [late, early], durations: [100, 100], gains: nil, timeline: timeline, fadeOutAtEnd: false, crossfade: 6)
        #expect(s.count == 2)
        #expect(s[0].trackID == early.id && s[0].start == 0 && s[0].end == 30 && s[0].fadeOutSeconds == 6)
        #expect(s[1].trackID == late.id && s[1].start == 24 && s[1].end == 60 && s[1].fadeInSeconds == 6)
    }

    @Test("Las configuraciones antiguas abren con 3 s de cruce y de fundido final")
    func oldConfig() throws {
        let json = #"{"tracks":[{"url":"file:///a.mp3"}],"fadeOut":true,"normalize":false}"#
        let options = try JSONDecoder().decode(AudioOptions.self, from: Data(json.utf8))
        #expect(options.crossfade == 3 && options.fadeOutDuration == 3 && options.tracks[0].crossfade == nil)
    }
}

@Suite("AudioPlan repetición")
struct AudioPlanLoopTests {
    @Test("Con la lista en bucle, tras la última pista vuelve la primera")
    func loops() {
        let timeline = SlideshowTimeline(durations: Array(repeating: 10, count: 10), transition: 0) // 100 s
        let a = AudioTrack(url: URL(fileURLWithPath: "/a.mp3"))
        let b = AudioTrack(url: URL(fileURLWithPath: "/b.mp3"))
        let segments = AudioPlan.build(tracks: [a, b], durations: [30, 30], gains: nil, timeline: timeline, fadeOutAtEnd: true, loopPlaylist: true)
        #expect(segments.map(\.url.lastPathComponent) == ["a.mp3", "b.mp3", "a.mp3", "b.mp3"])
        #expect(segments.map(\.start) == [0, 27, 54, 81])
        #expect(segments.last!.end == 100 && segments.last!.fadeOutSeconds == 3)
        // Sin bucle, la última se alarga hasta el final.
        let single = AudioPlan.build(tracks: [a, b], durations: [30, 30], gains: nil, timeline: timeline, fadeOutAtEnd: false, loopPlaylist: false)
        #expect(single.count == 2 && single[1].end == 100)
    }
}

@Suite("AudioPlan recorte")
struct AudioPlanTrimTests {
    @Test("El recorte acorta la pista y adelanta la siguiente")
    func trimmed() {
        let timeline = SlideshowTimeline(durations: Array(repeating: 4, count: 20), transition: 0) // 80 s
        let a = AudioTrack(url: URL(fileURLWithPath: "/a.mp3"), trimStart: 10, trimEnd: 40) // suena 30 s
        let b = AudioTrack(url: URL(fileURLWithPath: "/b.mp3"))
        let segments = AudioPlan.build(tracks: [a, b], durations: [200, 200], gains: nil, timeline: timeline, fadeOutAtEnd: false)
        #expect(segments[0].start == 0 && segments[0].end == 30 && segments[0].trimStart == 10 && segments[0].trimEnd == 40)
        #expect(segments[1].start == 27 && segments[1].end == 80)
        #expect(a.effectiveDuration(assetDuration: 200) == 30)
        #expect(AudioTrack(url: URL(fileURLWithPath: "/x"), trimStart: 500).effectiveDuration(assetDuration: 100) == 0.5)
    }

    @Test("Una pista guardada sin recorte se decodifica con valores por defecto")
    func decodeLegacy() throws {
        let json = #"{"id":"6F9619FF-8B86-D011-B42D-00C04FC964FF","url":"file:///a.mp3","startMode":{"automatic":{}}}"#
        let track = try JSONDecoder().decode(AudioTrack.self, from: Data(json.utf8))
        #expect(track.trimStart == 0 && track.trimEnd == nil)
    }
}

@Suite("SlideshowRenderer", .serialized)
struct SlideshowRendererTests {
    private func makePhotos(in folder: URL) throws -> [URL] {
        [try TestImages.makePhoto(in: folder, name: "a.jpg", width: 1200, height: 800),
         try TestImages.makePhoto(in: folder, name: "b.jpg", width: 600, height: 900, orientation: .right),
         try TestImages.makePhoto(in: folder, name: "c.jpg", width: 800, height: 800)]
    }

    private func info(_ url: URL) async throws -> (duration: Double, size: CGSize, hasAudio: Bool) {
        let asset = AVURLAsset(url: url)
        let duration = CMTimeGetSeconds(try await asset.load(.duration))
        let video = try await asset.loadTracks(withMediaType: .video).first!
        let size = try await video.load(.naturalSize)
        let hasAudio = !(try await asset.loadTracks(withMediaType: .audio)).isEmpty
        return (duration, size, hasAudio)
    }

    /// Etiquetas 3GPP del MP4 (las únicas que AVAssetWriter guarda en .mp4), como texto.
    private func tags(_ url: URL) async throws -> [AVMetadataIdentifier: String] {
        var result: [AVMetadataIdentifier: String] = [:]
        for item in try await AVURLAsset(url: url).load(.metadata) {
            guard let id = item.identifier, let value = try await item.load(.stringValue) else { continue }
            result[id] = value
        }
        return result
    }

    @Test("Etiquetas del MP4 sin música: descripción y autor; sin autor no se escribe")
    func metadataWithoutAudio() async throws {
        let folder = try TestImages.makeTempFolder()
        let photo = try TestImages.makePhoto(in: folder, name: "a.jpg", width: 800, height: 600)
        let output = folder.appendingPathComponent("tags.mp4")
        var spec = SlideshowSpec(photos: [SlideshowPhoto(url: photo, duration: 0.5)], format: .landscape16x9,
                                 transition: false, output: output, preview: true)
        spec.metadata = VideoMetadata(author: "  Ana Ficticia ", comment: "Creado con CAOBA — https://caobafoto.com")
        try await SlideshowRenderer.generate(spec)

        let written = try await tags(output)
        #expect(written[.identifier3GPUserDataDescription] == "Creado con CAOBA — https://caobafoto.com")
        #expect(written[.identifier3GPUserDataAuthor] == "Ana Ficticia")
        #expect(written[.identifier3GPUserDataPerformer] == "Ana Ficticia")
        #expect(written[AVMetadataIdentifier(rawValue: "uiso/date")] != nil)

        spec.metadata = VideoMetadata(author: "   ", comment: "x")
        try await SlideshowRenderer.generate(spec)
        let empty = try await tags(output)
        #expect(empty[.identifier3GPUserDataAuthor] == nil)
        #expect(empty[.identifier3GPUserDataPerformer] == nil)
        #expect(empty[.identifier3GPUserDataDescription] == "x")
    }

    @Test("Vídeo con fundido, marca de agua y dos pistas de audio")
    func fullRender() async throws {
        let folder = try TestImages.makeTempFolder()
        let photos = try makePhotos(in: folder)
        let wm = folder.appendingPathComponent("wm.png")
        try TestImages.write(TestImages.solid(width: 200, height: 100, r: 1, g: 0, b: 0, a: 1), to: wm, format: .png)
        let track1 = folder.appendingPathComponent("t1.m4a"), track2 = folder.appendingPathComponent("t2.m4a")
        try TestAudio.writeTone(to: track1, dbfs: -20, seconds: 4)
        try TestAudio.writeTone(to: track2, dbfs: -30, seconds: 4)
        let output = folder.appendingPathComponent("out.mp4")

        var spec = SlideshowSpec(
            photos: photos.map { SlideshowPhoto(url: $0, duration: 1.5) },
            format: .landscape16x9, fps: 25, transition: true,
            watermark: VideoWatermark(url: wm, position: .bottomRight, sizePercent: 30, opacity: 80),
            audio: AudioOptions(tracks: [AudioTrack(url: track1), AudioTrack(url: track2)], fadeOut: true, normalize: true),
            output: output, preview: true
        )
        spec.metadata = VideoMetadata(author: "Ana Ficticia", comment: "Made with CAOBA — https://caobafoto.com")
        let phases = PhaseCollector()
        try await SlideshowRenderer.generate(spec) { p in phases.insert(p.phase) }

        let result = try await info(output)
        #expect(abs(result.duration - 5.5) < 0.1) // 3 × 1,5 + 1 de transición
        #expect(result.size == CGSize(width: 640, height: 360)) // vista previa: lado mayor de 640
        #expect(result.hasAudio)
        let written = try await tags(output)
        #expect(written[.identifier3GPUserDataDescription] == "Made with CAOBA — https://caobafoto.com")
        #expect(written[.identifier3GPUserDataAuthor] == "Ana Ficticia")
        #expect(phases.seen.isSuperset(of: [.analyzingAudio, .encodingVideo, .mixingAudio]))
    }

    @Test("Fotogramas: contain sobre negro, Ken Burns llena el lienzo, marca de agua visible")
    func frames() throws {
        let folder = try TestImages.makeTempFolder()
        let photos = try makePhotos(in: folder)
        let wm = folder.appendingPathComponent("wm.png")
        try TestImages.write(TestImages.solid(width: 100, height: 100, r: 0, g: 0, b: 1), to: wm, format: .png)
        var spec = SlideshowSpec(photos: [SlideshowPhoto(url: photos[0], duration: 2),
                                          SlideshowPhoto(url: photos[1], duration: 2, kenBurns: .zoomIn)],
                                 format: .landscape16x9, transition: false,
                                 watermark: VideoWatermark(url: wm, position: .topLeft, sizePercent: 20, opacity: 100),
                                 output: folder.appendingPathComponent("x.mp4"), preview: true)
        spec.kenBurns = KenBurnsSettings(intensity: .normal, easing: .linear, durationPercent: 100)
        let writer = VideoWriter(spec: spec, timeline: SlideshowTimeline(durations: [2, 2], transition: 0))
        let ctx = CIContext()
        let size = spec.renderSize // 640x360
        // Puntos en proporción del lienzo, para que no dependan del tamaño de la vista previa.
        func at(_ fx: Double, _ fy: Double) -> (x: Int, y: Int) { (Int(Double(size.width) * fx), Int(Double(size.height) * fy)) }

        // Foto 0: 1200x800 (3:2) en 16:9 → bandas negras a los lados, foto entera.
        try writer.loadWatermarkForTests()
        let f0 = ctx.createCGImage(try writer.composeFrame(at: 0.5), from: CGRect(x: 0, y: 0, width: size.width, height: size.height))!
        let edge = TestImages.pixel(f0, x: 3, y: at(0, 0.5).y)
        #expect(edge.r < 10 && edge.g < 10 && edge.b < 10)
        #expect(TestImages.isRed(TestImages.pixel(f0, x: at(0.21, 0.28).x, y: at(0.21, 0.28).y)))   // cuadrante rojo (arriba-izquierda de la foto)
        #expect(TestImages.isWhite(TestImages.pixel(f0, x: at(0.79, 0.74).x, y: at(0.79, 0.74).y))) // blanco abajo-derecha
        #expect(TestImages.isBlue(TestImages.pixel(f0, x: at(0.04, 0.07).x, y: at(0.04, 0.07).y)))  // marca de agua azul arriba-izquierda

        // Foto 1: vertical con Ken Burns → cover: sin bandas negras.
        let f1 = ctx.createCGImage(try writer.composeFrame(at: 2.5), from: CGRect(x: 0, y: 0, width: size.width, height: size.height))!
        let corner = TestImages.pixel(f1, x: 3, y: size.height - 7)
        #expect(!(corner.r < 10 && corner.g < 10 && corner.b < 10))
    }

    @Test("Vista previa: lado mayor de 640, misma proporción, píxeles pares y la calidad por píxel del vídeo final")
    func previewSize() {
        let url = URL(fileURLWithPath: "/tmp/x.mp4")
        func size(_ format: VideoFormat) -> PixelSize { SlideshowSpec(photos: [], format: format, output: url, preview: true).renderSize }
        #expect(size(.landscape16x9) == PixelSize(width: 640, height: 360))
        #expect(size(.portrait9x16) == PixelSize(width: 360, height: 640))
        #expect(size(.portrait4x5) == PixelSize(width: 512, height: 640))
        #expect(size(.portrait2x3) == PixelSize(width: 426, height: 640))
        // El vídeo final no cambia.
        #expect(SlideshowSpec(photos: [], format: .landscape16x9, output: url).renderSize == PixelSize(width: 1920, height: 1080))
        // Misma fórmula de bitrate que el final: proporcional a los píxeles.
        #expect(VideoWriter.bitrate(for: PixelSize(width: 640, height: 360)) * 9 == VideoWriter.bitrate(for: PixelSize(width: 1920, height: 1080)))
    }

    @Test("El progreso de codificación enseña la etiqueta de la foto o, sin ella, el nombre del fichero")
    func progressNames() async throws {
        let folder = try TestImages.makeTempFolder()
        let urls = try makePhotos(in: folder)
        var photos = urls.prefix(2).map { SlideshowPhoto(url: $0, duration: 1) }
        photos[1].label = "Collage 1 · Mosaico"
        let spec = SlideshowSpec(photos: photos, format: .landscape16x9, transition: false,
                                 output: folder.appendingPathComponent("p.mp4"), preview: true)
        let names = NameCollector()
        try await SlideshowRenderer.generate(spec) { p in if p.phase == .encodingVideo, let n = p.currentFile { names.insert(n) } }
        #expect(names.seen == ["a.jpg", "Collage 1 · Mosaico"])
    }

    @Test("Cancelar durante la codificación")
    func cancel() async throws {
        let folder = try TestImages.makeTempFolder()
        let photos = try makePhotos(in: folder)
        let spec = SlideshowSpec(photos: photos.map { SlideshowPhoto(url: $0, duration: 5) }, format: .landscape16x9,
                                 output: folder.appendingPathComponent("c.mp4"), preview: true)
        let task = Task { try await SlideshowRenderer.generate(spec) }
        try await Task.sleep(for: .milliseconds(300))
        task.cancel()
        await #expect(throws: CaobaError.cancelled) { try await task.value }
    }
}

/// Recoge las fases emitidas desde cualquier hilo.
final class PhaseCollector: @unchecked Sendable {
    private var set: Set<JobPhase> = []
    private let lock = NSLock()
    func insert(_ phase: JobPhase) { lock.lock(); set.insert(phase); lock.unlock() }
    var seen: Set<JobPhase> { lock.lock(); defer { lock.unlock() }; return set }
}

/// Recoge los nombres de fichero del progreso desde cualquier hilo.
final class NameCollector: @unchecked Sendable {
    private var set: Set<String> = []
    private let lock = NSLock()
    func insert(_ name: String) { lock.lock(); set.insert(name); lock.unlock() }
    var seen: Set<String> { lock.lock(); defer { lock.unlock() }; return set }
}

extension VideoWriter {
    /// Acceso para tests: carga la marca de agua sin escribir vídeo.
    func loadWatermarkForTests() throws { try loadWatermarkInternal() }
}
