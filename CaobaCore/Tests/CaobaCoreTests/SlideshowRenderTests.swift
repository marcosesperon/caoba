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
        #expect(segments[0].start == 0 && segments[0].end == 20 && segments[0].fadeIn == false && segments[0].fadeOut == true)
        #expect(segments[0].gain == 0.5)
        #expect(segments[1].start == 17 && segments[1].end == 41 && segments[1].fadeIn == true && segments[1].fadeOut == true)
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
        #expect(segments[0].start == 0 && segments[0].end == 9 && segments[0].fadeOut == true)
        #expect(segments[1].start == 6 && segments[1].end == 12 && segments[1].fadeOut == false)
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
        #expect(segments.last!.end == 100 && segments.last!.fadeOut == true)
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
        #expect(result.size == CGSize(width: 960, height: 540)) // preview a la mitad
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
        let size = spec.renderSize // 960x540

        // Foto 0: 1200x800 (3:2) en 16:9 → bandas negras a los lados, foto entera.
        try writer.loadWatermarkForTests()
        let f0 = ctx.createCGImage(try writer.composeFrame(at: 0.5), from: CGRect(x: 0, y: 0, width: size.width, height: size.height))!
        let edge = TestImages.pixel(f0, x: 5, y: 270)
        #expect(edge.r < 10 && edge.g < 10 && edge.b < 10)
        #expect(TestImages.isRed(TestImages.pixel(f0, x: 200, y: 150)))   // cuadrante rojo (arriba-izquierda de la foto)
        #expect(TestImages.isWhite(TestImages.pixel(f0, x: 760, y: 400))) // blanco abajo-derecha
        #expect(TestImages.isBlue(TestImages.pixel(f0, x: 40, y: 40)))    // marca de agua azul arriba-izquierda

        // Foto 1: vertical con Ken Burns → cover: sin bandas negras.
        let f1 = ctx.createCGImage(try writer.composeFrame(at: 2.5), from: CGRect(x: 0, y: 0, width: size.width, height: size.height))!
        let corner = TestImages.pixel(f1, x: 5, y: 530)
        #expect(!(corner.r < 10 && corner.g < 10 && corner.b < 10))
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
