import Foundation

/// Cuadra un cruce entre dos pistas con el ritmo, como haría un DJ: que el cruce
/// empiece en un golpe de la canción que sale y que, a partir de ahí, los golpes de
/// las dos caigan juntos. Solo calcula; quien llama aplica el resultado a la pista.
public enum CrossfadeAligner {
    /// Diferencia de tempo que se tolera (6 %), contando como compatibles el doble y la mitad.
    public static let tempoTolerance = 0.06

    /// Lo que sale y lo que entra en un cruce.
    public struct Crossfade: Sendable {
        /// Tramo de la pista que sale (con su inicio, recorte y cruce de salida).
        public var outgoing: AudioSegment
        /// Segundos de la canción que sale que se repiten (su Hasta − Desde).
        public var outgoingUsable: Double
        public var outgoingBeats: BeatTrack?
        /// Pista que entra: dónde empieza en el vídeo, su Desde/Hasta y su cruce de entrada.
        public var incomingStart: Double
        public var incomingTrimStart: Double
        public var incomingTrimEnd: Double
        public var incomingFade: Double
        public var incomingBeats: BeatTrack?

        public init(outgoing: AudioSegment, outgoingUsable: Double, outgoingBeats: BeatTrack?,
                    incomingStart: Double, incomingTrimStart: Double, incomingTrimEnd: Double, incomingFade: Double, incomingBeats: BeatTrack?) {
            self.outgoing = outgoing; self.outgoingUsable = outgoingUsable; self.outgoingBeats = outgoingBeats
            self.incomingStart = incomingStart; self.incomingTrimStart = incomingTrimStart; self.incomingTrimEnd = incomingTrimEnd
            self.incomingFade = incomingFade; self.incomingBeats = incomingBeats
        }
    }

    public enum Result: Sendable, Equatable {
        /// Nuevo inicio en el vídeo y nuevo Desde de la pista que entra.
        case aligned(start: Double, trimStart: Double)
        case noRhythm
        case tempoMismatch(outgoing: Double, incoming: Double)
        case cut
        /// Al cuadrar, no quedaría al menos 1 s de canción antes del Hasta.
        case tooShort
    }

    public static func align(_ c: Crossfade) -> Result {
        guard c.incomingFade > 0 else { return .cut }
        guard let out = c.outgoingBeats, let inc = c.incomingBeats, out.isReliable, inc.isReliable else { return .noRhythm }
        guard tempoCompatible(out.tempo, inc.tempo) else { return .tempoMismatch(outgoing: out.tempo, incoming: inc.tempo) }

        // 1. El cruce empieza en el golpe de la que sale más cercano (como mucho medio golpe).
        guard let start = nearestOutgoingBeat(to: c.incomingStart, in: c) else { return .noRhythm }

        // 2. La que entra arranca en uno de sus golpes: su Desde va al golpe más cercano.
        //    Así su primer golpe cae justo en el golpe de la que sale y siguen a la par.
        guard let trim = nearest(to: c.incomingTrimStart, in: inc.beats, maxDistance: inc.period / 2) else { return .noRhythm }
        guard trim <= c.incomingTrimEnd - 1 else { return .tooShort }
        return .aligned(start: max(0, start), trimStart: max(0, trim))
    }

    /// Tempos compatibles: iguales, o uno el doble del otro, con la tolerancia.
    public static func tempoCompatible(_ a: Double, _ b: Double) -> Bool {
        guard a > 0, b > 0 else { return false }
        return [0.5, 1, 2].contains { abs(b / (a * $0) - 1) <= tempoTolerance }
    }

    /// Golpe de la canción que sale más cercano al instante `t` del vídeo. La canción
    /// repite su tramo Desde → Hasta, así que se busca en la vuelta que toque.
    static func nearestOutgoingBeat(to t: Double, in c: Crossfade) -> Double? {
        guard let out = c.outgoingBeats, c.outgoingUsable > 0 else { return nil }
        let trimStart = c.outgoing.trimStart
        let elapsed = max(0, t - c.outgoing.start)
        let lap = floor(elapsed / c.outgoingUsable)
        let lapStart = c.outgoing.start + lap * c.outgoingUsable
        // Golpes de esta vuelta y de las vecinas, en tiempo del vídeo.
        let inRange = out.beats.filter { $0 >= trimStart && $0 < trimStart + c.outgoingUsable }
        var candidates: [Double] = []
        for offset in [-1.0, 0, 1] {
            let base = lapStart + offset * c.outgoingUsable
            candidates += inRange.map { base + ($0 - trimStart) }
        }
        return nearest(to: t, in: candidates.filter { $0 >= c.outgoing.start }, maxDistance: out.period / 2)
    }

    /// Valor de la lista más cercano a `t`, si está a `maxDistance` o menos (con un pelín de margen).
    static func nearest(to t: Double, in values: [Double], maxDistance: Double) -> Double? {
        guard let best = values.min(by: { abs($0 - t) < abs($1 - t) }), abs(best - t) <= maxDistance + 0.001 else { return nil }
        return best
    }
}
