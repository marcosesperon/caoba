import Foundation
import ImageIO
import CoreGraphics
import CoreLocation

/// Coordenadas GPS en grados decimales (negativo = sur / oeste).
public struct GPSCoordinate: Sendable, Equatable, Codable {
    public var latitude: Double
    public var longitude: Double

    public init(latitude: Double, longitude: Double) {
        self.latitude = latitude
        self.longitude = longitude
    }
}

/// Lo que el módulo de Metadatos muestra de una foto.
public struct PhotoMetadata: Sendable, Equatable {
    public var artist: String?
    public var copyright: String?
    public var description: String?
    /// Fecha de captura tal como está en EXIF ("2024:05:31 14:22:10").
    public var dateTimeOriginal: String?
    public var make: String?
    public var model: String?
    public var camera: String?
    public var lens: String?
    public var size: PixelSize?
    public var iso: Int?
    public var exposureTime: Double?
    public var fNumber: Double?
    public var focalLength: Double?
    public var flash: Int?
    public var software: String?
    public var gps: GPSCoordinate?

    public init() {}

    public var captureDate: Date? { dateTimeOriginal.flatMap(ExifDate.parse) }
}

/// Campos editables. `nil` = no tocar; cadena vacía = borrar el campo.
public struct MetadataEdit: Sendable, Equatable, Codable {
    public var artist: String?
    public var copyright: String?
    public var description: String?
    /// En formato EXIF "yyyy:MM:dd HH:mm:ss".
    public var dateTimeOriginal: String?
    /// `.some(nil)` borra el GPS; `nil` no lo toca.
    public var gps: GPSCoordinate??

    public init(artist: String? = nil, copyright: String? = nil, description: String? = nil,
                dateTimeOriginal: String? = nil, gps: GPSCoordinate?? = nil) {
        self.artist = artist
        self.copyright = copyright
        self.description = description
        self.dateTimeOriginal = dateTimeOriginal
        self.gps = gps
    }

    public var isEmpty: Bool {
        artist == nil && copyright == nil && description == nil && dateTimeOriginal == nil && gps == nil
    }
}

/// Lectura y escritura de metadatos con ImageIO. La escritura usa
/// `CGImageDestinationCopyImageSource`, que copia los datos de imagen tal cual
/// (sin recomprimir) y solo reescribe los metadatos.
///
/// ImageIO modela estos campos en XMP: artista = `dc:creator`, descripción =
/// `dc:description`, copyright = `dc:rights`, fecha = `photoshop:DateCreated`,
/// GPS = `exif:GPSLatitude` / `exif:GPSLongitude` en formato "DD,MM.mmN".
/// Al guardar, ImageIO sincroniza esos valores con los tags EXIF/TIFF clásicos.
public enum MetadataService {

    // MARK: Lectura

    public static func read(_ url: URL) -> PhotoMetadata {
        var result = PhotoMetadata()
        guard let source = ImageIOHelpers.source(for: url), let props = ImageIOHelpers.properties(of: source) else { return result }
        let tiff = props[kCGImagePropertyTIFFDictionary] as? [CFString: Any] ?? [:]
        let exif = props[kCGImagePropertyExifDictionary] as? [CFString: Any] ?? [:]
        let gps = props[kCGImagePropertyGPSDictionary] as? [CFString: Any] ?? [:]

        result.artist = nonEmpty(tiff[kCGImagePropertyTIFFArtist])
        result.copyright = nonEmpty(tiff[kCGImagePropertyTIFFCopyright])
        result.description = nonEmpty(tiff[kCGImagePropertyTIFFImageDescription])
        result.dateTimeOriginal = nonEmpty(exif[kCGImagePropertyExifDateTimeOriginal])
        result.make = nonEmpty(tiff[kCGImagePropertyTIFFMake])
        result.model = nonEmpty(tiff[kCGImagePropertyTIFFModel])
        result.camera = CameraName.combine(make: result.make, model: result.model)
        result.lens = nonEmpty(exif[kCGImagePropertyExifLensModel]) ?? nonEmpty(props[kCGImagePropertyExifAuxDictionary].flatMap { ($0 as? [CFString: Any])?[kCGImagePropertyExifAuxLensModel] })
        result.size = ImageIOHelpers.displaySize(from: props)
        result.iso = (exif[kCGImagePropertyExifISOSpeedRatings] as? [Int])?.first ?? exif[kCGImagePropertyExifISOSpeedRatings] as? Int
        result.exposureTime = exif[kCGImagePropertyExifExposureTime] as? Double
        result.fNumber = exif[kCGImagePropertyExifFNumber] as? Double
        result.focalLength = exif[kCGImagePropertyExifFocalLength] as? Double
        result.flash = exif[kCGImagePropertyExifFlash] as? Int
        result.software = nonEmpty(tiff[kCGImagePropertyTIFFSoftware])

        if let lat = gps[kCGImagePropertyGPSLatitude] as? Double, let lon = gps[kCGImagePropertyGPSLongitude] as? Double {
            let latRef = (gps[kCGImagePropertyGPSLatitudeRef] as? String) ?? "N"
            let lonRef = (gps[kCGImagePropertyGPSLongitudeRef] as? String) ?? "E"
            result.gps = GPSCoordinate(latitude: latRef.uppercased() == "S" ? -lat : lat,
                                       longitude: lonRef.uppercased() == "W" ? -lon : lon)
        }

        // Respaldo XMP: ImageIO solo actualiza los tags EXIF/TIFF clásicos si ya
        // existían en el fichero; lo que escribimos nosotros vive en XMP
        // (dc:creator, dc:rights, dc:description, photoshop:DateCreated, exif:GPS*).
        // Es también lo que escriben Lightroom y compañía.
        if let xmp = CGImageSourceCopyMetadataAtIndex(source, 0, nil) {
            func xmpString(_ path: String) -> String? {
                nonEmpty(CGImageMetadataCopyStringValueWithPath(xmp, nil, path as CFString) as String?)
            }
            result.artist = result.artist ?? xmpString("dc:creator")
            result.copyright = result.copyright ?? xmpString("dc:rights")
            result.description = result.description ?? xmpString("dc:description")
            if result.dateTimeOriginal == nil, let created = xmpString("photoshop:DateCreated") ?? xmpString("exif:DateTimeOriginal") {
                result.dateTimeOriginal = exifDate(fromXMP: created)
            }
            if result.gps == nil, let lat = xmpString("exif:GPSLatitude").flatMap(parseXMPCoordinate),
               let lon = xmpString("exif:GPSLongitude").flatMap(parseXMPCoordinate) {
                result.gps = GPSCoordinate(latitude: lat, longitude: lon)
            }
        }
        return result
    }

    private static func nonEmpty(_ value: Any?) -> String? {
        guard let s = value as? String else { return nil }
        let t = s.trimmingCharacters(in: .whitespacesAndNewlines)
        return t.isEmpty ? nil : t
    }

    // MARK: Escritura

    /// Aplica los cambios sin recomprimir la imagen. Si `stripOthers` es true,
    /// borra todos los metadatos previos y deja solo los campos indicados.
    ///
    /// Se hace en dos pasadas porque ImageIO se comporta distinto según el modo:
    /// - sin mezcla (`merge = false`) respeta lo que quitamos, pero no siempre
    ///   sincroniza los valores XMP nuevos con los tags EXIF/TIFF clásicos;
    /// - con mezcla (`merge = true`) sincroniza bien los valores nuevos, pero no
    ///   permite borrar nada.
    /// Como la imagen no se recomprime, la segunda pasada es casi gratis.
    /// Tras escribir se vuelve a leer para comprobar que ha quedado bien
    /// (ImageIO ha tenido fallos silenciosos en algunas versiones).
    public static func write(_ edit: MetadataEdit, to url: URL, stripOthers: Bool = false) throws {
        let fields = normalizedFields(edit)
        let needsClearPass = stripOthers || fields.contains { $0.value == nil }
        let needsSetPass = fields.contains { $0.value != nil }
        guard needsClearPass || needsSetPass else { return }

        var current = url
        var temps: [URL] = []
        defer { temps.forEach(TempFiles.remove) }

        if needsClearPass {
            let temp = try TempFiles.makeFileURL(extension: url.pathExtension)
            temps.append(temp)
            try rewrite(from: current, to: temp, merge: false) { source in
                let metadata: CGMutableImageMetadata
                if !stripOthers, let existing = CGImageSourceCopyMetadataAtIndex(source, 0, nil),
                   let copy = CGImageMetadataCreateMutableCopy(existing) {
                    metadata = copy
                } else {
                    metadata = CGImageMetadataCreateMutable()
                }
                for field in fields where field.value == nil {
                    for path in field.paths { CGImageMetadataRemoveTagWithPath(metadata, nil, path as CFString) }
                }
                return metadata
            }
            current = temp
        }

        if needsSetPass {
            let temp = try TempFiles.makeFileURL(extension: url.pathExtension)
            temps.append(temp)
            try rewrite(from: current, to: temp, merge: true) { _ in
                let metadata = CGImageMetadataCreateMutable()
                for field in fields {
                    guard let value = field.value else { continue }
                    for path in field.paths {
                        CGImageMetadataSetValueWithPath(metadata, nil, path as CFString, value as CFTypeRef)
                    }
                }
                return metadata
            }
            current = temp
        }

        // Verificación: lo que pedimos escribir tiene que leerse igual.
        let check = read(current)
        if let artist = edit.artist?.trimmingCharacters(in: .whitespacesAndNewlines), check.artist != (artist.isEmpty ? nil : artist) {
            throw CaobaError.metadataWriteFailed("\(url.lastPathComponent): artist")
        }
        if let date = edit.dateTimeOriginal?.trimmingCharacters(in: .whitespacesAndNewlines), !date.isEmpty, check.dateTimeOriginal != date {
            throw CaobaError.metadataWriteFailed("\(url.lastPathComponent): date")
        }
        try FileOperations.commit(temporary: current, to: url)
        temps.removeAll { $0 == current }
    }

    /// Campo a escribir: rutas XMP y valor ya convertido; `nil` = borrar.
    private struct Field {
        var paths: [String]
        var value: Any?
    }

    /// Convierte el `MetadataEdit` en campos con sus rutas XMP y valores.
    private static func normalizedFields(_ edit: MetadataEdit) -> [Field] {
        var fields: [Field] = []
        func text(_ raw: String?, paths: [String], build: (String) -> Any) {
            guard let raw else { return }
            let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            fields.append(Field(paths: paths, value: trimmed.isEmpty ? nil : build(trimmed)))
        }
        text(edit.artist, paths: ["dc:creator"]) { [$0] }
        text(edit.description, paths: ["dc:description"]) { $0 }
        text(edit.copyright, paths: ["dc:rights"]) { $0 }
        text(edit.dateTimeOriginal, paths: ["photoshop:DateCreated", "exif:DateTimeOriginal"]) { Self.xmpDate(fromExif: $0) }
        if let gpsEdit = edit.gps {
            if let gps = gpsEdit {
                fields.append(Field(paths: ["exif:GPSLatitude"], value: xmpCoordinate(gps.latitude, positive: "N", negative: "S")))
                fields.append(Field(paths: ["exif:GPSLongitude"], value: xmpCoordinate(gps.longitude, positive: "E", negative: "W")))
            } else {
                fields.append(Field(paths: ["exif:GPSLatitude", "exif:GPSLongitude"], value: nil))
            }
        }
        return fields
    }

    /// Copia la imagen de `from` a `to` sin recomprimir, aplicando la metadata que devuelve `build`.
    private static func rewrite(from: URL, to: URL, merge: Bool, build: (CGImageSource) -> CGMutableImageMetadata) throws {
        guard let source = ImageIOHelpers.source(for: from), let type = CGImageSourceGetType(source) else {
            throw CaobaError.cannotReadImage(from.lastPathComponent)
        }
        guard let dest = CGImageDestinationCreateWithURL(to as CFURL, type, 1, nil) else {
            throw CaobaError.cannotWriteImage(to.lastPathComponent)
        }
        let options: [CFString: Any] = [
            kCGImageDestinationMetadata: build(source),
            kCGImageDestinationMergeMetadata: merge,
        ]
        var error: Unmanaged<CFError>?
        guard CGImageDestinationCopyImageSource(dest, source, options as CFDictionary, &error) else {
            let message = error.map { String(describing: $0.takeRetainedValue()) } ?? "desconocido"
            throw CaobaError.metadataWriteFailed("\(from.lastPathComponent): \(message)")
        }
    }

    /// Escribe el mismo cambio en varios ficheros.
    public static func writeBatch(_ edit: MetadataEdit, to files: [URL], stripOthers: Bool = false,
                                  progress: ProgressHandler? = nil) async throws -> BatchSummary {
        try await writePerFile(files.map { ($0, edit) }, stripOthers: stripOthers, progress: progress)
    }

    /// Escribe un cambio distinto por fichero.
    public static func writePerFile(_ edits: [(URL, MetadataEdit)], stripOthers: Bool = false,
                                    progress: ProgressHandler? = nil) async throws -> BatchSummary {
        guard !edits.isEmpty else { throw CaobaError.noFiles }
        var summary = BatchSummary()
        for (index, (url, edit)) in edits.enumerated() {
            try Task.checkCaobaCancellation()
            progress?(.step(index, of: edits.count, phase: .writingMetadata, file: url.lastPathComponent))
            if edit.isEmpty && !stripOthers { summary.skipped += 1; continue }
            do {
                try write(edit, to: url, stripOthers: stripOthers)
                summary.processed += 1
            } catch {
                summary.failures.append("\(url.lastPathComponent): \(error)")
            }
        }
        progress?(.step(edits.count, of: edits.count, phase: .writingMetadata))
        return summary
    }

    // MARK: Conversión de formatos

    /// "2024:05:31 14:22:10" → "2024-05-31T14:22:10" (formato XMP).
    static func xmpDate(fromExif exif: String) -> String {
        guard exif.count >= 19 else { return exif }
        let s = Array(exif.prefix(19))
        return "\(String(s[0..<4]))-\(String(s[5..<7]))-\(String(s[8..<10]))T\(String(s[11..<19]))"
    }

    /// "2024-05-31T14:22:10" (XMP) → "2024:05:31 14:22:10" (EXIF). Ignora zona horaria si la hay.
    static func exifDate(fromXMP xmp: String) -> String {
        guard xmp.count >= 19 else { return xmp }
        let s = Array(xmp.prefix(19))
        return "\(String(s[0..<4])):\(String(s[5..<7])):\(String(s[8..<10])) \(String(s[11..<19]))"
    }

    /// "DD,MM.mmmmN" o "DD,MM,SSN" (XMP) → grados decimales con signo.
    static func parseXMPCoordinate(_ raw: String) -> Double? {
        let trimmed = raw.trimmingCharacters(in: .whitespaces)
        guard let ref = trimmed.last, "NSEW".contains(ref) else { return nil }
        let parts = trimmed.dropLast().split(separator: ",").map { Double($0.trimmingCharacters(in: .whitespaces)) }
        guard parts.count >= 2, let degrees = parts[0], let minutes = parts[1] else { return nil }
        var value = degrees + minutes / 60
        if parts.count >= 3, let seconds = parts[2] { value += seconds / 3600 }
        return (ref == "S" || ref == "W") ? -value : value
    }

    /// Grados decimales → "DD,MM.mmmmN" como lo espera XMP.
    static func xmpCoordinate(_ value: Double, positive: String, negative: String) -> String {
        let ref = value < 0 ? negative : positive
        let abs = Swift.abs(value)
        let degrees = Int(abs)
        let minutes = (abs - Double(degrees)) * 60
        return String(format: "%d,%.4f%@", locale: Locale(identifier: "en_US_POSIX"), degrees, minutes, ref)
    }
}
