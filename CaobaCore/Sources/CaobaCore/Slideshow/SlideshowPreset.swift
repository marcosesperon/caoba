import Foundation
import CoreGraphics

/// Sección `slideshow` del fichero `.caoba`. Las claves son las de la app
/// antigua (v1) para poder leer sus ficheros; lo nuevo se añade sin romperlas.
public struct SlideshowPreset: Codable, Sendable, Equatable {
    public struct ImageWithDuration: Codable, Sendable, Equatable {
        public var path: String?
        public var duration: Double?
        public init(path: String? = nil, duration: Double? = nil) { self.path = path; self.duration = duration }
    }

    public struct Watermark: Codable, Sendable, Equatable {
        public var path: String?
        public var position: String?
        public var size: Double?
        public var opacity: Double?
        public init(path: String? = nil, position: String? = nil, size: Double? = nil, opacity: Double? = nil) {
            self.path = path; self.position = position; self.size = size; self.opacity = opacity
        }
        /// La app antigua guardaba la opacidad a veces en fracción (0,8) y a veces en porcentaje (80).
        public var opacityPercent: Double? { opacity.map { $0 <= 1 ? $0 * 100 : $0 } }
    }

    public struct Audio: Codable, Sendable, Equatable {
        public var fadeout: Bool?
        public var normalize: Bool?
        /// Nuevo: repetir la lista de pistas si el vídeo es más largo.
        public var loopPlaylist: Bool?
        public init(fadeout: Bool? = nil, normalize: Bool? = nil, loopPlaylist: Bool? = nil) {
            self.fadeout = fadeout; self.normalize = normalize; self.loopPlaylist = loopPlaylist
        }
    }

    public struct MusicTrack: Codable, Sendable, Equatable {
        public var path: String
        /// "auto" o "manual".
        public var mode: String?
        public var startPhoto: Int?
        /// Nuevo: recorte de la canción en segundos.
        public var trimStart: Double?
        public var trimEnd: Double?
        /// Nuevo: inicio en segundos del vídeo (modo "time"). Sustituye a `startPhoto`.
        public var startTime: Double?
        public init(path: String, mode: String? = nil, startPhoto: Int? = nil, trimStart: Double? = nil, trimEnd: Double? = nil, startTime: Double? = nil) {
            self.path = path; self.mode = mode; self.startPhoto = startPhoto; self.trimStart = trimStart; self.trimEnd = trimEnd; self.startTime = startTime
        }
    }

    public struct Points: Codable, Sendable, Equatable {
        public var startFx: Double?, startFy: Double?, startZoom: Double?
        public var endFx: Double?, endFy: Double?, endZoom: Double?
        public var fit: String?
        public var delayPct: Double?

        public init(_ p: KenBurnsPoints) {
            startFx = p.startFocus.x; startFy = p.startFocus.y; startZoom = p.startZoom
            endFx = p.endFocus.x; endFy = p.endFocus.y; endZoom = p.endZoom
            fit = p.fit.rawValue; delayPct = p.delayPercent
        }

        public var kenBurnsPoints: KenBurnsPoints {
            KenBurnsPoints(startFocus: CGPoint(x: startFx ?? 0.5, y: startFy ?? 0.5), startZoom: startZoom ?? 1,
                           endFocus: CGPoint(x: endFx ?? 0.5, y: endFy ?? 0.5), endZoom: endZoom ?? 1,
                           fit: KenBurnsPoints.Fit(rawValue: fit ?? "cover") ?? .cover, delayPercent: delayPct ?? 0)
        }
    }

    public struct KenBurnsSection: Codable, Sendable, Equatable {
        public var intensity: String?
        public var easing: String?
        public var durationPct: Double?
        /// v1: efecto por índice de foto. Nuevo: por nombre de fichero (`byFile`), que no se desalinea al excluir fotos.
        public var perPhoto: [String: String]?
        public var points: [String: Points]?
        public var byFile: [String: String]?
        public var pointsByFile: [String: Points]?
        public init() {}
    }

    public struct FocusPoint: Codable, Sendable, Equatable {
        public var file: String?
        public var fx: Double?
        public var fy: Double?
        public init(file: String? = nil, fx: Double? = nil, fy: Double? = nil) { self.file = file; self.fx = fx; self.fy = fy }
    }

    public struct CollageSection: Codable, Sendable, Equatable {
        public var templateMode: String?
        public var revealDuration: Double?
        public var holdDuration: Double?
        public var bgColor: String?
        public var gap: Double?
        public var borderRadius: Double?
        public var shadowIntensity: Double?
        /// v1: foco por fila ("0", "1"...) con la lista de celdas.
        public var focusPoints: [String: [FocusPoint]]?
        /// Nuevo: identificadores de plantilla en orden (la app antigua no lo guardaba).
        public var sequence: [String]?
        /// Nuevo: "mantener" propio por fila ("0", "1"...), en segundos.
        public var holdByRow: [String: Double]?
        /// Nuevo: ajustes de la hoja «Componer secuencia».
        public var compose: ComposeSettings?
        public init() {}
    }

    public var mode: String?
    public var sortMode: String?
    public var orientationFilter: String?
    public var fileOrder: [String]?
    public var excludedFiles: [String]?
    public var videoFormat: String?
    public var durationPerPhoto: Double?
    public var useTransition: Bool?
    public var cover: ImageWithDuration?
    public var credits: ImageWithDuration?
    public var watermark: Watermark?
    public var audio: Audio?
    public var musicTracks: [MusicTrack]?
    public var kenBurns: KenBurnsSection?
    public var collage: CollageSection?
    /// Nuevo: duración propia por nombre de fichero (las demás usan `durationPerPhoto`).
    public var durations: [String: Double]?

    public init() {}

    public static let sectionName = "slideshow"

    public static func load(from folder: URL) -> SlideshowPreset? {
        CaobaConfig.readSection(sectionName, as: SlideshowPreset.self, from: folder)
    }

    public func save(in folder: URL) throws {
        try CaobaConfig.writeSection(Self.sectionName, value: self, in: folder)
    }
}
