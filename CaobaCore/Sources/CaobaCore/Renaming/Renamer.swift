import Foundation
import ImageIO

/// Un cambio de nombre previsto: fichero original y nombre nuevo (solo el nombre, sin carpeta).
public struct RenameEntry: Sendable, Equatable, Identifiable {
    public var from: URL
    public var newName: String

    public var id: URL { from }
    public var oldName: String { from.lastPathComponent }
    public var destination: URL { from.deletingLastPathComponent().appendingPathComponent(newName) }

    public init(from: URL, newName: String) {
        self.from = from
        self.newName = newName
    }
}

/// Transformación de mayúsculas/minúsculas del nombre.
public enum TextCase: String, Sendable, Codable, CaseIterable {
    case none, lowercase, uppercase, capitalize
}

/// Limpiezas opcionales del nombre.
public struct SanitizeOptions: Sendable, Equatable, Codable {
    public var removeAccents: Bool
    public var removeSpaces: Bool
    public var removeSpecialCharacters: Bool

    public init(removeAccents: Bool = false, removeSpaces: Bool = false, removeSpecialCharacters: Bool = false) {
        self.removeAccents = removeAccents
        self.removeSpaces = removeSpaces
        self.removeSpecialCharacters = removeSpecialCharacters
    }

    public var isEmpty: Bool { !removeAccents && !removeSpaces && !removeSpecialCharacters }
}

/// Opciones del modo "patrón".
public struct PatternRenameOptions: Sendable, Equatable {
    /// Patrón con placeholders: `{nombre}`, `{n}`, `{camara}`, `{objetivo}`,
    /// `{ancho}`, `{alto}`, `{orientacion}` y tokens de fecha `YYYY MM DD hh mm ss`.
    public var pattern: String
    public var sortBy: SortMode
    /// Dígitos del contador. 0 = automático según el número de ficheros (mínimo 2).
    public var sequenceDigits: Int
    public var sequenceStart: Int
    public var textCase: TextCase
    public var sanitize: SanitizeOptions

    public init(pattern: String, sortBy: SortMode = .name, sequenceDigits: Int = 0, sequenceStart: Int = 1,
                textCase: TextCase = .none, sanitize: SanitizeOptions = SanitizeOptions()) {
        self.pattern = pattern
        self.sortBy = sortBy
        self.sequenceDigits = sequenceDigits
        self.sequenceStart = sequenceStart
        self.textCase = textCase
        self.sanitize = sanitize
    }
}

/// Datos de un fichero que el patrón puede necesitar.
public struct RenameSourceInfo: Sendable, Equatable {
    public var url: URL
    public var date: Date?
    public var camera: String?
    public var lens: String?
    public var size: PixelSize?

    public init(url: URL, date: Date? = nil, camera: String? = nil, lens: String? = nil, size: PixelSize? = nil) {
        self.url = url
        self.date = date
        self.camera = camera
        self.lens = lens
        self.size = size
    }
}

/// Renombrado por lotes en cuatro modos. Primero se calcula un plan (que la
/// interfaz muestra como vista previa) y luego se ejecuta.
public struct Renamer: Sendable {
    public init() {}

    // MARK: - Planes

    /// Modo patrón. Lee EXIF y dimensiones solo si el patrón los necesita.
    public static func patternPlan(files: [URL], options: PatternRenameOptions) -> [RenameEntry] {
        let infos = gatherInfo(files: files, pattern: options.pattern, needsDates: options.sortBy == .date)
        let ordered: [RenameSourceInfo]
        switch options.sortBy {
        case .name: ordered = infos
        case .date: ordered = infos.sorted { ($0.date ?? .distantPast) < ($1.date ?? .distantPast) }
        }
        let total = ordered.count
        let autoDigits = options.sequenceDigits > 0
            ? options.sequenceDigits
            : max(String(total + options.sequenceStart - 1).count, 2)

        var names: [String] = []
        for (index, info) in ordered.enumerated() {
            let ext = info.url.pathExtension
            let seq = pad(index + options.sequenceStart, digits: autoDigits)
            var name = expand(pattern: options.pattern, info: info, sequence: seq)
            name = applyCase(name, options.textCase)
            name = sanitize(name, options.sanitize)
            names.append(name + (ext.isEmpty ? "" : "." + ext.lowercased()))
        }
        return resolveCollisions(files: ordered.map(\.url), names: names)
    }

    /// Corrector de numeración: detecta `prefijo + número + sufijo` común y
    /// rellena con ceros. Devuelve vacío si no hay nada que corregir.
    public static func autofixPlan(files: [URL]) -> [RenameEntry] {
        struct Parsed { let url: URL; let prefix: String; let number: Int; let digits: String; let suffix: String; let ext: String }
        let regex = try! NSRegularExpression(pattern: "^(.*?)(\\d+)([^\\d]*)$")
        var parsed: [Parsed] = []
        for url in files {
            let base = url.deletingPathExtension().lastPathComponent
            guard let m = regex.firstMatch(in: base, range: NSRange(base.startIndex..., in: base)),
                  let pr = Range(m.range(at: 1), in: base), let nr = Range(m.range(at: 2), in: base),
                  let sr = Range(m.range(at: 3), in: base), let number = Int(base[nr]) else { return [] }
            parsed.append(Parsed(url: url, prefix: String(base[pr]), number: number, digits: String(base[nr]),
                                 suffix: String(base[sr]), ext: url.pathExtension))
        }
        guard let first = parsed.first else { return [] }
        guard parsed.allSatisfy({ $0.prefix == first.prefix && $0.suffix == first.suffix }) else { return [] }
        let required = max(String(parsed.map(\.number).max() ?? 0).count, 2)
        let names = parsed.map { p -> String in
            let ext = p.ext.isEmpty ? "" : "." + p.ext
            return p.prefix + pad(p.number, digits: required) + p.suffix + ext
        }
        return resolveCollisions(files: parsed.map(\.url), names: names).filter { $0.newName != $0.oldName }
    }

    /// Buscar y reemplazar en el nombre (sin extensión).
    public static func searchReplacePlan(files: [URL], search: String, replace: String) -> [RenameEntry] {
        guard !search.isEmpty else { return [] }
        let names = files.map { url -> String in
            let base = url.deletingPathExtension().lastPathComponent.replacingOccurrences(of: search, with: replace)
            return base + extensionSuffix(url)
        }
        return resolveCollisions(files: files, names: names).filter { $0.newName != $0.oldName }
    }

    /// Prefijo y/o sufijo.
    public static func prefixSuffixPlan(files: [URL], prefix: String, suffix: String) -> [RenameEntry] {
        guard !prefix.isEmpty || !suffix.isEmpty else { return [] }
        let names = files.map { url in
            prefix + url.deletingPathExtension().lastPathComponent + suffix + extensionSuffix(url)
        }
        return resolveCollisions(files: files, names: names).filter { $0.newName != $0.oldName }
    }

    // MARK: - Ejecución

    /// Ejecuta un plan. En modo copia, copia a la carpeta de salida con el
    /// nombre nuevo. En modo sobrescribir, renombra en sitio evitando choques
    /// entre nombres viejos y nuevos y deja registro en `RenameHistory` para
    /// poder deshacerlo (salvo que `recordHistory` sea false).
    public func execute(plan: [RenameEntry], saveMode: SaveMode, recordHistory: Bool = true, modeLabel: String = "",
                        progress: ProgressHandler? = nil) async throws -> BatchSummary {
        guard !plan.isEmpty else { return BatchSummary() }
        let fm = FileManager.default
        var summary = BatchSummary()
        var done: [RenameOperation.Entry] = []
        defer {
            // Pase lo que pase, lo que ya se ha renombrado queda registrado para poder volver atrás.
            if recordHistory, saveMode.isOverwrite, !done.isEmpty, let folder = plan.first?.from.deletingLastPathComponent() {
                try? RenameHistory.record(RenameOperation(mode: modeLabel, entries: done), in: folder)
            }
        }

        switch saveMode {
        case .newCopy(let outputFolder):
            for (index, entry) in plan.enumerated() {
                try Task.checkCaobaCancellation()
                progress?(.step(index, of: plan.count, phase: .renaming, file: entry.oldName))
                let folder = outputFolder ?? entry.from.deletingLastPathComponent()
                try fm.createDirectory(at: folder, withIntermediateDirectories: true)
                let dest = folder.appendingPathComponent(entry.newName)
                do {
                    if fm.fileExists(atPath: dest.path) { try fm.removeItem(at: dest) }
                    try fm.copyItem(at: entry.from, to: dest)
                    summary.processed += 1
                } catch {
                    summary.failures.append("\(entry.oldName): \(error.localizedDescription)")
                }
            }

        case .overwrite:
            // Si algún nombre nuevo coincide con el nombre viejo de otro fichero
            // hay que pasar por nombres intermedios para no pisarlo.
            let oldNames = Set(plan.map { $0.oldName.lowercased() })
            let needsTwoPasses = plan.contains { entry in
                entry.newName.lowercased() != entry.oldName.lowercased() && oldNames.contains(entry.newName.lowercased())
            }
            if needsTwoPasses {
                let token = UUID().uuidString.prefix(8)
                var temps: [URL] = []
                for (index, entry) in plan.enumerated() {
                    try Task.checkCaobaCancellation()
                    let temp = entry.from.deletingLastPathComponent()
                        .appendingPathComponent("_caoba_rename_\(token)_\(index)")
                        .appendingPathExtension(entry.from.pathExtension)
                    try fm.moveItem(at: entry.from, to: temp)
                    temps.append(temp)
                    progress?(JobProgress(phase: .renaming, fraction: Double(index) / Double(plan.count * 2), currentFile: entry.oldName))
                }
                for (index, entry) in plan.enumerated() {
                    try Task.checkCaobaCancellation()
                    try fm.moveItem(at: temps[index], to: entry.destination)
                    done.append(RenameOperation.Entry(from: entry.oldName, to: entry.newName))
                    summary.processed += 1
                    progress?(JobProgress(phase: .renaming, fraction: Double(plan.count + index) / Double(plan.count * 2), currentFile: entry.newName))
                }
            } else {
                for (index, entry) in plan.enumerated() {
                    try Task.checkCaobaCancellation()
                    progress?(.step(index, of: plan.count, phase: .renaming, file: entry.oldName))
                    do {
                        try fm.moveItem(at: entry.from, to: entry.destination)
                        done.append(RenameOperation.Entry(from: entry.oldName, to: entry.newName))
                        summary.processed += 1
                    } catch {
                        summary.failures.append("\(entry.oldName): \(error.localizedDescription)")
                    }
                }
            }
        }
        progress?(.step(plan.count, of: plan.count, phase: .renaming))
        return summary
    }

    // MARK: - Piezas internas (públicas para poder testearlas)

    /// Sustituye tokens de fecha y placeholders. Primero las fechas, para que
    /// un nombre original que contenga "DD" o "MM" no se vea afectado.
    public static func expand(pattern: String, info: RenameSourceInfo, sequence: String) -> String {
        var result = pattern
        if patternNeedsDate(pattern) {
            let date = info.date
            let parts = date.map { Self.dateParts($0) }
            // Orden importa: "YYYY" antes que nada, y "MM" (mes) antes que "mm" (minuto) no se pisan por mayúsculas.
            result = result.replacingOccurrences(of: "YYYY", with: parts?.year ?? "0000")
            result = result.replacingOccurrences(of: "MM", with: parts?.month ?? "00")
            result = result.replacingOccurrences(of: "DD", with: parts?.day ?? "00")
            result = result.replacingOccurrences(of: "hh", with: parts?.hour ?? "00")
            result = result.replacingOccurrences(of: "mm", with: parts?.minute ?? "00")
            result = result.replacingOccurrences(of: "ss", with: parts?.second ?? "00")
        }
        let base = info.url.deletingPathExtension().lastPathComponent
        let orientation: String
        if let size = info.size {
            orientation = size.width > size.height ? "H" : (size.height > size.width ? "V" : "C")
        } else {
            orientation = "C"
        }
        result = result.replacingOccurrences(of: "{nombre}", with: base)
        result = result.replacingOccurrences(of: "{n}", with: sequence)
        result = result.replacingOccurrences(of: "{camara}", with: info.camera ?? "unknown")
        result = result.replacingOccurrences(of: "{objetivo}", with: info.lens ?? "unknown")
        result = result.replacingOccurrences(of: "{ancho}", with: String(info.size?.width ?? 0))
        result = result.replacingOccurrences(of: "{alto}", with: String(info.size?.height ?? 0))
        result = result.replacingOccurrences(of: "{orientacion}", with: orientation)
        return result
    }

    public static func applyCase(_ name: String, _ textCase: TextCase) -> String {
        switch textCase {
        case .none: return name
        case .lowercase: return name.lowercased()
        case .uppercase: return name.uppercased()
        case .capitalize: return name.capitalized
        }
    }

    public static func sanitize(_ name: String, _ options: SanitizeOptions) -> String {
        var result = name
        if options.removeAccents {
            result = result.folding(options: .diacriticInsensitive, locale: nil)
        }
        if options.removeSpaces {
            result = result.replacingOccurrences(of: "\\s+", with: "_", options: .regularExpression)
        }
        if options.removeSpecialCharacters {
            result = result.replacingOccurrences(of: "[^A-Za-z0-9._-]", with: "", options: .regularExpression)
        }
        return result
    }

    /// Evita que dos ficheros acaben con el mismo nombre añadiendo `_2`, `_3`...
    public static func resolveCollisions(files: [URL], names: [String]) -> [RenameEntry] {
        var used = Set<String>()
        var plan: [RenameEntry] = []
        for (url, proposed) in zip(files, names) {
            var name = proposed
            if used.contains(name.lowercased()) {
                let ext = (name as NSString).pathExtension
                let base = (name as NSString).deletingPathExtension
                var n = 2
                while used.contains("\(base)_\(n)\(ext.isEmpty ? "" : "." + ext)".lowercased()) { n += 1 }
                name = "\(base)_\(n)\(ext.isEmpty ? "" : "." + ext)"
            }
            used.insert(name.lowercased())
            plan.append(RenameEntry(from: url, newName: name))
        }
        return plan
    }

    public static func patternNeedsDate(_ pattern: String) -> Bool {
        ["YYYY", "MM", "DD", "hh", "mm", "ss"].contains { pattern.contains($0) }
    }

    public static func patternNeedsCamera(_ pattern: String) -> Bool {
        pattern.contains("{camara}") || pattern.contains("{objetivo}")
    }

    public static func patternNeedsSize(_ pattern: String) -> Bool {
        pattern.contains("{ancho}") || pattern.contains("{alto}") || pattern.contains("{orientacion}")
    }

    /// Lee de cada fichero solo lo que el patrón necesita.
    static func gatherInfo(files: [URL], pattern: String, needsDates: Bool) -> [RenameSourceInfo] {
        let wantDate = needsDates || patternNeedsDate(pattern)
        let wantCamera = patternNeedsCamera(pattern)
        let wantSize = patternNeedsSize(pattern)
        return files.map { url in
            var info = RenameSourceInfo(url: url)
            guard wantDate || wantCamera || wantSize else { return info }
            let props = ImageIOHelpers.properties(of: url)
            if wantDate { info.date = ImageIOHelpers.captureDate(from: props) ?? ImageIOHelpers.captureOrFileDate(of: url) }
            if wantSize { info.size = props.flatMap { ImageIOHelpers.displaySize(from: $0) } }
            if wantCamera {
                let tiff = props?[kCGImagePropertyTIFFDictionary] as? [CFString: Any]
                let exif = props?[kCGImagePropertyExifDictionary] as? [CFString: Any]
                info.camera = CameraName.combine(make: tiff?[kCGImagePropertyTIFFMake] as? String, model: tiff?[kCGImagePropertyTIFFModel] as? String)
                info.lens = (exif?[kCGImagePropertyExifLensModel] as? String)?.trimmingCharacters(in: .whitespaces)
            }
            return info
        }
    }

    private static func dateParts(_ date: Date) -> (year: String, month: String, day: String, hour: String, minute: String, second: String) {
        let c = Calendar.current.dateComponents([.year, .month, .day, .hour, .minute, .second], from: date)
        return (pad(c.year ?? 0, digits: 4), pad(c.month ?? 0, digits: 2), pad(c.day ?? 0, digits: 2),
                pad(c.hour ?? 0, digits: 2), pad(c.minute ?? 0, digits: 2), pad(c.second ?? 0, digits: 2))
    }

    static func pad(_ n: Int, digits: Int) -> String {
        let s = String(n)
        return s.count >= digits ? s : String(repeating: "0", count: digits - s.count) + s
    }

    private static func extensionSuffix(_ url: URL) -> String {
        url.pathExtension.isEmpty ? "" : "." + url.pathExtension
    }
}

/// "Nikon Z6" a partir de make y model, sin repetir la marca si el modelo ya la lleva.
public enum CameraName {
    public static func combine(make: String?, model: String?) -> String? {
        let make = make?.trimmingCharacters(in: .whitespaces) ?? ""
        let model = model?.trimmingCharacters(in: .whitespaces) ?? ""
        if model.isEmpty { return make.isEmpty ? nil : make }
        if make.isEmpty || model.lowercased().hasPrefix(make.lowercased()) { return model }
        return make + " " + model
    }
}
