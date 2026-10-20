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

/// Un preset con nombre.
struct NamedPreset<S: Codable & Equatable>: Codable, Equatable, Identifiable {
    var name: String
    var settings: S
    var id: String { name }
}

/// Módulos que tienen presets; el valor es la clave de preferencias.
enum PresetModule: String, CaseIterable {
    case processor, watermark, collage
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

    /// Todos los presets de los tres módulos en un único fichero.
    struct Bundle: Codable {
        var version = 1
        var processor: [NamedPreset<ProcessorSettings>] = []
        var watermark: [NamedPreset<WatermarkSettings>] = []
        var collage: [NamedPreset<CollageSettings>] = []
        var count: Int { processor.count + watermark.count + collage.count }
    }

    var totalCount: Int { bundle.count }

    var bundle: Bundle {
        Bundle(processor: presets(.processor, as: ProcessorSettings.self),
               watermark: presets(.watermark, as: WatermarkSettings.self),
               collage: presets(.collage, as: CollageSettings.self))
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
        return incoming.count
    }
}
