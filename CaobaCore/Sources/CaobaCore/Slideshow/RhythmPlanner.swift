import Foundation

/// Un golpe en el tiempo del vídeo, con el periodo de la pista que suena entonces.
public struct VideoBeat: Sendable, Equatable {
    public var time: Double
    public var period: Double
    public init(time: Double, period: Double) {
        self.time = time
        self.period = period
    }
}

/// Un elemento del timeline tal como lo ve el planificador.
public struct RhythmItem: Sendable, Equatable {
    /// Duración que no se toca (portada, créditos o duración propia del usuario).
    public var fixedDuration: Double?
    public var minimum: Double
    public var maximum: Double
    public init(fixedDuration: Double? = nil, minimum: Double = 1, maximum: Double = 15) {
        self.fixedDuration = fixedDuration
        self.minimum = minimum
        self.maximum = maximum
    }
}

/// Ajusta las duraciones de los elementos para que cada cambio caiga en un golpe.
public enum RhythmPlanner {
    /// Densidades disponibles: potencias de dos, que son las frases musicales.
    public static let densities = [1, 2, 4, 8, 16]

    /// Pasa los golpes de cada pista al tiempo del vídeo según los segmentos
    /// de la mezcla: cada segmento aporta sus golpes solo hasta que empieza el
    /// siguiente (en el crossfade manda la pista que entra).
    public static func videoBeats(segments: [AudioSegment], tracks: [String: BeatTrack]) -> [VideoBeat] {
        var result: [VideoBeat] = []
        for (n, segment) in segments.enumerated() {
            guard let track = tracks[segment.url.path], track.isReliable else { continue }
            let until = n + 1 < segments.count ? min(segment.end, segments[n + 1].start) : segment.end
            let trimEnd = segment.trimEnd ?? .infinity
            for beat in track.beats where beat >= segment.trimStart && beat < trimEnd {
                let time = segment.start + (beat - segment.trimStart)
                if time >= segment.start && time < until { result.append(VideoBeat(time: time, period: track.period)) }
            }
        }
        return result.sorted { $0.time < $1.time }
    }

    /// Golpes por foto que dejan la duración más cerca del objetivo con ese periodo.
    public static func automaticDensity(period: Double, target: Double) -> Int {
        guard period > 0 else { return 1 }
        return densities.min { abs(log(Double($0) * period / target)) < abs(log(Double($1) * period / target)) } ?? 1
    }

    /// Duraciones resultantes. Cada elemento empieza en `t`; su cambio visual
    /// (centro de la transición) debe caer sobre un golpe: `d = golpe - transición/2 - t`.
    /// Sin golpes a la vista (no suena música) se usa el objetivo.
    public static func plan(beats: [VideoBeat], items: [RhythmItem], target: Double, beatsPerCut: Int?, transition: Double) -> [Double] {
        var durations: [Double] = []
        var t = 0.0
        let half = transition / 2
        for item in items {
            if let fixed = item.fixedDuration {
                durations.append(fixed)
                t += fixed
                continue
            }
            // Golpe en el que "aterriza" este elemento y los que vienen después.
            let landing = t + half
            let upcoming = beats.filter { $0.time >= landing - 0.05 }
            guard let first = upcoming.first else {
                durations.append(target)
                t += target
                continue
            }
            let density = beatsPerCut ?? automaticDensity(period: first.period, target: target)
            var chosen: Double?
            var index = density
            // Primero el golpe que toca por densidad; si se sale de los límites, el más cercano que entre.
            if index < upcoming.count {
                let d = upcoming[index].time - half - t
                if d >= item.minimum && d <= item.maximum { chosen = d }
            }
            if chosen == nil {
                index = 1
                var candidates: [Double] = []
                while index < upcoming.count {
                    let d = upcoming[index].time - half - t
                    if d > item.maximum { break }
                    if d >= item.minimum { candidates.append(d) }
                    index += 1
                }
                chosen = candidates.min { abs($0 - Double(density) * first.period) < abs($1 - Double(density) * first.period) }
            }
            let d = chosen ?? min(item.maximum, max(item.minimum, target))
            durations.append(d)
            t += d
        }
        return durations
    }
}
