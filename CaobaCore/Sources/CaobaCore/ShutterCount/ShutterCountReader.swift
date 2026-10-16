import Foundation
import ImageIO

/// Resultado del análisis de disparos de una foto.
public struct ShutterCountResult: Sendable, Equatable {
    public enum Source: String, Sendable { case exiftool, imageIO }

    public struct Camera: Sendable, Equatable {
        public var make: String?
        public var model: String?
        public var displayName: String?
        public var serial: String?
        public var firmware: String?
        public var lens: String?
    }

    public struct Shutter: Sendable, Equatable {
        public var count: Int?
        public var mechanicalCount: Int?
        /// Disparos estimados de vida útil, si conocemos el modelo o la marca.
        public var lifeExpectancy: Int?
        /// Porcentaje usado (0-100+), si hay contador y estimación.
        public var percentUsed: Double?
        /// `true` si la estimación es genérica por marca y no del modelo exacto.
        public var isEstimate: Bool
    }

    public struct Photo: Sendable, Equatable {
        public var dateTime: String?
        public var iso: Int?
        public var exposureTime: Double?
        public var fNumber: Double?
        public var focalLength: Double?
        public var width: Int?
        public var height: Int?
    }

    public var source: Source
    public var camera: Camera
    public var shutter: Shutter
    public var photo: Photo
}

/// Lee el contador de disparos. Primero con exiftool (empaquetado en la app o
/// instalado en el sistema), que entiende los MakerNotes de todas las marcas;
/// si no hay exiftool, con ImageIO, que en la práctica solo expone el contador
/// de Nikon.
public enum ShutterCountReader {

    // MARK: Localizar exiftool

    /// Dónde está exiftool y con qué intérprete lanzarlo.
    public struct ExifToolLocation: Sendable, Equatable {
        public var executable: URL
        public var arguments: [String]
        public var isBundled: Bool
    }

    /// Busca exiftool: primero el empaquetado en la app, luego el de Homebrew o /usr/local.
    public static func locateExifTool(bundleResources: URL? = Bundle.main.resourceURL) -> ExifToolLocation? {
        let fm = FileManager.default
        if let resources = bundleResources {
            let script = resources.appendingPathComponent("exiftool/exiftool")
            let lib = resources.appendingPathComponent("exiftool/lib")
            if fm.fileExists(atPath: script.path), fm.fileExists(atPath: lib.path), fm.fileExists(atPath: "/usr/bin/perl") {
                return ExifToolLocation(executable: URL(fileURLWithPath: "/usr/bin/perl"), arguments: ["-I", lib.path, script.path], isBundled: true)
            }
        }
        for path in ["/opt/homebrew/bin/exiftool", "/usr/local/bin/exiftool"] where fm.isExecutableFile(atPath: path) {
            return ExifToolLocation(executable: URL(fileURLWithPath: path), arguments: [], isBundled: false)
        }
        return nil
    }

    /// Tags que pedimos a exiftool (con `-n` los numéricos vienen sin formatear).
    static let exifToolTags = [
        "ShutterCount", "ImageCount", "ShutterCount2", "ShutterCount3", "MechanicalShutterCount",
        "Make", "Model", "SerialNumber", "InternalSerialNumber", "FirmwareVersion", "Firmware",
        "LensModel", "Lens", "LensID", "DateTimeOriginal", "ISO", "ExposureTime", "FNumber", "FocalLength",
        "ImageWidth", "ImageHeight", "ExifImageWidth", "ExifImageHeight",
    ]

    // MARK: Lectura

    public static func read(_ url: URL, exifTool: ExifToolLocation? = locateExifTool()) async throws -> ShutterCountResult {
        if let exifTool {
            let json = try await runExifTool(exifTool, file: url)
            return try parseExifToolJSON(json)
        }
        return try readWithImageIO(url)
    }

    static func runExifTool(_ location: ExifToolLocation, file: URL) async throws -> Data {
        let process = Process()
        process.executableURL = location.executable
        process.arguments = location.arguments + ["-j", "-n", "-fast2", "-q"] + exifToolTags.map { "-" + $0 } + [file.path]
        let output = Pipe()
        process.standardOutput = output
        process.standardError = Pipe()
        let data: Data = try await withCheckedThrowingContinuation { continuation in
            process.terminationHandler = { proc in
                let data = output.fileHandleForReading.readDataToEndOfFile()
                if proc.terminationStatus == 0 || !data.isEmpty {
                    continuation.resume(returning: data)
                } else {
                    continuation.resume(throwing: CaobaError.cannotReadImage("exiftool (\(proc.terminationStatus))"))
                }
            }
            do { try process.run() } catch { continuation.resume(throwing: CaobaError.cannotReadImage("exiftool: \(error.localizedDescription)")) }
        }
        return data
    }

    /// Convierte la salida JSON de exiftool en el resultado.
    public static func parseExifToolJSON(_ data: Data) throws -> ShutterCountResult {
        guard let array = try JSONSerialization.jsonObject(with: data) as? [[String: Any]], let tags = array.first else {
            throw CaobaError.cannotReadImage("exiftool JSON")
        }
        func string(_ keys: String...) -> String? {
            for k in keys { if let v = tags[k] { let s = "\(v)".trimmingCharacters(in: .whitespaces); if !s.isEmpty { return s } } }
            return nil
        }
        func int(_ keys: String...) -> Int? {
            for k in keys {
                if let v = tags[k] as? Int { return v }
                if let v = tags[k] as? Double { return Int(v) }
                if let v = tags[k] as? String, let i = Int(v) { return i }
            }
            return nil
        }
        func double(_ keys: String...) -> Double? {
            for k in keys {
                if let v = tags[k] as? Double { return v }
                if let v = tags[k] as? Int { return Double(v) }
                if let v = tags[k] as? String, let d = Double(v) { return d }
            }
            return nil
        }
        let make = string("Make"), model = string("Model")
        var camera = ShutterCountResult.Camera(make: make, model: model, displayName: CameraName.combine(make: make, model: model))
        camera.serial = string("SerialNumber", "InternalSerialNumber")
        camera.firmware = string("FirmwareVersion", "Firmware")
        camera.lens = string("LensModel", "Lens", "LensID")
        let count = int("ShutterCount", "ImageCount", "ShutterCount2", "ShutterCount3")
        let shutter = makeShutter(count: count, mechanical: int("MechanicalShutterCount"), make: make, model: model)
        let photo = ShutterCountResult.Photo(dateTime: string("DateTimeOriginal"), iso: int("ISO"), exposureTime: double("ExposureTime"),
                                             fNumber: double("FNumber"), focalLength: double("FocalLength"),
                                             width: int("ImageWidth", "ExifImageWidth"), height: int("ImageHeight", "ExifImageHeight"))
        return ShutterCountResult(source: .exiftool, camera: camera, shutter: shutter, photo: photo)
    }

    /// Respaldo con ImageIO: contador solo para Nikon.
    public static func readWithImageIO(_ url: URL) throws -> ShutterCountResult {
        guard let props = ImageIOHelpers.properties(of: url) else { throw CaobaError.cannotReadImage(url.lastPathComponent) }
        let tiff = props[kCGImagePropertyTIFFDictionary] as? [CFString: Any] ?? [:]
        let exif = props[kCGImagePropertyExifDictionary] as? [CFString: Any] ?? [:]
        let nikon = props[kCGImagePropertyMakerNikonDictionary] as? [CFString: Any] ?? [:]
        let make = (tiff[kCGImagePropertyTIFFMake] as? String)?.trimmingCharacters(in: .whitespaces)
        let model = (tiff[kCGImagePropertyTIFFModel] as? String)?.trimmingCharacters(in: .whitespaces)
        var camera = ShutterCountResult.Camera(make: make, model: model, displayName: CameraName.combine(make: make, model: model))
        camera.serial = (exif[kCGImagePropertyExifBodySerialNumber] as? String) ?? (nikon[kCGImagePropertyMakerNikonCameraSerialNumber] as? String)
        camera.lens = exif[kCGImagePropertyExifLensModel] as? String
        let count = nikon[kCGImagePropertyMakerNikonShutterCount] as? Int
        let shutter = makeShutter(count: count, mechanical: nil, make: make, model: model)
        let size = ImageIOHelpers.displaySize(from: props)
        let photo = ShutterCountResult.Photo(dateTime: exif[kCGImagePropertyExifDateTimeOriginal] as? String,
                                             iso: (exif[kCGImagePropertyExifISOSpeedRatings] as? [Int])?.first,
                                             exposureTime: exif[kCGImagePropertyExifExposureTime] as? Double,
                                             fNumber: exif[kCGImagePropertyExifFNumber] as? Double,
                                             focalLength: exif[kCGImagePropertyExifFocalLength] as? Double,
                                             width: size?.width, height: size?.height)
        return ShutterCountResult(source: .imageIO, camera: camera, shutter: shutter, photo: photo)
    }

    static func makeShutter(count: Int?, mechanical: Int?, make: String?, model: String?) -> ShutterCountResult.Shutter {
        let life = ShutterLife.expectancy(make: make, model: model)
        let percent: Double? = (count != nil && life.count != nil) ? (Double(count!) / Double(life.count!) * 10000).rounded() / 100 : nil
        return ShutterCountResult.Shutter(count: count, mechanicalCount: mechanical, lifeExpectancy: life.count, percentUsed: percent, isEstimate: life.isEstimate)
    }
}

/// Vida útil estimada del obturador por modelo (fabricantes y datos de la
/// comunidad), portada de la app antigua.
public enum ShutterLife {
    public static let byModel: [String: Int] = [
        // Nikon
        "nikon d3": 300_000, "nikon d3s": 300_000, "nikon d3x": 300_000, "nikon d4": 400_000, "nikon d4s": 400_000,
        "nikon d5": 400_000, "nikon d6": 400_000, "nikon d800": 200_000, "nikon d800e": 200_000, "nikon d810": 200_000, "nikon d850": 200_000,
        "nikon d700": 150_000, "nikon d750": 150_000, "nikon d780": 200_000, "nikon d500": 200_000, "nikon d300": 150_000, "nikon d300s": 150_000,
        "nikon d200": 100_000, "nikon d7000": 150_000, "nikon d7100": 150_000, "nikon d7200": 150_000, "nikon d7500": 150_000,
        "nikon d600": 150_000, "nikon d610": 150_000, "nikon d90": 100_000, "nikon d80": 100_000,
        "nikon d5600": 100_000, "nikon d5500": 100_000, "nikon d5300": 100_000, "nikon d5200": 100_000, "nikon d5100": 100_000, "nikon d5000": 100_000,
        "nikon d3500": 100_000, "nikon d3400": 100_000, "nikon d3300": 100_000,
        "nikon z9": 400_000, "nikon z8": 200_000, "nikon z7": 200_000, "nikon z7 ii": 200_000, "nikon z7ii": 200_000,
        "nikon z6": 200_000, "nikon z6 ii": 200_000, "nikon z6ii": 200_000, "nikon z6 iii": 200_000, "nikon z6iii": 200_000,
        "nikon z5": 200_000, "nikon zf": 200_000, "nikon zfc": 200_000, "nikon z50": 200_000, "nikon z30": 200_000,
        // Canon
        "canon eos-1d x": 400_000, "canon eos-1d x mark ii": 500_000, "canon eos-1d x mark iii": 500_000,
        "canon eos 5d": 100_000, "canon eos 5d mark ii": 150_000, "canon eos 5d mark iii": 150_000, "canon eos 5d mark iv": 200_000,
        "canon eos 5ds": 150_000, "canon eos 5ds r": 150_000, "canon eos 6d": 100_000, "canon eos 6d mark ii": 150_000,
        "canon eos 7d": 150_000, "canon eos 7d mark ii": 200_000, "canon eos 80d": 100_000, "canon eos 90d": 120_000,
        "canon eos 70d": 100_000, "canon eos 60d": 100_000, "canon eos 77d": 100_000, "canon eos 800d": 100_000,
        "canon eos 750d": 100_000, "canon eos 760d": 100_000, "canon eos 200d": 100_000, "canon eos 250d": 100_000,
        "canon eos r": 200_000, "canon eos rp": 100_000, "canon eos r3": 500_000, "canon eos r5": 500_000, "canon eos r5 mark ii": 500_000,
        "canon eos r6": 300_000, "canon eos r6 mark ii": 400_000, "canon eos r7": 200_000, "canon eos r8": 200_000, "canon eos r10": 100_000,
        "canon eos r50": 100_000, "canon eos r100": 100_000,
        // Sony
        "sony ilce-1": 500_000, "sony a1": 500_000, "sony ilce-9": 500_000, "sony a9": 500_000, "sony ilce-9m2": 500_000, "sony a9 ii": 500_000,
        "sony ilce-9m3": 500_000, "sony a9 iii": 500_000, "sony ilce-7rm5": 300_000, "sony a7r v": 300_000, "sony ilce-7rm4": 500_000, "sony a7r iv": 500_000,
        "sony ilce-7rm3": 500_000, "sony a7r iii": 500_000, "sony ilce-7rm2": 500_000, "sony a7r ii": 500_000, "sony ilce-7m4": 300_000, "sony a7 iv": 300_000,
        "sony ilce-7m3": 200_000, "sony a7 iii": 200_000, "sony ilce-7m2": 200_000, "sony a7 ii": 200_000, "sony ilce-7cm2": 200_000, "sony a7c ii": 200_000,
        "sony ilce-7c": 200_000, "sony a7c": 200_000, "sony ilce-6700": 200_000, "sony a6700": 200_000, "sony ilce-6600": 200_000, "sony a6600": 200_000,
        "sony ilce-6500": 200_000, "sony a6500": 200_000, "sony ilce-6400": 200_000, "sony a6400": 200_000, "sony ilce-6300": 200_000, "sony a6300": 200_000,
        "sony ilce-6100": 100_000, "sony a6100": 100_000, "sony ilce-6000": 100_000, "sony a6000": 100_000,
        // Pentax
        "pentax k-1": 300_000, "pentax k-1 ii": 300_000, "pentax k-3": 200_000, "pentax k-3 ii": 200_000, "pentax k-3 iii": 200_000,
        "pentax k-5": 100_000, "pentax k-5 ii": 100_000, "pentax k-70": 100_000, "pentax kf": 100_000,
    ]

    /// Estimación para una cámara: modelo exacto, coincidencia parcial o
    /// genérica por marca. `isEstimate` indica que no es del modelo exacto.
    public static func expectancy(make: String?, model: String?) -> (count: Int?, isEstimate: Bool) {
        let make = (make ?? "").trimmingCharacters(in: .whitespaces)
        let model = (model ?? "").trimmingCharacters(in: .whitespaces)
        guard !make.isEmpty || !model.isEmpty else { return (nil, true) }
        // "NIKON CORPORATION" + "NIKON Z 6" → "nikon z 6"; si el modelo ya lleva la marca, no se repite.
        let combined = (CameraName.combine(make: make, model: model) ?? "").lowercased()
            .replacingOccurrences(of: " corporation", with: "")
            .replacingOccurrences(of: "nikon z ", with: "nikon z")
        if let exact = byModel[combined] { return (exact, false) }
        for (key, value) in byModel where combined.contains(key) || key.contains(combined) { return (value, false) }
        let brand = make.lowercased() + " " + model.lowercased()
        if brand.contains("nikon") { return (150_000, true) }
        if brand.contains("canon") { return (150_000, true) }
        if brand.contains("sony") { return (200_000, true) }
        if brand.contains("pentax") { return (100_000, true) }
        return (nil, true)
    }
}
