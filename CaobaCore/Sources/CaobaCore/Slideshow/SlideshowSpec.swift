import Foundation
import CoreGraphics

/// Formatos de vídeo disponibles, con los mismos identificadores que la app
/// antigua para que los `.caoba` existentes se sigan leyendo.
public enum VideoFormat: String, Sendable, Codable, CaseIterable, Identifiable {
    case landscape16x9 = "169_h"
    case portrait9x16 = "916_v"
    case portrait4x5 = "45_v"
    case landscape5x4 = "45_h"
    case portrait2x3 = "23_v"
    case landscape3x2 = "23_h"

    public var id: String { rawValue }

    public var size: PixelSize {
        switch self {
        case .landscape16x9: return PixelSize(width: 1920, height: 1080)
        case .portrait9x16: return PixelSize(width: 1080, height: 1920)
        case .portrait4x5: return PixelSize(width: 1080, height: 1350)
        case .landscape5x4: return PixelSize(width: 1350, height: 1080)
        case .portrait2x3: return PixelSize(width: 1280, height: 1920)
        case .landscape3x2: return PixelSize(width: 1920, height: 1280)
        }
    }

    public var label: String {
        switch self {
        case .landscape16x9: return "16:9"
        case .portrait9x16: return "9:16"
        case .portrait4x5: return "4:5"
        case .landscape5x4: return "5:4"
        case .portrait2x3: return "2:3"
        case .landscape3x2: return "3:2"
        }
    }

    public var aspectRatio: Double { size.aspectRatio }
}

/// Marca de agua del vídeo.
public struct VideoWatermark: Sendable, Equatable, Codable {
    public var url: URL
    public var position: OverlayPosition
    /// Ancho como porcentaje del lado corto del vídeo.
    public var sizePercent: Double
    /// Opacidad 0-100.
    public var opacity: Double

    public init(url: URL, position: OverlayPosition = .bottomRight, sizePercent: Double = 30, opacity: Double = 80) {
        self.url = url
        self.position = position
        self.sizePercent = sizePercent
        self.opacity = opacity
    }
}

/// Pista de música.
public struct AudioTrack: Sendable, Equatable, Codable, Identifiable {
    public enum StartMode: Sendable, Equatable, Codable {
        /// Empieza cuando acaba la anterior (con crossfade); la primera, en 0.
        case automatic
        /// Empieza cuando aparece la foto indicada. Solo se conserva para leer
        /// configuraciones antiguas; la app ya trabaja con `atTime`.
        case atPhoto(Int)
        /// Empieza en el segundo indicado del vídeo.
        case atTime(Double)
    }

    public var id: UUID
    public var url: URL
    public var startMode: StartMode
    /// Segundos de la canción que se saltan al principio (silencio, intro...).
    public var trimStart: Double
    /// Segundo de la canción en el que se corta; `nil` = hasta el final.
    public var trimEnd: Double?

    public init(id: UUID = UUID(), url: URL, startMode: StartMode = .automatic, trimStart: Double = 0, trimEnd: Double? = nil) {
        self.id = id
        self.url = url
        self.startMode = startMode
        self.trimStart = max(0, trimStart)
        self.trimEnd = trimEnd
    }

    /// Duración que suena de verdad, dada la duración real del fichero.
    public func effectiveDuration(assetDuration: Double) -> Double {
        let end = min(assetDuration, trimEnd ?? assetDuration)
        return max(0.5, end - min(trimStart, assetDuration))
    }

    private enum CodingKeys: String, CodingKey { case id, url, startMode, trimStart, trimEnd }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        url = try c.decode(URL.self, forKey: .url)
        startMode = try c.decodeIfPresent(StartMode.self, forKey: .startMode) ?? .automatic
        trimStart = try c.decodeIfPresent(Double.self, forKey: .trimStart) ?? 0
        trimEnd = try c.decodeIfPresent(Double.self, forKey: .trimEnd)
    }
}

/// Opciones de audio del slideshow.
public struct AudioOptions: Sendable, Equatable, Codable {
    public var tracks: [AudioTrack]
    public var fadeOut: Bool
    public var normalize: Bool
    /// Si el vídeo dura más que las pistas, vuelve a empezar la lista (con
    /// crossfade entre cambios). Si no, la última pista se repite sola.
    public var loopPlaylist: Bool

    public static let crossfadeSeconds = 3.0
    public static let fadeOutSeconds = 3.0
    public static let targetLoudness = -16.0

    public init(tracks: [AudioTrack] = [], fadeOut: Bool = true, normalize: Bool = false, loopPlaylist: Bool = true) {
        self.tracks = tracks
        self.fadeOut = fadeOut
        self.normalize = normalize
        self.loopPlaylist = loopPlaylist
    }

    private enum CodingKeys: String, CodingKey { case tracks, fadeOut, normalize, loopPlaylist }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        tracks = try c.decodeIfPresent([AudioTrack].self, forKey: .tracks) ?? []
        fadeOut = try c.decodeIfPresent(Bool.self, forKey: .fadeOut) ?? true
        normalize = try c.decodeIfPresent(Bool.self, forKey: .normalize) ?? false
        loopPlaylist = try c.decodeIfPresent(Bool.self, forKey: .loopPlaylist) ?? true
    }
}

/// Una foto (o portada, o créditos) dentro del vídeo.
public struct SlideshowPhoto: Sendable, Equatable, Identifiable {
    public var id: UUID
    public var url: URL
    /// Segundos en pantalla (sin contar la transición).
    public var duration: Double
    /// Efecto Ken Burns ya resuelto (sin `random`); `nil` = foto fija.
    public var kenBurns: KenBurnsEffect?
    /// Puntos personalizados (efecto `custom`) o foco para efectos automáticos.
    public var points: KenBurnsPoints?
    public var easing: KenBurnsEasing?

    public init(id: UUID = UUID(), url: URL, duration: Double, kenBurns: KenBurnsEffect? = nil, points: KenBurnsPoints? = nil, easing: KenBurnsEasing? = nil) {
        self.id = id
        self.url = url
        self.duration = max(0.1, duration)
        self.kenBurns = kenBurns
        self.points = points
        self.easing = easing
    }
}

/// Todo lo que hace falta para generar un slideshow.
public struct SlideshowSpec: Sendable, Equatable {
    public var photos: [SlideshowPhoto]
    public var format: VideoFormat
    public var fps: Int
    /// Fundido de 1 s entre fotos.
    public var transition: Bool
    public var watermark: VideoWatermark?
    public var audio: AudioOptions
    public var kenBurns: KenBurnsSettings
    public var output: URL
    /// Mitad de resolución y bitrate bajo, para la vista previa.
    public var preview: Bool

    public static let transitionSeconds = 1.0

    public init(photos: [SlideshowPhoto], format: VideoFormat, fps: Int = 25, transition: Bool = true, watermark: VideoWatermark? = nil,
                audio: AudioOptions = AudioOptions(), kenBurns: KenBurnsSettings = KenBurnsSettings(), output: URL, preview: Bool = false) {
        self.photos = photos
        self.format = format
        self.fps = fps
        self.transition = transition
        self.watermark = watermark
        self.audio = audio
        self.kenBurns = kenBurns
        self.output = output
        self.preview = preview
    }

    /// Tamaño real del vídeo (la preview va a la mitad, en píxeles pares).
    public var renderSize: PixelSize {
        guard preview else { return format.size }
        let s = format.size
        return PixelSize(width: (s.width / 2) & ~1, height: (s.height / 2) & ~1)
    }

    public var transitionDuration: Double { transition ? Self.transitionSeconds : 0 }
}

/// Línea de tiempo del vídeo: cuándo entra y sale cada foto.
public struct SlideshowTimeline: Sendable, Equatable {
    public struct Segment: Sendable, Equatable {
        public var photoIndex: Int
        /// Instante en que la foto empieza a verse (al inicio de su fundido de entrada).
        public var start: Double
        /// Instante en que deja de verse del todo.
        public var end: Double
        public var duration: Double { end - start }
    }

    public var segments: [Segment]
    public var transition: Double
    public var totalDuration: Double

    /// Con transición, la foto i+1 empieza a entrar cuando a la i le queda
    /// exactamente la duración de la transición: igual que el `xfade` antiguo.
    public init(durations: [Double], transition: Double) {
        self.transition = transition
        var segments: [Segment] = []
        var start = 0.0
        for (i, d) in durations.enumerated() {
            segments.append(Segment(photoIndex: i, start: start, end: start + d + transition))
            start += d
        }
        self.segments = segments
        totalDuration = durations.isEmpty ? 0 : start + transition
    }

    /// Instante en que empieza la foto `index` (sin contar su fundido de entrada).
    public func startTime(ofPhoto index: Int) -> Double {
        guard segments.indices.contains(index) else { return totalDuration }
        return segments[index].start
    }

    /// Qué se ve en el instante `t`: la foto actual y, si hay fundido en curso,
    /// la siguiente con su progreso (0 = recién empieza, 1 = ya ha sustituido).
    public func frame(at t: Double) -> (current: Int, next: Int?, progress: Double)? {
        guard !segments.isEmpty else { return nil }
        let clamped = min(max(0, t), totalDuration - 1e-9)
        // La última foto cuyo inicio es <= t es la que está entrando o ya en pantalla.
        var latest = 0
        for (i, s) in segments.enumerated() where s.start <= clamped { latest = i }
        // Si acaba de empezar y todavía está en su fundido de entrada, la anterior sigue visible debajo.
        if transition > 0, latest > 0, clamped < segments[latest].start + transition {
            return (latest - 1, latest, min(1, (clamped - segments[latest].start) / transition))
        }
        let current = latest
        return (current, nil, 0)
    }
}
