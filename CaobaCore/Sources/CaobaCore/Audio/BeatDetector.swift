import Foundation

/// Ritmo de una pista: tempo, instantes de los golpes (segundos desde el inicio
/// del fichero) y cuánto fiarse del resultado.
public struct BeatTrack: Sendable, Equatable {
    public var tempo: Double
    public var beats: [Double]
    /// 0-1: fuerza del tempo encontrado frente al resto de candidatos.
    public var confidence: Double

    public init(tempo: Double, beats: [Double], confidence: Double) {
        self.tempo = tempo
        self.beats = beats
        self.confidence = confidence
    }

    /// Segundos entre golpes.
    public var period: Double { tempo > 0 ? 60 / tempo : 0 }
    /// Hay ritmo claro si el tempo destaca y hay golpes suficientes.
    public var isReliable: Bool { confidence >= BeatDetector.minimumConfidence && beats.count >= 8 }
}

/// Detección de golpes sin dependencias: envolvente de ataques por energía
/// (banda completa y graves), tempo por autocorrelación y seguimiento de la
/// rejilla de golpes pegándose a los ataques reales.
public enum BeatDetector {
    public static let minimumConfidence = 0.12
    /// Tamaño del tramo de análisis en muestras (≈10,7 ms a 48 kHz).
    static let hop = 512
    static let minTempo = 60.0
    static let maxTempo = 200.0

    public static func analyze(url: URL) async throws -> BeatTrack {
        var mono: [Float] = []
        var rate = 48_000.0
        try await AudioDecoder.read(url: url) { channels, sampleRate in
            rate = sampleRate
            let frames = channels.first?.count ?? 0
            var mix = [Float](repeating: 0, count: frames)
            for channel in channels { for i in 0..<frames { mix[i] += channel[i] } }
            let scale = 1 / Float(max(1, channels.count))
            for i in 0..<frames { mix[i] *= scale }
            mono.append(contentsOf: mix)
        }
        return analyze(mono: mono, sampleRate: rate)
    }

    /// Envolvente de ataques por tramo: subida de energía (logarítmica) en banda
    /// completa y, con más peso, en los graves, donde suelen estar bombo y bajo.
    static func onsetEnvelope(mono: [Float], sampleRate: Double) -> [Double] {
        guard mono.count >= hop * 2 else { return [] }
        var low = Biquad.lowPass(cutoff: 150, sampleRate: sampleRate)
        let lows = low.process(mono)
        let frames = mono.count / hop
        var energyFull = [Double](repeating: 0, count: frames)
        var energyLow = [Double](repeating: 0, count: frames)
        for f in 0..<frames {
            var sumFull = 0.0, sumLow = 0.0
            let base = f * hop
            for i in base..<(base + hop) {
                sumFull += Double(mono[i] * mono[i])
                sumLow += Double(lows[i] * lows[i])
            }
            energyFull[f] = log(sumFull / Double(hop) + 1e-9)
            energyLow[f] = log(sumLow / Double(hop) + 1e-9)
        }
        var onset = [Double](repeating: 0, count: frames)
        for f in 1..<frames {
            // Subida respecto a la media de los tramos anteriores: ignora el sostenido y ve el ataque.
            let back = max(0, f - 4)
            let refFull = energyFull[back..<f].reduce(0, +) / Double(f - back)
            let refLow = energyLow[back..<f].reduce(0, +) / Double(f - back)
            onset[f] = 0.5 * max(0, energyFull[f] - refFull) + max(0, energyLow[f] - refLow)
        }
        return onset
    }

    static func analyze(mono: [Float], sampleRate: Double) -> BeatTrack {
        let onset = onsetEnvelope(mono: mono, sampleRate: sampleRate)
        let hopSeconds = Double(hop) / sampleRate
        guard onset.count > Int(2 / hopSeconds) else { return BeatTrack(tempo: 0, beats: [], confidence: 0) }

        // Autocorrelación normalizada de la envolvente (sin media) entre 60 y 200 ppm.
        let mean = onset.reduce(0, +) / Double(onset.count)
        let centered = onset.map { $0 - mean }
        let r0 = centered.reduce(0) { $0 + $1 * $1 }
        guard r0 > 0 else { return BeatTrack(tempo: 0, beats: [], confidence: 0) }
        let minLag = Int((60 / maxTempo) / hopSeconds)
        let maxLag = Int((60 / minTempo) / hopSeconds)
        var acf: [Int: Double] = [:]
        for lag in minLag...maxLag {
            var sum = 0.0
            for i in lag..<centered.count { sum += centered[i] * centered[i - lag] }
            acf[lag] = sum / r0
        }
        // Preferencia suave por tempos alrededor de 120 ppm para no saltar de octava.
        func weight(_ lag: Int) -> Double {
            let tempo = 60 / (Double(lag) * hopSeconds)
            let x = log2(tempo / 120)
            return exp(-0.5 * x * x / 0.8)
        }
        guard let best = acf.max(by: { $0.value * weight($0.key) < $1.value * weight($1.key) }) else {
            return BeatTrack(tempo: 0, beats: [], confidence: 0)
        }
        let values = acf.values.sorted()
        let median = values[values.count / 2]
        let confidence = max(0, min(1, (best.value - median) / max(1e-6, 1 - median)))

        // Afinado del periodo: parábola entre los tres puntos alrededor del máximo.
        var period = Double(best.key) * hopSeconds
        if let l = acf[best.key - 1], let r = acf[best.key + 1] {
            let denominator = l - 2 * best.value + r
            if abs(denominator) > 1e-9 { period = (Double(best.key) + 0.5 * (l - r) / denominator) * hopSeconds }
        }

        // Fase: desplazamiento con más energía de ataque sobre la rejilla.
        let lagFrames = Double(period / hopSeconds)
        var bestOffset = 0.0
        var bestEnergy = -1.0
        var offset = 0.0
        while offset < lagFrames {
            var energy = 0.0
            var position = offset
            while Int(position) < onset.count { energy += onset[Int(position)]; position += lagFrames }
            if energy > bestEnergy { bestEnergy = energy; bestOffset = offset }
            offset += 1
        }

        // Seguimiento: cada golpe se pega al ataque más fuerte cerca de donde toca,
        // y el periodo se adapta despacio por si el tempo se mueve un poco.
        var beats: [Double] = []
        var current = bestOffset * hopSeconds
        var liveGap = period
        let total = Double(onset.count) * hopSeconds
        let tolerance = 0.12
        while current < total {
            let window = (max(0, Int((current - liveGap * tolerance) / hopSeconds))...min(onset.count - 1, Int((current + liveGap * tolerance) / hopSeconds)))
            var peak = current
            var peakValue = -1.0
            for f in window where onset[f] > peakValue { peakValue = onset[f]; peak = Double(f) * hopSeconds }
            let snapped = peakValue > mean ? peak : current
            if let last = beats.last { liveGap = 0.9 * liveGap + 0.1 * (snapped - last) }
            beats.append(snapped)
            current = snapped + liveGap
        }
        return BeatTrack(tempo: 60 / period, beats: beats, confidence: confidence)
    }
}
