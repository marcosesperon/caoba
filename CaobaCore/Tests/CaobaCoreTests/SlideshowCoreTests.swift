import Testing
import Foundation
import CoreGraphics
import AVFoundation
@testable import CaobaCore

@Suite("SlideshowTimeline")
struct SlideshowTimelineTests {
    @Test("Con transición, las fotos se solapan 1 s como el xfade antiguo")
    func withTransition() {
        let tl = SlideshowTimeline(durations: [4, 4, 4], transition: 1)
        #expect(tl.totalDuration == 13)
        #expect(tl.segments.map(\.start) == [0, 4, 8])
        #expect(tl.segments.map(\.end) == [5, 9, 13])
        #expect(tl.frame(at: 2)! == (0, nil, 0))
        let mid = tl.frame(at: 4.5)!
        #expect(mid.current == 0 && mid.next == 1 && abs(mid.progress - 0.5) < 1e-9)
        #expect(tl.frame(at: 5.5)! == (1, nil, 0))
        #expect(tl.frame(at: 12.9)!.current == 2)
        #expect(tl.startTime(ofPhoto: 2) == 8)
    }

    @Test("Sin transición no hay solapes")
    func withoutTransition() {
        let tl = SlideshowTimeline(durations: [2, 3], transition: 0)
        #expect(tl.totalDuration == 5)
        #expect(tl.frame(at: 1.9)! == (0, nil, 0))
        #expect(tl.frame(at: 2.0)! == (1, nil, 0))
    }
}

@Suite("KenBurns")
struct KenBurnsTests {
    @Test("Progreso con retardo, porcentaje de duración y easing")
    func progress() {
        #expect(KenBurns.progress(time: 0, duration: 4, durationPercent: 50, delayPercent: 0, easing: .linear) == 0)
        #expect(KenBurns.progress(time: 1, duration: 4, durationPercent: 50, delayPercent: 0, easing: .linear) == 0.5)
        #expect(KenBurns.progress(time: 3, duration: 4, durationPercent: 50, delayPercent: 0, easing: .linear) == 1)
        // Con 50 % de retardo el efecto empieza en 2 s y dura 1 s (50 % de los 2 s restantes).
        #expect(KenBurns.progress(time: 1.9, duration: 4, durationPercent: 50, delayPercent: 50, easing: .linear) == 0)
        #expect(KenBurns.progress(time: 2.5, duration: 4, durationPercent: 50, delayPercent: 50, easing: .linear) == 0.5)
        #expect(KenBurnsEasing.easeInOut.apply(0.5) == 0.5)
        #expect(KenBurnsEasing.easeIn.apply(0.5) == 0.25)
    }

    @Test("Zoom in encoge el recorte hacia el foco y se mantiene dentro de la imagen")
    func zoomIn() {
        let img = PixelSize(width: 4000, height: 3000), target = PixelSize(width: 1920, height: 1080)
        let start = KenBurns.cropRect(imageSize: img, targetSize: target, effect: .zoomIn, t: 0, intensity: .normal, focus: CGPoint(x: 0.5, y: 0.5))
        let end = KenBurns.cropRect(imageSize: img, targetSize: target, effect: .zoomIn, t: 1, intensity: .normal, focus: CGPoint(x: 0.5, y: 0.5))
        #expect(start.width > end.width && start.height > end.height)
        #expect(abs(start.width / start.height - 16.0 / 9.0) < 0.01)
        #expect(start.maxX <= 4000 && start.maxY <= 3000 && end.minX >= 0)
        // Centrado en el foco.
        #expect(abs(end.midX - 2000) <= 2 && abs(end.midY - 1500) <= 2)
    }

    @Test("Pan a la izquierda mueve el recorte de derecha a izquierda")
    func panLeft() {
        let img = PixelSize(width: 4000, height: 3000), target = PixelSize(width: 1920, height: 1080)
        let a = KenBurns.cropRect(imageSize: img, targetSize: target, effect: .panLeft, t: 0, intensity: .fast, focus: CGPoint(x: 0.5, y: 0.5))
        let b = KenBurns.cropRect(imageSize: img, targetSize: target, effect: .panLeft, t: 1, intensity: .fast, focus: CGPoint(x: 0.5, y: 0.5))
        #expect(a.minX > b.minX)
        #expect(a.size == b.size)
    }

    @Test("Efecto personalizado interpola foco y zoom")
    func custom() {
        let img = PixelSize(width: 2000, height: 2000), target = PixelSize(width: 1000, height: 1000)
        let points = KenBurnsPoints(startFocus: CGPoint(x: 0.25, y: 0.5), startZoom: 1, endFocus: CGPoint(x: 0.75, y: 0.5), endZoom: 2)
        let a = KenBurns.customCropRect(imageSize: img, targetSize: target, points: points, t: 0)
        let b = KenBurns.customCropRect(imageSize: img, targetSize: target, points: points, t: 1)
        #expect(a == CGRect(x: 0, y: 0, width: 2000, height: 2000))
        #expect(b == CGRect(x: 1000, y: 500, width: 1000, height: 1000))
    }

    @Test("Efecto sugerido según proporción")
    func suggested() {
        struct G: RandomNumberGenerator { mutating func next() -> UInt64 { 1 } }
        var g = G()
        #expect([.panLeft, .panRight].contains(KenBurns.suggestedEffect(imageAspect: 3, videoAspect: 1.78, generator: &g)))
        #expect([.panUp, .panDown].contains(KenBurns.suggestedEffect(imageAspect: 0.67, videoAspect: 1.78, generator: &g)))
        #expect([.zoomIn, .zoomOut].contains(KenBurns.suggestedEffect(imageAspect: 1.78, videoAspect: 1.78, generator: &g)))
    }
}

@Suite("LoudnessMeter")
struct LoudnessMeterTests {
    /// Senoide estéreo de 997 Hz a `dbfs` dB, `seconds` segundos.
    private func sine(dbfs: Double, seconds: Double, sampleRate: Double = 48000) -> [[Float]] {
        let amplitude = Float(pow(10, dbfs / 20))
        let n = Int(seconds * sampleRate)
        let samples = (0..<n).map { amplitude * Float(sin(2 * .pi * 997 * Double($0) / sampleRate)) }
        return [samples, samples]
    }

    @Test("EBU Tech 3341: senoide estéreo de 997 Hz a -23 dBFS mide -23 LUFS")
    func referenceTone() {
        var meter = LoudnessMeter(channelCount: 2, sampleRate: 48000)
        meter.process(channels: sine(dbfs: -23, seconds: 5))
        let lufs = meter.integratedLoudness!
        #expect(abs(lufs + 23) < 0.1)
        #expect(abs(LoudnessMeter.gain(from: lufs, to: -16) - pow(10, 7.0 / 20)) < 0.02)
    }

    @Test("A 44,1 kHz el resultado es el mismo y el silencio no mide")
    func otherRateAndSilence() {
        var meter = LoudnessMeter(channelCount: 2, sampleRate: 44100)
        meter.process(channels: sine(dbfs: -30, seconds: 4, sampleRate: 44100))
        #expect(abs(meter.integratedLoudness! + 30) < 0.15)
        var silent = LoudnessMeter(channelCount: 2, sampleRate: 48000)
        silent.process(channels: [[Float](repeating: 0, count: 48000), [Float](repeating: 0, count: 48000)])
        #expect(silent.integratedLoudness == nil)
    }

    @Test("Medir un fichero de audio escrito con AVAudioFile")
    func measureFile() async throws {
        let folder = try TestImages.makeTempFolder()
        let url = folder.appendingPathComponent("tone.m4a")
        try TestAudio.writeTone(to: url, dbfs: -20, seconds: 3)
        let lufs = try await LoudnessMeter.measure(url: url)
        #expect(lufs != nil && abs(lufs! + 20) < 0.5)
    }
}

/// Audio sintético para tests.
enum TestAudio {
    /// Escribe una senoide estéreo de 997 Hz en AAC (.m4a) o WAV según extensión.
    static func writeTone(to url: URL, dbfs: Double, seconds: Double, sampleRate: Double = 48000) throws {
        let format = AVAudioFormat(standardFormatWithSampleRate: sampleRate, channels: 2)!
        let frames = AVAudioFrameCount(seconds * sampleRate)
        let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frames)!
        buffer.frameLength = frames
        let amplitude = Float(pow(10, dbfs / 20))
        for i in 0..<Int(frames) {
            let v = amplitude * Float(sin(2 * .pi * 997 * Double(i) / sampleRate))
            buffer.floatChannelData![0][i] = v
            buffer.floatChannelData![1][i] = v
        }
        let settings: [String: Any] = url.pathExtension == "wav"
            ? [AVFormatIDKey: kAudioFormatLinearPCM, AVSampleRateKey: sampleRate, AVNumberOfChannelsKey: 2, AVLinearPCMBitDepthKey: 16]
            : [AVFormatIDKey: kAudioFormatMPEG4AAC, AVSampleRateKey: sampleRate, AVNumberOfChannelsKey: 2, AVEncoderBitRateKey: 192_000]
        let file = try AVAudioFile(forWriting: url, settings: settings)
        try file.write(from: buffer)
    }
}
