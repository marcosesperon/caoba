import Testing
import Foundation
@testable import CaobaCore

@Suite("Cuadrar cruces con el ritmo")
struct CrossfadeAlignerTests {
    /// Golpes regulares de `start` a `end` con ese tempo.
    func beats(tempo: Double, from start: Double = 0, to end: Double = 200) -> BeatTrack {
        let period = 60 / tempo
        return BeatTrack(tempo: tempo, beats: Array(stride(from: start, to: end, by: period)), confidence: 0.9)
    }

    /// Cruce de prueba: la que sale empieza en 0 (Desde 0) y la que entra en `start` con su Desde.
    func crossfade(start: Double, trimStart: Double = 0, trimEnd: Double = 200, fade: Double = 4,
                   out: BeatTrack?, inc: BeatTrack?, outTrimStart: Double = 0, usable: Double = 200) -> CrossfadeAligner.Crossfade {
        let outgoing = AudioSegment(url: URL(fileURLWithPath: "/a.mp3"), start: 0, end: start + fade, gain: 1,
                                    fadeInSeconds: 0, fadeOutSeconds: fade, trimStart: outTrimStart, trimEnd: nil)
        return .init(outgoing: outgoing, outgoingUsable: usable, outgoingBeats: out,
                     incomingStart: start, incomingTrimStart: trimStart, incomingTrimEnd: trimEnd, incomingFade: fade, incomingBeats: inc)
    }

    @Test("Ya cuadrado: no se mueve nada")
    func alreadyAligned() {
        let r = CrossfadeAligner.align(crossfade(start: 30, out: beats(tempo: 120), inc: beats(tempo: 120)))
        #expect(r == .aligned(start: 30, trimStart: 0))
    }

    @Test("Desfasado: el inicio va al golpe más cercano y el Desde a un golpe de la que entra")
    func shifts() {
        // Golpes cada 0,5 s. Empieza en 30,2 (golpe más cercano: 30,0) con Desde 10,15 (golpe: 10,0).
        let r = CrossfadeAligner.align(crossfade(start: 30.2, trimStart: 10.15, out: beats(tempo: 120), inc: beats(tempo: 120)))
        guard case .aligned(let start, let trim) = r else { Issue.record("no cuadra: \(r)"); return }
        #expect(abs(start - 30) < 0.001 && abs(trim - 10) < 0.001)
    }

    @Test("Nunca más de medio golpe")
    func halfBeatAtMost() {
        let r = CrossfadeAligner.align(crossfade(start: 30.24, trimStart: 10.24, out: beats(tempo: 120), inc: beats(tempo: 120)))
        guard case .aligned(let start, let trim) = r else { Issue.record("no cuadra: \(r)"); return }
        #expect(abs(start - 30.24) <= 0.25 && abs(trim - 10.24) <= 0.25)
    }

    @Test("El doble de tempo es compatible; tempos muy distintos no")
    func tempos() {
        #expect(CrossfadeAligner.tempoCompatible(70, 140))
        #expect(CrossfadeAligner.tempoCompatible(120, 125))
        #expect(!CrossfadeAligner.tempoCompatible(92, 128))
        let r = CrossfadeAligner.align(crossfade(start: 30, out: beats(tempo: 92), inc: beats(tempo: 128)))
        #expect(r == .tempoMismatch(outgoing: 92, incoming: 128))
        #expect(CrossfadeAligner.align(crossfade(start: 30.1, out: beats(tempo: 70), inc: beats(tempo: 140))) != .noRhythm)
    }

    @Test("Sin ritmo claro, corte seco o sin sitio antes del Hasta: no se cuadra")
    func skipped() {
        let weak = BeatTrack(tempo: 120, beats: Array(stride(from: 0.0, to: 100, by: 0.5)), confidence: 0.01)
        #expect(CrossfadeAligner.align(crossfade(start: 30, out: weak, inc: beats(tempo: 120))) == .noRhythm)
        #expect(CrossfadeAligner.align(crossfade(start: 30, out: beats(tempo: 120), inc: nil)) == .noRhythm)
        #expect(CrossfadeAligner.align(crossfade(start: 30, fade: 0, out: beats(tempo: 120), inc: beats(tempo: 120))) == .cut)
        #expect(CrossfadeAligner.align(crossfade(start: 30, trimStart: 9.9, trimEnd: 10.5, out: beats(tempo: 120), inc: beats(tempo: 120))) == .tooShort)
    }

    @Test("La que sale repite su tramo: los golpes se buscan en la vuelta que toca")
    func repeatedOutgoing() {
        // Tramo de 10,25 s (Desde 0): la segunda vuelta empieza en 10,25, así que sus golpes caen en 10,25 + 0,5·k.
        let r = CrossfadeAligner.align(crossfade(start: 15.4, out: beats(tempo: 120), inc: beats(tempo: 120), usable: 10.25))
        guard case .aligned(let start, _) = r else { Issue.record("no cuadra: \(r)"); return }
        #expect(abs(start - 15.25) < 0.001)
    }
}
