import Foundation
import AVFoundation

/// Orquesta la generación completa: análisis de audio, vídeo y mezcla final.
public enum SlideshowRenderer {

    /// Genera el vídeo descrito en `spec` y devuelve la URL final.
    @discardableResult
    public static func generate(_ spec: SlideshowSpec, progress: ProgressHandler? = nil) async throws -> URL {
        do {
            return try await generateUnchecked(spec, progress: progress)
        } catch is CancellationError {
            // Las esperas de AVFoundation y `Task.sleep` lanzan su propio error al cancelar.
            TempFiles.remove(spec.output)
            throw CaobaError.cancelled
        } catch let error as CaobaError where error == .cancelled {
            TempFiles.remove(spec.output)
            throw error
        }
    }

    private static func generateUnchecked(_ spec: SlideshowSpec, progress: ProgressHandler?) async throws -> URL {
        guard spec.photos.count >= 1 else { throw CaobaError.noFiles }
        let timeline = SlideshowTimeline(durations: spec.photos.map(\.duration), transitions: spec.entryTransitions)
        let jobDir = try TempFiles.makeJobDirectory(prefix: "slideshow")
        defer { TempFiles.remove(jobDir) }

        // 1. Audio: duraciones y, si se pide, sonoridad de cada pista.
        var segments: [AudioSegment] = []
        if !spec.audio.tracks.isEmpty {
            progress?(JobProgress(phase: .analyzingAudio, fraction: nil))
            var durations: [Double] = []
            var gains: [Double]? = spec.audio.normalize ? [] : nil
            for track in spec.audio.tracks {
                try Task.checkCaobaCancellation()
                durations.append(try await AudioPlan.duration(of: track.url))
                if spec.audio.normalize {
                    let measured = try await LoudnessMeter.measure(url: track.url)
                    gains?.append(measured.map { LoudnessMeter.gain(from: $0, to: AudioOptions.targetLoudness) } ?? 1)
                }
            }
            segments = AudioPlan.build(tracks: spec.audio.tracks, durations: durations, gains: gains, timeline: timeline,
                                       fadeOutAtEnd: spec.audio.fadeOut, loopPlaylist: spec.audio.loopPlaylist,
                                       crossfade: spec.audio.crossfade, fadeOutDuration: spec.audio.fadeOutDuration)
        }

        // 2. Vídeo sin audio.
        let videoOnly = segments.isEmpty ? spec.output : jobDir.appendingPathComponent("video.mp4")
        try FileManager.default.createDirectory(at: spec.output.deletingLastPathComponent(), withIntermediateDirectories: true)
        let writer = VideoWriter(spec: spec, timeline: timeline)
        try await writer.write(to: videoOnly, progress: progress)

        // 3. Mezcla con el audio.
        if !segments.isEmpty {
            try Task.checkCaobaCancellation()
            try await AudioMuxer.mux(videoURL: videoOnly, segments: segments, totalDuration: timeline.totalDuration, output: spec.output,
                                     metadata: spec.metadata, progress: progress)
        }
        progress?(JobProgress(phase: .encodingVideo, fraction: 1))
        return spec.output
    }
}
