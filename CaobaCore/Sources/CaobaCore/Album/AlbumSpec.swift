import Foundation
import CoreGraphics

/// Medidas y opciones de un álbum, tal como las pide el laboratorio. Todo va en milímetros:
/// los píxeles solo salen al dibujar o al exportar (con los `ppi`).
///
/// Un pliego es la doble página abierta: en un álbum de 30 × 30 mide 60 × 30 cm más el sangrado.
public struct AlbumSpec: Codable, Sendable, Equatable, Hashable {
    /// Página cerrada (una sola cara), en mm.
    public var pageWidthMM: Double
    public var pageHeightMM: Double
    /// Lo que se corta al encuadernar: la imagen crece esto por cada lado del pliego.
    public var bleedMM: Double
    /// Margen por dentro del corte que las fotos no invaden (por fuera y junto al lomo).
    public var safetyMM: Double
    /// Franja a cada lado del lomo donde no deben quedar caras (se pierde en el pliegue).
    public var spineMM: Double
    /// Número de pliegos del álbum. `nil` = los que pida el reparto automático.
    public var spreads: Int?
    /// El primer pliego solo usa la página derecha y el último solo la izquierda (fase 4).
    public var singleFirstLast: Bool
    /// Cómo se exportan esos pliegos de una página: enteros (la otra mitad en blanco) o solo la
    /// página útil. Según el laboratorio.
    public var singlePageExport: AlbumSinglePageExport
    /// Portada con sus propias medidas, o `nil` si el álbum no lleva (fase 4).
    public var cover: AlbumCover?
    /// Resolución de la exportación (de 300 a 600).
    public var ppi: Int
    /// Ancho del lomo entre las dos páginas. En los pliegos es 0 (el lomo es una línea); lo usa
    /// la portada, que lleva contraportada, lomo y tapa (`coverSpec`).
    public var spineWidthMM: Double

    /// Separación fija entre casillas. «Solo fotos»: no se configura.
    public static let gapMM = 4.0
    public static let ppiRange = 300...600

    public init(pageWidthMM: Double = 300, pageHeightMM: Double = 300, bleedMM: Double = 3, safetyMM: Double = 10,
                spineMM: Double = 10, spreads: Int? = nil, singleFirstLast: Bool = false, cover: AlbumCover? = nil, ppi: Int = 300,
                singlePageExport: AlbumSinglePageExport = .fullSpread, spineWidthMM: Double = 0) {
        self.pageWidthMM = pageWidthMM
        self.pageHeightMM = pageHeightMM
        self.bleedMM = bleedMM
        self.safetyMM = safetyMM
        self.spineMM = spineMM
        self.spreads = spreads
        self.singleFirstLast = singleFirstLast
        self.cover = cover
        self.ppi = ppi
        self.singlePageExport = singlePageExport
        self.spineWidthMM = spineWidthMM
    }

    /// Lee lo guardado siendo tolerante: lo que falte se queda por defecto.
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let base = AlbumSpec()
        pageWidthMM = try c.decodeIfPresent(Double.self, forKey: .pageWidthMM) ?? base.pageWidthMM
        pageHeightMM = try c.decodeIfPresent(Double.self, forKey: .pageHeightMM) ?? base.pageHeightMM
        bleedMM = try c.decodeIfPresent(Double.self, forKey: .bleedMM) ?? base.bleedMM
        safetyMM = try c.decodeIfPresent(Double.self, forKey: .safetyMM) ?? base.safetyMM
        spineMM = try c.decodeIfPresent(Double.self, forKey: .spineMM) ?? base.spineMM
        spreads = try c.decodeIfPresent(Int.self, forKey: .spreads)
        singleFirstLast = try c.decodeIfPresent(Bool.self, forKey: .singleFirstLast) ?? false
        cover = try c.decodeIfPresent(AlbumCover.self, forKey: .cover)
        ppi = try c.decodeIfPresent(Int.self, forKey: .ppi) ?? base.ppi
        singlePageExport = (try? c.decodeIfPresent(AlbumSinglePageExport.self, forKey: .singlePageExport)) ?? .fullSpread
        spineWidthMM = try c.decodeIfPresent(Double.self, forKey: .spineWidthMM) ?? 0
    }

    // MARK: - Geometría del pliego (mm, origen arriba-izquierda del corte)

    /// El pliego abierto al corte, sin sangrado (con el lomo en medio si tiene ancho).
    public var spreadSize: CGSize { CGSize(width: pageWidthMM * 2 + spineWidthMM, height: pageHeightMM) }

    /// Dónde empieza y acaba el lomo (en un pliego, los dos son la línea del centro).
    public var spineStart: Double { pageWidthMM }
    public var spineEnd: Double { pageWidthMM + spineWidthMM }
    /// Centro del lomo.
    public var spineCenter: Double { pageWidthMM + spineWidthMM / 2 }

    /// Zona útil de todo el pliego (lo de dentro del margen de seguridad). La usan las fotos que
    /// cruzan el lomo.
    public var spreadContent: CGRect {
        CGRect(x: safetyMM, y: safetyMM, width: spreadSize.width - safetyMM * 2, height: pageHeightMM - safetyMM * 2)
    }

    /// Zona útil de una página: el margen de seguridad también va junto al lomo.
    public func pageContent(_ side: AlbumPageSide) -> CGRect {
        let x = side == .left ? safetyMM : spineEnd + safetyMM
        return CGRect(x: x, y: safetyMM, width: pageWidthMM - safetyMM * 2, height: pageHeightMM - safetyMM * 2)
    }

    /// La página entera al corte (sin márgenes).
    public func pageRect(_ side: AlbumPageSide) -> CGRect {
        CGRect(x: side == .left ? 0 : spineEnd, y: 0, width: pageWidthMM, height: pageHeightMM)
    }

    /// Franja del lomo (el lomo y un margen a cada lado), donde no deben quedar caras.
    public var spineStrip: CGRect {
        CGRect(x: spineStart - spineMM, y: 0, width: spineWidthMM + spineMM * 2, height: pageHeightMM)
    }

    /// Píxeles de un pliego exportado, sangrado incluido.
    public var exportPixelSize: PixelSize {
        pixels(widthMM: spreadSize.width + bleedMM * 2, heightMM: pageHeightMM + bleedMM * 2)
    }

    /// Píxeles de una sola página exportada, sangrado incluido (pliegos de una página, fase 4).
    public var pagePixelSize: PixelSize {
        pixels(widthMM: pageWidthMM + bleedMM * 2, heightMM: pageHeightMM + bleedMM * 2)
    }

    func pixels(widthMM: Double, heightMM: Double) -> PixelSize {
        let perMM = Double(ppi) / 25.4
        return PixelSize(width: Int((widthMM * perMM).rounded()), height: Int((heightMM * perMM).rounded()))
    }

    /// Las medidas de la portada como si fuera un pliego: contraportada, lomo con su ancho y tapa,
    /// con su sangrado o solapa, el margen de seguridad y la franja del lomo del álbum y sus ppp.
    /// `nil` si el álbum no lleva portada.
    public var coverSpec: AlbumSpec? {
        guard let cover else { return nil }
        return AlbumSpec(pageWidthMM: cover.widthMM, pageHeightMM: cover.heightMM, bleedMM: cover.bleedMM, safetyMM: safetyMM,
                         spineMM: spineMM, spreads: nil, singleFirstLast: false, cover: nil, ppi: ppi, spineWidthMM: cover.spineWidthMM)
    }

    /// Que las medidas tengan sentido: página de al menos 5 cm y márgenes que dejen sitio.
    public var isValid: Bool {
        pageWidthMM >= 50 && pageHeightMM >= 50 && bleedMM >= 0 && safetyMM >= 0 && spineMM >= 0
            && safetyMM * 2 < min(pageWidthMM, pageHeightMM) - 20 && (spreads ?? 1) >= 1
    }
}

/// Cómo se exportan los pliegos de una sola página (el primero y el último, si el álbum los lleva).
public enum AlbumSinglePageExport: String, Codable, Sendable, Hashable, CaseIterable {
    /// Como los demás pliegos, con la página pegada a la tapa en blanco.
    case fullSpread
    /// Solo la página útil, con su sangrado.
    case pageOnly
}

/// Lado de la doble página.
public enum AlbumPageSide: String, Codable, Sendable, Hashable {
    case left, right
}

/// Portada: tapa, lomo y contraportada en una sola pieza, con su sangrado o solapa (fase 4).
public struct AlbumCover: Codable, Sendable, Equatable, Hashable {
    /// Cada tapa (delantera y trasera), en mm.
    public var widthMM: Double
    public var heightMM: Double
    /// Lomo del álbum cerrado.
    public var spineWidthMM: Double
    /// Lo que envuelve el cartón o se corta.
    public var bleedMM: Double

    public init(widthMM: Double = 310, heightMM: Double = 310, spineWidthMM: Double = 20, bleedMM: Double = 15) {
        self.widthMM = widthMM
        self.heightMM = heightMM
        self.spineWidthMM = spineWidthMM
        self.bleedMM = bleedMM
    }
}

/// Tipo de álbum de Ajustes: la plantilla base de la que sale cada álbum. Los define el usuario
/// (CAOBA no trae ninguno); al crear un álbum se copian sus medidas.
public struct AlbumType: Codable, Sendable, Equatable, Hashable, Identifiable {
    public var id: UUID
    public var name: String
    public var spec: AlbumSpec

    public init(id: UUID = UUID(), name: String, spec: AlbumSpec = AlbumSpec()) {
        self.id = id
        self.name = name
        self.spec = spec
    }
}
