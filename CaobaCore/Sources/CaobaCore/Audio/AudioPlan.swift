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
    /// Segundos que tarda en subir al empezar (0 = entra de golpe).
    public var fadeInSeconds: Double
    /// Segundos que tarda en bajar a silencio al acabar (0 = se corta).
    public var fadeOutSeconds: Double
    /// Tramo de la canción que se usa (en segundos de la canción).
    public var trimStart: Double = 0
    public var trimEnd: Double? = nil
    /// Pista de la que sale el tramo (para dibujarlo en su carril).
    public var trackID: UUID? = nil

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
    ///
    /// Cada cambio de pista es un cruce que dura lo que diga la pista que entra (su
    /// `crossfade` o, si no tiene, el general `crossfade`): la que entra sube en ese
    /// tiempo y la que sale sigue sonando lo mismo mientras baja. Con 0 es un corte seco.
    public static func build(tracks: [AudioTrack], durations: [Double], gains: [Double]?, timeline: SlideshowTimeline,
                             fadeOutAtEnd: Bool, loopPlaylist: Bool = false,
                             crossfade: Double = AudioOptions.crossfadeSeconds,
                             fadeOutDuration: Double = AudioOptions.fadeOutSeconds) -> [AudioSegment] {
        guard !tracks.isEmpty, tracks.count == durations.count else { return [] }
        let total = timeline.totalDuration
        /// Cruce con el que entra una pista.
        func entry(_ i: Int) -> Double { max(0, tracks[i].crossfade ?? crossfade) }

        // Primera pasada por la lista: inicio automático o en una foto.
        var items: [(index: Int, start: Double)] = []
        var tail = 0.0
        for (i, track) in tracks.enumerated() {
            let start: Double
            switch track.startMode {
            case .atPhoto(let index): start = timeline.startTime(ofPhoto: index)
            case .atTime(let t): start = max(0, t)
            case .automatic: start = i == 0 ? 0 : max(0, tail - entry(i))
            }
            items.append((i, start))
            tail = start + track.effectiveDuration(assetDuration: durations[i])
        }

        // Si sobra vídeo y hay que repetir la lista, seguimos encadenando en
        // automático (los inicios por foto ya no tienen sentido en la repetición).
        if loopPlaylist, tracks.count > 1 {
            var safety = 0
            while tail - entry(0) < total, safety < 500 {
                for i in tracks.indices {
                    let start = max(0, tail - entry(i))
                    guard start < total else { break }
                    items.append((i, start))
                    tail = start + tracks[i].effectiveDuration(assetDuration: durations[i])
                }
                safety += 1
            }
        }

        // Los cruces se calculan en el orden en que suenan, no en el de la lista: una pista
        // con inicio fijo puede ir más abajo en la lista y empezar antes que otra.
        // (Desempate por orden de llegada, para que dos que empiezan a la vez no se crucen.)
        items = items.enumerated().sorted { ($0.element.start, $0.offset) < ($1.element.start, $1.offset) }.map(\.element)

        var segments: [AudioSegment] = []
        for (n, item) in items.enumerated() {
            let track = tracks[item.index]
            let start = min(item.start, total)
            var end = total
            var fadeOut = 0.0
            if n + 1 < items.count {
                // Sigue sonando mientras entra la siguiente, y baja en ese mismo tiempo.
                let next = items[n + 1]
                let cross = entry(next.index)
                end = min(total, next.start + cross)
                fadeOut = next.start < total ? cross : 0
            }
            segments.append(AudioSegment(url: track.url, start: start, end: max(start, end),
                                         gain: gains?[item.index] ?? 1, fadeInSeconds: n > 0 ? entry(item.index) : 0, fadeOutSeconds: fadeOut,
                                         trimStart: track.trimStart, trimEnd: track.trimEnd, trackID: track.id))
        }
        if fadeOutAtEnd, let last = segments.indices.last, segments[last].end >= total - 0.01 {
            segments[last].fadeOutSeconds = max(0, fadeOutDuration)
        }
        return segments.filter { $0.duration > 0.05 }
    }
}
