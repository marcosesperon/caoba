import Foundation
import AVFoundation

/// Dónde empieza y acaba cada pista en el vídeo, con sus fundidos y ganancia.
/// Es la traducción del encadenado `acrossfade` + `afade` de la app antigua.
public struct AudioSegment: Sendable, Equatable {
    public var url: URL
    public var start: Double
    public var end: Double
    /// Ganancia lineal (1 = sin cambio) por normalización.
    public var gain: Double
    public var fadeIn: Bool
    public var fadeOut: Bool
    /// Tramo de la canción que se usa (en segundos de la canción).
    public var trimStart: Double = 0
    public var trimEnd: Double? = nil

    public var duration: Double { max(0, end - start) }
}

public enum AudioPlan {

    /// Duración real de un fichero de audio.
    public static func duration(of url: URL) async throws -> Double {
        let asset = AVURLAsset(url: url)
        let duration = try await asset.load(.duration)
        return CMTimeGetSeconds(duration)
    }

    /// Calcula los segmentos. `durations` son las duraciones reales de cada pista
    /// y `gains` las ganancias (o `nil`, sin normalizar). Con `loopPlaylist`, si el
    /// vídeo dura más que la lista, se vuelve a empezar por la primera pista.
    public static func build(tracks: [AudioTrack], durations: [Double], gains: [Double]?, timeline: SlideshowTimeline,
                             fadeOutAtEnd: Bool, loopPlaylist: Bool = false) -> [AudioSegment] {
        guard !tracks.isEmpty, tracks.count == durations.count else { return [] }
        let crossfade = AudioOptions.crossfadeSeconds
        let total = timeline.totalDuration

        // Primera pasada por la lista: inicio automático o en una foto.
        var items: [(index: Int, start: Double)] = []
        var tail = 0.0
        for (i, track) in tracks.enumerated() {
            let start: Double
            switch track.startMode {
            case .atPhoto(let index): start = timeline.startTime(ofPhoto: index)
            case .atTime(let t): start = max(0, t)
            case .automatic: start = i == 0 ? 0 : max(0, tail - crossfade)
            }
            items.append((i, start))
            tail = start + track.effectiveDuration(assetDuration: durations[i])
        }

        // Si sobra vídeo y hay que repetir la lista, seguimos encadenando en
        // automático (los inicios por foto ya no tienen sentido en la repetición).
        if loopPlaylist, tracks.count > 1 {
            var safety = 0
            while tail - crossfade < total, safety < 500 {
                for i in tracks.indices {
                    let start = max(0, tail - crossfade)
                    guard start < total else { break }
                    items.append((i, start))
                    tail = start + tracks[i].effectiveDuration(assetDuration: durations[i])
                }
                safety += 1
            }
        }

        var segments: [AudioSegment] = []
        for (n, item) in items.enumerated() {
            let track = tracks[item.index]
            let start = min(item.start, total)
            var end = total
            var fadesOut = false
            if n + 1 < items.count {
                let nextStart = items[n + 1].start
                end = min(total, nextStart + crossfade)
                fadesOut = nextStart < total
            }
            segments.append(AudioSegment(url: track.url, start: start, end: max(start, end),
                                         gain: gains?[item.index] ?? 1, fadeIn: n > 0, fadeOut: fadesOut,
                                         trimStart: track.trimStart, trimEnd: track.trimEnd))
        }
        if fadeOutAtEnd, let last = segments.indices.last, segments[last].end >= total - 0.01 {
            segments[last].fadeOut = true
        }
        return segments.filter { $0.duration > 0.05 }
    }
}
