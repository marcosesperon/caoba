import Testing
import Foundation
import CoreImage
import AVFoundation
@testable import CaobaCore

@Suite("Transiciones")
struct TransitionTests {
    @Test("Timeline con transición distinta por foto: cada una entra durante su propia duración")
    func perItemTimeline() {
        let tl = SlideshowTimeline(durations: [4, 4, 4], transitions: [0, 2, 0.5])
        #expect(tl.segments.map(\.start) == [0, 4, 8])
        #expect(tl.segments.map(\.end) == [6, 8.5, 12.5])
        #expect(tl.totalDuration == 12.5)
        // Entre la 0 y la 1 hay 2 s de solape; entre la 1 y la 2, 0,5 s.
        let a = tl.frame(at: 5)!
        #expect(a.current == 0 && a.next == 1 && abs(a.progress - 0.5) < 1e-9)
        let b = tl.frame(at: 8.25)!
        #expect(b.current == 1 && b.next == 2 && abs(b.progress - 0.5) < 1e-9)
        #expect(tl.frame(at: 8.6)! == (2, nil, 0))
        // La primera foto no entra desde negro si su transición es 0.
        #expect(tl.entry(at: 0.1)!.fromBlack == false)
        let fromBlack = SlideshowTimeline(durations: [4, 4], transitions: [1, 1])
        let e = fromBlack.entry(at: 0.5)!
        #expect(e.fromBlack && e.incoming == nil && abs(e.progress - 0.5) < 1e-9)
    }

    @Test("El spec resuelve la transición de cada foto con los valores por defecto y el atajo antiguo")
    func specResolution() {
        let url = URL(fileURLWithPath: "/tmp/x.jpg")
        var spec = SlideshowSpec(photos: [SlideshowPhoto(url: url, duration: 3),
                                          SlideshowPhoto(url: url, duration: 3, transition: .slideLeft, transitionDuration: 0.5),
                                          SlideshowPhoto(url: url, duration: 3, transition: .cut, transitionDuration: 2)],
                                 format: .landscape16x9, transition: true, output: URL(fileURLWithPath: "/tmp/x.mp4"))
        #expect(spec.resolvedTransition(for: 0) == (.crossfade, 1))
        #expect(spec.resolvedTransition(for: 1) == (.slideLeft, 0.5))
        #expect(spec.resolvedTransition(for: 2) == (.cut, 0))
        spec.defaultTransition = .fadeToBlack
        spec.defaultTransitionDuration = 0.75
        #expect(spec.resolvedTransition(for: 0) == (.fadeToBlack, 0.75))
        spec.transition = false
        #expect(spec.resolvedTransition(for: 0) == (.cut, 0))
        #expect(spec.entryTransitions == [0, 0.5, 0])
    }

    @Test("Cada transición produce un fotograma del tamaño del lienzo en 0, 0,5 y 1, y respeta los extremos")
    func everyKindComposes() {
        let size = PixelSize(width: 320, height: 180)
        let canvas = CGRect(x: 0, y: 0, width: 320, height: 180)
        let red = CIImage(color: CIColor(red: 1, green: 0, blue: 0)).cropped(to: canvas)
        let blue = CIImage(color: CIColor(red: 0, green: 0, blue: 1)).cropped(to: canvas)
        let ctx = CIContext()
        func pixel(_ image: CIImage, _ x: Int, _ y: Int) -> (r: Int, g: Int, b: Int) {
            let cg = ctx.createCGImage(image, from: canvas)!
            return TestImages.pixel(cg, x: x, y: y)
        }
        for kind in TransitionKind.allCases {
            for p in [0.0, 0.5, 1.0] {
                let out = Transitions.compose(from: red, to: blue, kind: kind, progress: p, size: size)
                #expect(out.extent == canvas, "\(kind) a \(p)")
            }
            // Al final siempre se ve la que entra.
            #expect(TestImages.isBlue(pixel(Transitions.compose(from: red, to: blue, kind: kind, progress: 1, size: size), 160, 90)), "\(kind) al final")
            // Al principio se ve la que sale (salvo el corte).
            if kind != .cut {
                #expect(TestImages.isRed(pixel(Transitions.compose(from: red, to: blue, kind: kind, progress: 0, size: size), 160, 90)), "\(kind) al principio")
            }
        }
        // A mitad de un deslizamiento a la izquierda, la izquierda es la que sale y la derecha la que entra.
        let half = Transitions.compose(from: red, to: blue, kind: .slideLeft, progress: 0.5, size: size)
        #expect(TestImages.isRed(pixel(half, 40, 90)))
        #expect(TestImages.isBlue(pixel(half, 280, 90)))
        // Y a mitad de un barrido a la derecha, igual.
        let wipe = Transitions.compose(from: red, to: blue, kind: .wipeRight, progress: 0.5, size: size)
        #expect(TestImages.isBlue(pixel(wipe, 40, 90)))
        #expect(TestImages.isRed(pixel(wipe, 280, 90)))
        // Fundido a negro: en el centro todo es negro.
        let dark = pixel(Transitions.compose(from: red, to: blue, kind: .fadeToBlack, progress: 0.5, size: size), 160, 90)
        #expect(dark.r < 12 && dark.g < 12 && dark.b < 12)
    }

    @Test("El planificador de ritmo usa la transición de entrada del elemento que llega")
    func rhythmUsesEntryTransition() {
        let grid = (0..<100).map { VideoBeat(time: Double($0) * 0.5, period: 0.5) }
        let items = [RhythmItem(), RhythmItem(), RhythmItem()]
        let d = RhythmPlanner.plan(beats: grid, items: items, target: 4, beatsPerCut: 8, entryTransitions: [0, 2, 0])
        // El cambio 0→1 está en d0 + 1 (mitad de 2 s) y debe caer en golpe; el 1→2 en d0 + d1 + 0.
        let c1 = d[0] + 1, c2 = d[0] + d[1]
        #expect(abs(c1 - (c1 / 0.5).rounded() * 0.5) < 1e-9)
        #expect(abs(c2 - (c2 / 0.5).rounded() * 0.5) < 1e-9)
    }

    @Test("El vídeo generado lleva la transición: a mitad de un deslizamiento se ven las dos fotos")
    func renderedVideoHasTransition() async throws {
        let folder = try TestImages.makeTempFolder()
        let red = folder.appendingPathComponent("red.jpg"), blue = folder.appendingPathComponent("blue.jpg")
        try TestImages.write(TestImages.solid(width: 640, height: 360, r: 1, g: 0, b: 0), to: red, format: .jpeg)
        try TestImages.write(TestImages.solid(width: 640, height: 360, r: 0, g: 0, b: 1), to: blue, format: .jpeg)
        let output = folder.appendingPathComponent("t.mp4")
        let spec = SlideshowSpec(photos: [SlideshowPhoto(url: red, duration: 2, transition: .cut),
                                          SlideshowPhoto(url: blue, duration: 2, transition: .slideLeft, transitionDuration: 1)],
                                 format: .landscape16x9, transition: true, output: output, preview: true)
        _ = try await SlideshowRenderer.generate(spec)
        let asset = AVURLAsset(url: output)
        let generator = AVAssetImageGenerator(asset: asset)
        generator.requestedTimeToleranceBefore = .zero
        generator.requestedTimeToleranceAfter = .zero
        let (frame, _) = try await generator.image(at: CMTime(seconds: 2.5, preferredTimescale: 600))
        // A mitad del deslizamiento: la mitad izquierda es la foto que sale (roja), la derecha la que entra (azul).
        let w = frame.width, h = frame.height
        #expect(TestImages.isRed(TestImages.pixel(frame, x: w / 8, y: h / 2)))
        #expect(TestImages.isBlue(TestImages.pixel(frame, x: w * 7 / 8, y: h / 2)))
        let (before, _) = try await generator.image(at: CMTime(seconds: 1.0, preferredTimescale: 600))
        #expect(TestImages.isRed(TestImages.pixel(before, x: before.width / 2, y: before.height / 2)))
        let (after, _) = try await generator.image(at: CMTime(seconds: 3.5, preferredTimescale: 600))
        #expect(TestImages.isBlue(TestImages.pixel(after, x: after.width / 2, y: after.height / 2)))
    }
}

