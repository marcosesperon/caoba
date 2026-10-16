import Foundation
import AVFoundation

/// Lee un fichero de audio como PCM flotante y entrega cada bloque por canales
/// (no entrelazado). Lo usan el medidor de sonoridad y el detector de golpes.
public enum AudioDecoder {
    public static func read(url: URL, block: (_ channels: [[Float]], _ sampleRate: Double) throws -> Void) async throws {
        let asset = AVURLAsset(url: url)
        guard let track = try await asset.loadTracks(withMediaType: .audio).first else { return }
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

        while let sample = output.copyNextSampleBuffer() {
            try Task.checkCaobaCancellation()
            guard let format = CMSampleBufferGetFormatDescription(sample),
                  let asbd = CMAudioFormatDescriptionGetStreamBasicDescription(format)?.pointee,
                  let blockBuffer = CMSampleBufferGetDataBuffer(sample) else { continue }
            let channels = Int(asbd.mChannelsPerFrame)
            var length = 0
            var pointer: UnsafeMutablePointer<Int8>?
            guard CMBlockBufferGetDataPointer(blockBuffer, atOffset: 0, lengthAtOffsetOut: nil, totalLengthOut: &length, dataPointerOut: &pointer) == noErr,
                  let pointer else { continue }
            let frames = length / (MemoryLayout<Float>.size * channels)
            let floats = UnsafeBufferPointer(start: UnsafeRawPointer(pointer).assumingMemoryBound(to: Float.self), count: frames * channels)
            var perChannel = Array(repeating: [Float](repeating: 0, count: frames), count: channels)
            for f in 0..<frames { for c in 0..<channels { perChannel[c][f] = floats[f * channels + c] } }
            try block(perChannel, asbd.mSampleRate)
        }
    }
}
