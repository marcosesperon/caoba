import Foundation
import AVFoundation

/// Une el vídeo ya codificado con la banda sonora: el vídeo se copia tal cual
/// (sin recodificar) y el audio se mezcla con `AVMutableAudioMix` y se
/// codifica a AAC.
public enum AudioMuxer {

    /// Composición de audio con todas las pistas en su sitio, en bucle hasta su final.
    static func makeComposition(segments: [AudioSegment], totalDuration: Double) async throws -> (AVMutableComposition, AVMutableAudioMix) {
        let composition = AVMutableComposition()
        var parameters: [AVMutableAudioMixInputParameters] = []
        let crossfade = AudioOptions.crossfadeSeconds

        for segment in segments {
            let asset = AVURLAsset(url: segment.url)
            guard let sourceTrack = try await asset.loadTracks(withMediaType: .audio).first else { continue }
            let assetDuration = CMTimeGetSeconds(try await asset.load(.duration))
            guard assetDuration > 0, let track = composition.addMutableTrack(withMediaType: .audio, preferredTrackID: kCMPersistentTrackID_Invalid) else { continue }

            // Repetimos el tramo recortado de la pista hasta cubrir el segmento.
            let trimStart = min(max(0, segment.trimStart), max(0, assetDuration - 0.5))
            let trimEnd = min(assetDuration, segment.trimEnd ?? assetDuration)
            let usable = max(0.5, trimEnd - trimStart)
            var cursor = segment.start
            while cursor < segment.end - 0.01 {
                let chunk = min(usable, segment.end - cursor)
                let range = CMTimeRange(start: CMTime(seconds: trimStart, preferredTimescale: 44100),
                                        duration: CMTime(seconds: chunk, preferredTimescale: 44100))
                try track.insertTimeRange(range, of: sourceTrack, at: CMTime(seconds: cursor, preferredTimescale: 44100))
                cursor += chunk
            }

            let p = AVMutableAudioMixInputParameters(track: track)
            let gain = Float(segment.gain)
            // Las rampas no pueden solaparse: si la pista es corta, las acortamos
            // y la de salida empieza siempre después de la de entrada.
            let fadeInDuration = segment.fadeIn ? min(crossfade, segment.duration / 2) : 0
            let fadeOutDuration = segment.fadeOut ? min(AudioOptions.fadeOutSeconds, segment.duration - fadeInDuration) : 0
            if fadeInDuration > 0 {
                p.setVolumeRamp(fromStartVolume: 0, toEndVolume: gain,
                                timeRange: CMTimeRange(start: CMTime(seconds: segment.start, preferredTimescale: 44100),
                                                       duration: CMTime(seconds: fadeInDuration, preferredTimescale: 44100)))
            } else {
                p.setVolume(gain, at: CMTime(seconds: segment.start, preferredTimescale: 44100))
            }
            if fadeOutDuration > 0 {
                let fadeStart = max(segment.end - fadeOutDuration, segment.start + fadeInDuration)
                p.setVolumeRamp(fromStartVolume: gain, toEndVolume: 0,
                                timeRange: CMTimeRange(start: CMTime(seconds: fadeStart, preferredTimescale: 44100),
                                                       duration: CMTime(seconds: segment.end - fadeStart, preferredTimescale: 44100)))
            }
            parameters.append(p)
        }
        let mix = AVMutableAudioMix()
        mix.inputParameters = parameters
        return (composition, mix)
    }

    /// Escribe `output` con el vídeo de `videoURL` y la mezcla de `segments`.
    public static func mux(videoURL: URL, segments: [AudioSegment], totalDuration: Double, output: URL, progress: ProgressHandler?) async throws {
        TempFiles.remove(output)
        let videoAsset = AVURLAsset(url: videoURL)
        guard let videoTrack = try await videoAsset.loadTracks(withMediaType: .video).first else {
            throw CaobaError.cannotReadImage(videoURL.lastPathComponent)
        }
        let (composition, mix) = try await makeComposition(segments: segments, totalDuration: totalDuration)
        let audioTracks = try await composition.loadTracks(withMediaType: .audio)

        // Lectores: vídeo tal cual, audio mezclado a PCM.
        let videoReader = try AVAssetReader(asset: videoAsset)
        let videoOutput = AVAssetReaderTrackOutput(track: videoTrack, outputSettings: nil)
        videoReader.add(videoOutput)

        let audioReader = try AVAssetReader(asset: composition)
        audioReader.timeRange = CMTimeRange(start: .zero, duration: CMTime(seconds: totalDuration, preferredTimescale: 44100))
        let audioOutput = AVAssetReaderAudioMixOutput(audioTracks: audioTracks, audioSettings: [
            AVFormatIDKey: kAudioFormatLinearPCM, AVLinearPCMBitDepthKey: 32, AVLinearPCMIsFloatKey: true,
            AVLinearPCMIsNonInterleaved: false, AVSampleRateKey: 48000, AVNumberOfChannelsKey: 2,
        ])
        audioOutput.audioMix = mix
        audioReader.add(audioOutput)

        // Escritor: vídeo en passthrough, audio AAC.
        let writer = try AVAssetWriter(outputURL: output, fileType: .mp4)
        let formatHint = try await videoTrack.load(.formatDescriptions).first
        let videoInput = AVAssetWriterInput(mediaType: .video, outputSettings: nil, sourceFormatHint: formatHint)
        videoInput.expectsMediaDataInRealTime = false
        let audioInput = AVAssetWriterInput(mediaType: .audio, outputSettings: [
            AVFormatIDKey: kAudioFormatMPEG4AAC, AVSampleRateKey: 48000, AVNumberOfChannelsKey: 2, AVEncoderBitRateKey: 192_000,
        ])
        audioInput.expectsMediaDataInRealTime = false
        writer.add(videoInput)
        writer.add(audioInput)
        writer.metadata = [Self.authorMetadata()]
        guard writer.startWriting(), videoReader.startReading(), audioReader.startReading() else {
            throw CaobaError.cannotWriteImage(writer.error?.localizedDescription ?? "mux start")
        }
        writer.startSession(atSourceTime: .zero)

        // Bombeamos cada entrada hasta agotar su lector. Los objetos de AVFoundation
        // no son Sendable; la bomba los encapsula y garantiza que solo se tocan
        // desde la cola de trabajo.
        let pump = SamplePump(video: (videoInput, videoOutput), audio: (audioInput, audioOutput), totalDuration: totalDuration, progress: progress)
        await pump.run()
        if Task.isCancelled {
            writer.cancelWriting()
            throw CaobaError.cancelled
        }
        await writer.finishWriting()
        guard writer.status == .completed else {
            throw CaobaError.cannotWriteImage(writer.error?.localizedDescription ?? "mux finish")
        }
    }

    static func authorMetadata() -> AVMetadataItem {
        let item = AVMutableMetadataItem()
        item.identifier = .commonIdentifierAuthor
        item.value = "CAOBA" as NSString
        return item
    }

    /// Copia muestras de los lectores a los escritores en una cola serie y avisa
    /// cuando las dos entradas han terminado.
    private final class SamplePump: @unchecked Sendable {
        private let videoInput: AVAssetWriterInput
        private let videoOutput: AVAssetReaderOutput
        private let audioInput: AVAssetWriterInput
        private let audioOutput: AVAssetReaderOutput
        private let totalDuration: Double
        private let progress: ProgressHandler?
        private let queue = DispatchQueue(label: "caoba.mux")
        private var remaining = 2
        private var continuation: CheckedContinuation<Void, Never>?

        init(video: (AVAssetWriterInput, AVAssetReaderOutput), audio: (AVAssetWriterInput, AVAssetReaderOutput), totalDuration: Double, progress: ProgressHandler?) {
            videoInput = video.0; videoOutput = video.1
            audioInput = audio.0; audioOutput = audio.1
            self.totalDuration = totalDuration
            self.progress = progress
        }

        func run() async {
            await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
                self.continuation = continuation
                videoInput.requestMediaDataWhenReady(on: queue) { [self] in pump(input: videoInput, output: videoOutput, reportProgress: false) }
                audioInput.requestMediaDataWhenReady(on: queue) { [self] in pump(input: audioInput, output: audioOutput, reportProgress: true) }
            }
        }

        private func pump(input: AVAssetWriterInput, output: AVAssetReaderOutput, reportProgress: Bool) {
            while input.isReadyForMoreMediaData {
                if Task.isCancelled { finish(input); return }
                guard let sample = output.copyNextSampleBuffer() else { finish(input); return }
                input.append(sample)
                if reportProgress {
                    let t = CMTimeGetSeconds(CMSampleBufferGetPresentationTimeStamp(sample))
                    progress?(JobProgress(phase: .mixingAudio, fraction: min(1, t / max(1, totalDuration))))
                }
            }
        }

        /// Marca la entrada como terminada; cuando acaban las dos, libera `run()`.
        private func finish(_ input: AVAssetWriterInput) {
            input.markAsFinished()
            remaining -= 1
            if remaining == 0 { continuation?.resume(); continuation = nil }
        }
    }
}
