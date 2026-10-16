import Foundation

/// Cómo ordenar los ficheros de la carpeta.
public enum SortMode: String, Sendable, Codable, CaseIterable {
    case name
    case date
}

/// Filtro por orientación de la foto.
public enum OrientationFilter: String, Sendable, Codable, CaseIterable {
    case all
    case horizontal
    case vertical
}

/// Un fichero encontrado en la carpeta, con lo que hace falta para ordenarlo y
/// filtrarlo sin volver a leerlo.
public struct ScannedFile: Sendable, Equatable, Identifiable {
    public var url: URL
    public var size: PixelSize?
    public var captureDate: Date

    public var id: URL { url }
    public var name: String { url.lastPathComponent }

    public init(url: URL, size: PixelSize?, captureDate: Date) {
        self.url = url
        self.size = size
        self.captureDate = captureDate
    }
}

/// Lista las imágenes de una carpeta (sin entrar en subcarpetas) y las ordena.
/// Equivale al `scanAndSortFiles` de la app antigua, pero leyendo solo
/// cabeceras con ImageIO en vez de decodificar.
public struct FolderScanner: Sendable {
    public var includeRaw: Bool
    public var concurrency: Int

    public init(includeRaw: Bool = false, concurrency: Int = ProcessInfo.processInfo.activeProcessorCount) {
        self.includeRaw = includeRaw
        self.concurrency = concurrency
    }

    /// Nombres de fichero candidatos, sin ocultos ni restos temporales, ordenados por nombre.
    public func listImageURLs(in folder: URL) throws -> [URL] {
        let keys: [URLResourceKey] = [.isRegularFileKey, .nameKey]
        let contents = try FileManager.default.contentsOfDirectory(
            at: folder, includingPropertiesForKeys: keys, options: [.skipsHiddenFiles]
        )
        return contents
            .filter { url in
                let name = url.lastPathComponent
                guard !name.hasPrefix(".") && !name.hasPrefix("_caoba_") else { return false }
                guard (try? url.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile) == true else { return false }
                return SupportedFormats.isImage(url, includingRaw: includeRaw)
            }
            .sorted { $0.lastPathComponent.localizedStandardCompare($1.lastPathComponent) == .orderedAscending }
    }

    /// Escanea, lee cabeceras en paralelo, filtra por orientación y ordena.
    public func scan(folder: URL, sort: SortMode = .name, orientation: OrientationFilter = .all,
                     progress: ProgressHandler? = nil) async throws -> [ScannedFile] {
        let urls = try listImageURLs(in: folder)
        guard !urls.isEmpty else { return [] }

        let semaphore = AsyncSemaphore(limit: concurrency)
        let total = urls.count

        // Leemos las cabeceras de todos los ficheros a la vez, con un tope de
        // concurrencia, y recomponemos el orden original por índice.
        let scanned: [ScannedFile] = try await withThrowingTaskGroup(of: (Int, ScannedFile).self) { group in
            for (index, url) in urls.enumerated() {
                group.addTask {
                    try Task.checkCaobaCancellation()
                    return await semaphore.run {
                        let props = ImageIOHelpers.properties(of: url)
                        let size = props.flatMap { ImageIOHelpers.displaySize(from: $0) }
                        let date = ImageIOHelpers.captureDate(from: props) ?? ImageIOHelpers.captureOrFileDate(of: url)
                        return (index, ScannedFile(url: url, size: size, captureDate: date))
                    }
                }
            }
            var results = [ScannedFile?](repeating: nil, count: total)
            var done = 0
            for try await (index, file) in group {
                results[index] = file
                done += 1
                progress?(.step(done, of: total, phase: .scanning, file: file.name))
            }
            return results.compactMap { $0 }
        }

        let filtered = scanned.filter { file in
            switch orientation {
            case .all: return true
            case .horizontal: return file.size?.isLandscape ?? true
            case .vertical: return file.size?.isPortrait ?? true
            }
        }

        switch sort {
        case .name:
            return filtered // ya viene ordenado por nombre
        case .date:
            return filtered.sorted {
                if $0.captureDate != $1.captureDate { return $0.captureDate < $1.captureDate }
                return $0.name.localizedStandardCompare($1.name) == .orderedAscending
            }
        }
    }
}
