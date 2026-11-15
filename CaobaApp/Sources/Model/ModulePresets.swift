import SwiftUI
import CaobaCore

// MARK: - Ajustes de cada módulo, tal como se guardan

/// Ajustes del Procesador.
struct ProcessorSettings: Codable, Equatable {
    var autorotate = true
    var cropEnabled = false
    var cropPreset: ProcessorView.CropPreset = .square
    var customRatioW = 4
    var customRatioH = 3
    var cropAnchor: CropAnchor = .center
    var resizeEnabled = false
    var maxDimension = 2048
    var quality = 90.0
    var keepFormat = true
    var outputFormat: OutputFormat = .jpeg
}

/// Ajustes de la Marca de agua (la ruta del PNG incluida).
struct WatermarkSettings: Codable, Equatable {
    var watermarkPath: String?
    var options = WatermarkOptions()
}

/// Ajustes de salida del Collage (logo incluido).
struct CollageSettings: Codable, Equatable {
    var longestSide = 3000
    var gap = 10.0
    var background: CanvasColor = .white
    var cornerRadius = 0.0
    var shadow = true
    var title = ""
    var quality = 90.0
    var logoPath: String?
    var logoPosition: OverlayPosition = .bottomRight
    var logoSize = 20.0
    var logoOpacity = 80.0
}

/// Ajustes del modo Patrón del Renombrador.
struct RenamerSettings: Codable, Equatable {
    var pattern = "{nombre}"
    var sortBy: SortMode = .name
    /// 0 = automático según el número de fotos.
    var digits = 0
    var start = 1
    var textCase: TextCase = .none
    var sanitize = SanitizeOptions()

    /// De partida para fotos de una sesión, cuando en Ajustes no hay preset elegido.
    static let sessionDefault = RenamerSettings(pattern: SessionLayout.defaultRenamePattern)
}

/// Ajustes del Contact Sheet (logo incluido). El título admite `{sesion}` y `{fecha_sesion}`,
/// que se cambian al aplicar el preset con fotos de una sesión.
struct ContactSheetSettings: Codable, Equatable {
    var columns = 5
    var thumbSize = 200
    var layout: ContactSheetOptions.Layout = .grid
    var cropMode: ContactSheetOptions.CropMode = .contain
    var showFilenames = true
    var showNumbering = false
    var title = ""
    var background: CanvasColor = .white
    var showBorder = false
    var borderWidth = 1.0
    var quality = 90.0
    var logoPath: String?
    var logoPosition: OverlayPosition = .bottomRight
    var logoSize = 20.0
    var logoOpacity = 80.0
}

/// Un preset con nombre.
struct NamedPreset<S: Codable & Equatable>: Codable, Equatable, Identifiable {
    var name: String
    var settings: S
    var id: String { name }
}

/// Módulos que tienen presets; el valor es la clave de preferencias.
enum PresetModule: String, CaseIterable {
    case processor, watermark, collage, renamer, contactSheet
    /// Plantillas del Slideshow (un `SlideshowPreset` sin lo de las fotos).
    case slideshow
}

// MARK: - Almacén

/// Presets con nombre y última configuración de cada módulo, en las
/// preferencias de la app (globales). `version` cambia con cada escritura
/// para que las vistas que lo leen se refresquen.
@Observable
@MainActor
final class PresetStore {
    static let shared = PresetStore()
    private(set) var version = 0

    private func presetsKey(_ module: PresetModule) -> String { "caoba.presets.\(module.rawValue)" }
    private func lastKey(_ module: PresetModule) -> String { "caoba.lastSettings.\(module.rawValue)" }

    private func read<T: Decodable>(_ key: String, as type: T.Type) -> T? {
        guard let data = UserDefaults.standard.data(forKey: key) else { return nil }
        return try? JSONDecoder().decode(T.self, from: data)
    }

    private func write<T: Encodable>(_ value: T, key: String) {
        if let data = try? JSONEncoder().encode(value) { UserDefaults.standard.set(data, forKey: key) }
        version += 1
    }

    func presets<S: Codable & Equatable>(_ module: PresetModule, as type: S.Type) -> [NamedPreset<S>] {
        _ = version
        return read(presetsKey(module), as: [NamedPreset<S>].self) ?? []
    }

    /// Guarda o sustituye el preset con ese nombre.
    func save<S: Codable & Equatable>(_ settings: S, named name: String, module: PresetModule) {
        var list = presets(module, as: S.self).filter { $0.name != name }
        list.append(NamedPreset(name: name, settings: settings))
        list.sort { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
        write(list, key: presetsKey(module))
    }

    func delete<S: Codable & Equatable>(named name: String, module: PresetModule, as type: S.Type) {
        write(presets(module, as: S.self).filter { $0.name != name }, key: presetsKey(module))
    }

    func last<S: Codable & Equatable>(_ module: PresetModule, as type: S.Type) -> S? {
        read(lastKey(module), as: S.self)
    }

    func saveLast<S: Codable & Equatable>(_ settings: S, module: PresetModule) {
        if let data = try? JSONEncoder().encode(settings) { UserDefaults.standard.set(data, forKey: lastKey(module)) }
    }

    // MARK: Exportar e importar

    /// Todos los presets de los módulos en un único fichero.
    struct Bundle: Codable {
        var version = 1
        var processor: [NamedPreset<ProcessorSettings>] = []
        var watermark: [NamedPreset<WatermarkSettings>] = []
        var collage: [NamedPreset<CollageSettings>] = []
        var renamer: [NamedPreset<RenamerSettings>] = []
        var contactSheet: [NamedPreset<ContactSheetSettings>] = []
        var slideshow: [NamedPreset<SlideshowPreset>] = []
        var count: Int { processor.count + watermark.count + collage.count + renamer.count + contactSheet.count + slideshow.count }

        init(processor: [NamedPreset<ProcessorSettings>], watermark: [NamedPreset<WatermarkSettings>],
             collage: [NamedPreset<CollageSettings>], renamer: [NamedPreset<RenamerSettings>],
             contactSheet: [NamedPreset<ContactSheetSettings>], slideshow: [NamedPreset<SlideshowPreset>]) {
            self.processor = processor
            self.watermark = watermark
            self.collage = collage
            self.renamer = renamer
            self.contactSheet = contactSheet
            self.slideshow = slideshow
        }

        /// Tolerante: los ficheros exportados antes no traen Renombrador, Contact Sheet ni plantillas.
        init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            version = try c.decodeIfPresent(Int.self, forKey: .version) ?? 1
            processor = try c.decode([NamedPreset<ProcessorSettings>].self, forKey: .processor)
            watermark = try c.decode([NamedPreset<WatermarkSettings>].self, forKey: .watermark)
            collage = try c.decode([NamedPreset<CollageSettings>].self, forKey: .collage)
            renamer = try c.decodeIfPresent([NamedPreset<RenamerSettings>].self, forKey: .renamer) ?? []
            contactSheet = try c.decodeIfPresent([NamedPreset<ContactSheetSettings>].self, forKey: .contactSheet) ?? []
            slideshow = try c.decodeIfPresent([NamedPreset<SlideshowPreset>].self, forKey: .slideshow) ?? []
        }
    }

    var totalCount: Int { bundle.count }

    var bundle: Bundle {
        Bundle(processor: presets(.processor, as: ProcessorSettings.self),
               watermark: presets(.watermark, as: WatermarkSettings.self),
               collage: presets(.collage, as: CollageSettings.self),
               renamer: presets(.renamer, as: RenamerSettings.self),
               contactSheet: presets(.contactSheet, as: ContactSheetSettings.self),
               slideshow: presets(.slideshow, as: SlideshowPreset.self))
    }

    func exportData() throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return try encoder.encode(bundle)
    }

    /// Añade los presets del fichero; los nombres repetidos se sustituyen. Devuelve cuántos ha leído.
    @discardableResult
    func importData(_ data: Data) throws -> Int {
        let incoming = try JSONDecoder().decode(Bundle.self, from: data)
        for p in incoming.processor { save(p.settings, named: p.name, module: .processor) }
        for p in incoming.watermark { save(p.settings, named: p.name, module: .watermark) }
        for p in incoming.collage { save(p.settings, named: p.name, module: .collage) }
        for p in incoming.renamer { save(p.settings, named: p.name, module: .renamer) }
        for p in incoming.contactSheet { save(p.settings, named: p.name, module: .contactSheet) }
        for p in incoming.slideshow { save(p.settings, named: p.name, module: .slideshow) }
        return incoming.count
    }
}
