import Foundation
import CoreGraphics
import ImageIO
import UniformTypeIdentifiers
@testable import CaobaCore

/// Imágenes sintéticas para los tests: nada de fotos reales en el repo.
enum TestImages {

    /// Carpeta temporal limpia para cada test.
    static func makeTempFolder() throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("caoba-tests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    /// Imagen con cuatro cuadrantes de colores distintos: rojo arriba-izquierda,
    /// verde arriba-derecha, azul abajo-izquierda, blanco abajo-derecha. Sirve
    /// para comprobar orientaciones y recortes mirando píxeles.
    static func quadrants(width: Int, height: Int) -> CGImage {
        let ctx = CGContext.rgba(width: width, height: height)!
        let hw = CGFloat(width) / 2, hh = CGFloat(height) / 2
        // Core Graphics tiene el origen abajo: "arriba" es y = hh...height.
        ctx.setFillColor(CGColor(red: 1, green: 0, blue: 0, alpha: 1)); ctx.fill(CGRect(x: 0, y: hh, width: hw, height: hh))
        ctx.setFillColor(CGColor(red: 0, green: 1, blue: 0, alpha: 1)); ctx.fill(CGRect(x: hw, y: hh, width: hw, height: hh))
        ctx.setFillColor(CGColor(red: 0, green: 0, blue: 1, alpha: 1)); ctx.fill(CGRect(x: 0, y: 0, width: hw, height: hh))
        ctx.setFillColor(CGColor(red: 1, green: 1, blue: 1, alpha: 1)); ctx.fill(CGRect(x: hw, y: 0, width: hw, height: hh))
        return ctx.makeImage()!
    }

    /// Imagen de un solo color, opcionalmente con alfa (para marcas de agua).
    static func solid(width: Int, height: Int, r: CGFloat, g: CGFloat, b: CGFloat, a: CGFloat = 1) -> CGImage {
        let ctx = CGContext.rgba(width: width, height: height)!
        ctx.setFillColor(CGColor(red: r, green: g, blue: b, alpha: a))
        ctx.fill(CGRect(x: 0, y: 0, width: width, height: height))
        return ctx.makeImage()!
    }

    /// Color (r, g, b) de un píxel con coordenadas arriba-izquierda.
    static func pixel(_ image: CGImage, x: Int, y: Int) -> (r: Int, g: Int, b: Int) {
        let ctx = CGContext.rgba(width: image.width, height: image.height)!
        ctx.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
        let data = ctx.data!.assumingMemoryBound(to: UInt8.self)
        // El contexto guarda las filas de arriba a abajo.
        let offset = y * ctx.bytesPerRow + x * 4
        return (Int(data[offset]), Int(data[offset + 1]), Int(data[offset + 2]))
    }

    static func isRed(_ p: (r: Int, g: Int, b: Int)) -> Bool { p.r > 200 && p.g < 60 && p.b < 60 }
    static func isGreen(_ p: (r: Int, g: Int, b: Int)) -> Bool { p.r < 60 && p.g > 200 && p.b < 60 }
    static func isBlue(_ p: (r: Int, g: Int, b: Int)) -> Bool { p.r < 60 && p.g < 60 && p.b > 200 }
    static func isWhite(_ p: (r: Int, g: Int, b: Int)) -> Bool { p.r > 200 && p.g > 200 && p.b > 200 }

    /// Escribe una imagen en disco con las propiedades EXIF/TIFF indicadas.
    @discardableResult
    static func write(_ image: CGImage, to url: URL, format: OutputFormat = .jpeg, quality: Double = 1.0,
                      orientation: CGImagePropertyOrientation = .up, exif: [CFString: Any] = [:],
                      tiff: [CFString: Any] = [:], gps: [CFString: Any] = [:]) throws -> URL {
        guard let dest = CGImageDestinationCreateWithURL(url as CFURL, format.utType.identifier as CFString, 1, nil) else {
            throw CaobaError.cannotWriteImage(url.lastPathComponent)
        }
        var props: [CFString: Any] = [kCGImageDestinationLossyCompressionQuality: quality]
        if orientation != .up { props[kCGImagePropertyOrientation] = orientation.rawValue }
        if !exif.isEmpty { props[kCGImagePropertyExifDictionary] = exif }
        if !tiff.isEmpty { props[kCGImagePropertyTIFFDictionary] = tiff }
        if !gps.isEmpty { props[kCGImagePropertyGPSDictionary] = gps }
        CGImageDestinationAddImage(dest, image, props as CFDictionary)
        guard CGImageDestinationFinalize(dest) else { throw CaobaError.cannotWriteImage(url.lastPathComponent) }
        return url
    }

    /// Crea un JPEG de cuadrantes con nombre y fecha EXIF.
    @discardableResult
    static func makePhoto(in folder: URL, name: String, width: Int = 400, height: Int = 300,
                          date: String? = nil, orientation: CGImagePropertyOrientation = .up,
                          make: String? = nil, model: String? = nil, lens: String? = nil) throws -> URL {
        var exif: [CFString: Any] = [:]
        if let date { exif[kCGImagePropertyExifDateTimeOriginal] = date }
        if let lens { exif[kCGImagePropertyExifLensModel] = lens }
        var tiff: [CFString: Any] = [:]
        if let make { tiff[kCGImagePropertyTIFFMake] = make }
        if let model { tiff[kCGImagePropertyTIFFModel] = model }
        let url = folder.appendingPathComponent(name)
        return try write(quadrants(width: width, height: height), to: url,
                         format: OutputFormat.matching(extensionOf: url),
                         orientation: orientation, exif: exif, tiff: tiff)
    }
}
