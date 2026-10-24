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
    /// Duración de referencia propia (p. ej. un collage según sus fotos); `nil` = la general.
    public var target: Double?
    /// Fotos que muestra: con «golpes por foto» fijo, los golpes se multiplican por ellas.
    public var photos: Int
    public init(fixedDuration: Double? = nil, minimum: Double = 1, maximum: Double = 15, target: Double? = nil, photos: Int = 1) {
        self.fixedDuration = fixedDuration
        self.minimum = minimum
        self.maximum = maximum
        self.target = target
        self.photos = max(1, photos)
    }
}

/// Ajusta las duraciones de los elementos para que cada cambio caiga en un golpe.
public enum RhythmPlanner {
    /// Densidades disponibles: potencias de dos, que son las frases musicales.
    public static let densities = [1, 2, 4, 8, 16]
    /// En automático también vale 32, para collages largos (muchas fotos o «Mantener» alto).
    static let automaticDensities = densities + [32]

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
        return automaticDensities.min { abs(log(Double($0) * period / target)) < abs(log(Double($1) * period / target)) } ?? 1
    }

    /// Duraciones resultantes. Cada elemento empieza en `t`; su cambio visual
    /// (centro de la transición) debe caer sobre un golpe: `d = golpe - transición/2 - t`.
    /// Sin golpes a la vista (no suena música) se usa el objetivo.
    public static func plan(beats: [VideoBeat], items: [RhythmItem], target: Double, beatsPerCut: Int?, transition: Double) -> [Double] {
        plan(beats: beats, items: items, target: target, beatsPerCut: beatsPerCut, entryTransitions: Array(repeating: transition, count: items.count))
    }

    /// Con la transición de entrada de cada elemento: el cambio visual entre el
    /// elemento i y el i+1 está en el centro de la transición del i+1.
    public static func plan(beats: [VideoBeat], items: [RhythmItem], target: Double, beatsPerCut: Int?, entryTransitions: [Double]) -> [Double] {
        var durations: [Double] = []
        var t = 0.0
        for (index, item) in items.enumerated() {
            let half = (index + 1 < entryTransitions.count ? entryTransitions[index + 1] : 0) / 2
            if let fixed = item.fixedDuration {
                durations.append(fixed)
                t += fixed
                continue
            }
            // Golpe en el que "aterriza" este elemento y los que vienen después.
            let landing = t + half
            let upcoming = beats.filter { $0.time >= landing - 0.05 }
            // Cada elemento puede tener su referencia (un collage, según sus fotos).
            let reference = item.target ?? target
            guard let first = upcoming.first else {
                let d = min(item.maximum, max(item.minimum, reference))
                durations.append(d)
                t += d
                continue
            }
            // Fijo: golpes por cada foto que muestra. Automático: los que más se acercan a su referencia.
            let density = beatsPerCut.map { $0 * item.photos } ?? automaticDensity(period: first.period, target: reference)
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
                // Si el que toca no cabe, el que más se acerque: a los golpes pedidos (fijo) o a su referencia (automático).
                let aim = beatsPerCut != nil ? Double(density) * first.period : reference
                chosen = candidates.min { abs($0 - aim) < abs($1 - aim) }
            }
            let d = chosen ?? min(item.maximum, max(item.minimum, reference))
            durations.append(d)
            t += d
        }
        return durations
    }
}
