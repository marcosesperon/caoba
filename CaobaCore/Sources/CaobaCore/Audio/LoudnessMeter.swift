import Foundation
import AVFoundation

/// Medidor de sonoridad integrada según ITU-R BS.1770-4 / EBU R128:
/// filtro K (shelving alto + paso alto), bloques de 400 ms con 75 % de solape,
/// gating absoluto (-70 LUFS) y relativo (-10 LU). Devuelve LUFS.
public struct LoudnessMeter: Sendable {
    public var channelCount: Int
    public var sampleRate: Double
    private var filters: [KWeightingFilter]
    private var blockSize: Int
    private var hopSize: Int
    private var buffer: [[Float]]
    private var blockPowers: [Double] = []

    public init(channelCount: Int, sampleRate: Double) {
        self.channelCount = max(1, channelCount)
        self.sampleRate = sampleRate
        filters = (0..<max(1, channelCount)).map { _ in KWeightingFilter(sampleRate: sampleRate) }
        blockSize = Int(sampleRate * 0.4)
        hopSize = Int(sampleRate * 0.1)
        buffer = Array(repeating: [], count: max(1, channelCount))
    }

    /// Pesos por canal: L, R, C = 1; surround = 1,41 (no aplican a música estéreo).
    private func weight(forChannel c: Int) -> Double {
        (c == 3 || c == 4) && channelCount >= 5 ? 1.41 : 1.0
    }

    /// Añade muestras por canal (mismo número de muestras en cada canal).
    public mutating func process(channels: [[Float]]) {
        for c in 0..<min(channelCount, channels.count) {
            buffer[c].append(contentsOf: filters[c].process(channels[c]))
        }
        // Consumimos bloques completos de 400 ms avanzando de 100 en 100 ms.
        while buffer[0].count >= blockSize {
            var power = 0.0
            for c in 0..<channelCount {
                var sum = 0.0
                for i in 0..<blockSize { let v = Double(buffer[c][i]); sum += v * v }
                power += weight(forChannel: c) * sum / Double(blockSize)
            }
            blockPowers.append(power)
            for c in 0..<channelCount { buffer[c].removeFirst(min(hopSize, buffer[c].count)) }
        }
    }

    /// Sonoridad integrada en LUFS, o `nil` si no hay señal por encima del gate.
    public var integratedLoudness: Double? {
        let blocks = blockPowers.map { -0.691 + 10 * log10(max($0, 1e-20)) }
        let absolute = zip(blockPowers, blocks).filter { $0.1 > -70 }.map(\.0)
        guard !absolute.isEmpty else { return nil }
        let relativeThreshold = -0.691 + 10 * log10(absolute.reduce(0, +) / Double(absolute.count)) - 10
        let gated = zip(blockPowers, blocks).filter { $0.1 > -70 && $0.1 > relativeThreshold }.map(\.0)
        guard !gated.isEmpty else { return nil }
        return -0.691 + 10 * log10(gated.reduce(0, +) / Double(gated.count))
    }

    /// Ganancia lineal necesaria para llevar `measured` LUFS al objetivo.
    public static func gain(from measured: Double, to target: Double) -> Double {
        pow(10, (target - measured) / 20)
    }

    /// Mide un fichero de audio entero. Devuelve LUFS o `nil` si está en silencio.
    public static func measure(url: URL) async throws -> Double? {
        let asset = AVURLAsset(url: url)
        guard let track = try await asset.loadTracks(withMediaType: .audio).first else { return nil }
        let reader = try AVAssetReader(asset: asset)
        let settings: [String: Any] = [
            AVFormatIDKey: kAudioFormatLinearPCM,
            AVLinearPCMBitDepthKey: 32,
            AVLinearPCMIsFloatKey: true,
            AVLinearPCMIsNonInterleaved: false,
        ]
        let output = AVAssetReaderTrackOutput(track: track, outputSettings: settings)
        reader.add(output)
        guard reader.startReading() else { throw CaobaError.cannotReadImage(url.lastPathComponent) }

        var meter: LoudnessMeter?
        while let sample = output.copyNextSampleBuffer() {
            try Task.checkCaobaCancellation()
            guard let format = CMSampleBufferGetFormatDescription(sample),
                  let asbd = CMAudioFormatDescriptionGetStreamBasicDescription(format)?.pointee,
                  let block = CMSampleBufferGetDataBuffer(sample) else { continue }
            let channels = Int(asbd.mChannelsPerFrame)
            if meter == nil { meter = LoudnessMeter(channelCount: channels, sampleRate: asbd.mSampleRate) }
            var length = 0
            var pointer: UnsafeMutablePointer<Int8>?
            guard CMBlockBufferGetDataPointer(block, atOffset: 0, lengthAtOffsetOut: nil, totalLengthOut: &length, dataPointerOut: &pointer) == noErr,
                  let pointer else { continue }
            let frames = length / (MemoryLayout<Float>.size * channels)
            let floats = UnsafeBufferPointer(start: UnsafeRawPointer(pointer).assumingMemoryBound(to: Float.self), count: frames * channels)
            var perChannel = Array(repeating: [Float](repeating: 0, count: frames), count: channels)
            for f in 0..<frames { for c in 0..<channels { perChannel[c][f] = floats[f * channels + c] } }
            meter?.process(channels: perChannel)
        }
        return meter?.integratedLoudness
    }
}

/// Filtro K de BS.1770: shelving de alta frecuencia seguido de paso alto RLB.
/// Los coeficientes se calculan para cualquier frecuencia de muestreo a partir
/// de los parámetros analógicos de la norma (como hace libebur128).
public struct KWeightingFilter: Sendable {
    private var shelf: Biquad
    private var highPass: Biquad

    public init(sampleRate: Double) {
        // Etapa 1: shelving (+4 dB en agudos).
        let f0 = 1681.974450955533, g = 3.999843853973347, q = 0.7071752369554196
        let k = tan(.pi * f0 / sampleRate)
        let vh = pow(10, g / 20), vb = pow(vh, 0.4996667741545416)
        let a0 = 1 + k / q + k * k
        shelf = Biquad(
            b0: (vh + vb * k / q + k * k) / a0,
            b1: 2 * (k * k - vh) / a0,
            b2: (vh - vb * k / q + k * k) / a0,
            a1: 2 * (k * k - 1) / a0,
            a2: (1 - k / q + k * k) / a0
        )
        // Etapa 2: paso alto RLB (38 Hz).
        let f1 = 38.13547087602444, q1 = 0.5003270373238773
        let k1 = tan(.pi * f1 / sampleRate)
        let a01 = 1 + k1 / q1 + k1 * k1
        highPass = Biquad(
            b0: 1 / a01, b1: -2 / a01, b2: 1 / a01,
            a1: 2 * (k1 * k1 - 1) / a01,
            a2: (1 - k1 / q1 + k1 * k1) / a01
        )
    }

    public mutating func process(_ samples: [Float]) -> [Float] {
        highPass.process(shelf.process(samples))
    }
}

/// Biquad IIR en forma directa II transpuesta.
public struct Biquad: Sendable {
    var b0, b1, b2, a1, a2: Double
    private var z1 = 0.0, z2 = 0.0

    init(b0: Double, b1: Double, b2: Double, a1: Double, a2: Double) {
        self.b0 = b0; self.b1 = b1; self.b2 = b2; self.a1 = a1; self.a2 = a2
    }

    mutating func process(_ samples: [Float]) -> [Float] {
        var out = [Float](repeating: 0, count: samples.count)
        for (i, s) in samples.enumerated() {
            let x = Double(s)
            let y = b0 * x + z1
            z1 = b1 * x - a1 * y + z2
            z2 = b2 * x - a2 * y
            out[i] = Float(y)
        }
        return out
    }
}
