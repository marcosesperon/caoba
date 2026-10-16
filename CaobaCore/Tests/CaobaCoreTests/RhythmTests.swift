import Testing
import Foundation
@testable import CaobaCore

@Suite("BeatDetector")
struct BeatDetectorTests {
    /// Pista de clics sintética: un golpe corto cada `period` segundos.
    static func clicks(tempo: Double, seconds: Double, sampleRate: Double = 48_000, offset: Double = 0.25) -> [Float] {
        let count = Int(seconds * sampleRate)
        var mono = [Float](repeating: 0, count: count)
        let period = 60 / tempo
        var t = offset
        while t < seconds {
            let start = Int(t * sampleRate)
            for i in 0..<Int(0.02 * sampleRate) where start + i < count {
                mono[start + i] = Float(0.8 * exp(-Double(i) / (0.004 * sampleRate)) * sin(Double(i) * 0.3))
            }
            t += period
        }
        return mono
    }

    @Test("Una pista de clics a 120 ppm da 120 ppm y golpes cada medio segundo")
    func clickTrack() {
        let mono = Self.clicks(tempo: 120, seconds: 20)
        let track = BeatDetector.analyze(mono: mono, sampleRate: 48_000)
        #expect(abs(track.tempo - 120) < 2)
        #expect(track.isReliable)
        #expect(track.beats.count >= 36)
        // Cada golpe detectado cae cerca de un clic real (0,25 + k·0,5).
        for beat in track.beats.prefix(30) {
            let k = ((beat - 0.25) / 0.5).rounded()
            #expect(abs(beat - (0.25 + k * 0.5)) < 0.03)
        }
    }

    @Test("A 92 ppm el tempo también se encuentra")
    func slowTrack() {
        let track = BeatDetector.analyze(mono: Self.clicks(tempo: 92, seconds: 30), sampleRate: 48_000)
        #expect(abs(track.tempo - 92) < 2)
    }

    @Test("El ruido sin ritmo no se considera fiable")
    func noise() {
        var generator = SystemRandomNumberGenerator()
        let mono = (0..<(48_000 * 10)).map { _ in Float.random(in: -0.3...0.3, using: &generator) }
        let track = BeatDetector.analyze(mono: mono, sampleRate: 48_000)
        #expect(!track.isReliable)
    }
}

@Suite("RhythmPlanner")
struct RhythmPlannerTests {
    func beats(period: Double, count: Int, from: Double = 0) -> [VideoBeat] {
        (0..<count).map { VideoBeat(time: from + Double($0) * period, period: period) }
    }

    @Test("Los cambios caen en golpes y la densidad automática se acerca a los segundos por foto")
    func cutsOnBeats() {
        let grid = beats(period: 0.5, count: 200)   // 120 ppm
        let items = Array(repeating: RhythmItem(), count: 6)
        let durations = RhythmPlanner.plan(beats: grid, items: items, target: 4, beatsPerCut: nil, transition: 1)
        #expect(durations.count == 6)
        var t = 0.0
        for d in durations {
            t += d
            let cut = t + 0.5
            let nearest = grid.min { abs($0.time - cut) < abs($1.time - cut) }!
            #expect(abs(nearest.time - cut) < 0.001)
            #expect(d >= 1 && d <= 15)
        }
        #expect(RhythmPlanner.automaticDensity(period: 0.5, target: 4) == 8)
        #expect(RhythmPlanner.automaticDensity(period: 0.65, target: 4) == 8)
        #expect(RhythmPlanner.automaticDensity(period: 1.0, target: 4) == 4)
    }

    @Test("Las duraciones fijas se respetan y lo siguiente se vuelve a sincronizar")
    func fixedRespected() {
        let grid = beats(period: 0.5, count: 200)
        let items = [RhythmItem(fixedDuration: 3.3), RhythmItem(), RhythmItem(fixedDuration: 2.2), RhythmItem()]
        let durations = RhythmPlanner.plan(beats: grid, items: items, target: 4, beatsPerCut: 4, transition: 0)
        #expect(durations[0] == 3.3)
        #expect(durations[2] == 2.2)
        // Tras 3,3 s el siguiente corte cae en un golpe.
        let cut = 3.3 + durations[1]
        #expect(abs(cut - (cut / 0.5).rounded() * 0.5) < 0.001)
    }

    @Test("Sin música se usa el objetivo y los límites acotan")
    func noBeatsAndLimits() {
        let none = RhythmPlanner.plan(beats: [], items: [RhythmItem(), RhythmItem()], target: 4, beatsPerCut: nil, transition: 1)
        #expect(none == [4, 4])
        // Golpes muy separados: 16 golpes a 1 s se salen del máximo; se elige el que entra.
        let slow = beats(period: 1.0, count: 100)
        let d = RhythmPlanner.plan(beats: slow, items: [RhythmItem(maximum: 6)], target: 4, beatsPerCut: 16, transition: 0)
        #expect(d[0] <= 6 && d[0] >= 1)
    }

    @Test("Los golpes de cada pista pasan al vídeo según su segmento; en el crossfade manda la que entra")
    func videoBeats() {
        let a = URL(fileURLWithPath: "/tmp/a.mp3"), b = URL(fileURLWithPath: "/tmp/b.mp3")
        let tracks = [
            a.path: BeatTrack(tempo: 120, beats: (0..<40).map { Double($0) * 0.5 }, confidence: 1),
            b.path: BeatTrack(tempo: 60, beats: (0..<40).map { Double($0) * 1.0 }, confidence: 1),
        ]
        let segments = [
            AudioSegment(url: a, start: 0, end: 13, gain: 1, fadeIn: false, fadeOut: true, trimStart: 2, trimEnd: nil),
            AudioSegment(url: b, start: 10, end: 30, gain: 1, fadeIn: true, fadeOut: false, trimStart: 0, trimEnd: nil),
        ]
        let beats = RhythmPlanner.videoBeats(segments: segments, tracks: tracks)
        // De la primera: golpes desde el recorte (2 s) hasta que entra la segunda (10 s) → 0, 0.5, … 9.5.
        #expect(beats.filter { $0.period == 0.5 }.count == 20)
        #expect(beats.filter { $0.period == 0.5 }.allSatisfy { $0.time < 10 })
        // De la segunda: desde 10 s, cada segundo, hasta 30.
        #expect(beats.filter { $0.period == 1.0 }.first?.time == 10)
        #expect(beats.filter { $0.period == 1.0 }.allSatisfy { $0.time >= 10 && $0.time < 30 })
    }
}
