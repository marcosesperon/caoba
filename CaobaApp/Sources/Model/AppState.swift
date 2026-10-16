import SwiftUI
import Observation
import UniformTypeIdentifiers
import CaobaCore

/// Estado compartido de la app: carpeta de origen, lista de ficheros con sus
/// marcas, destino por módulo, módulo activo y aviso de versión nueva.
@MainActor
@Observable
final class AppState {
    // MARK: Navegación
    var currentModule: Module = .processor

    // MARK: Carpeta de origen
    private(set) var sourceFolder: URL?
    private(set) var files: [ScannedFile] = []
    /// Ficheros desmarcados (por nombre) que no entran en el resultado.
    var excludedNames: Set<String> = []
    var sortMode: SortMode = .name { didSet { Task { await rescan() } } }
    var orientationFilter: OrientationFilter = .all { didSet { Task { await rescan() } } }
    private(set) var isScanning = false
    private(set) var recentFolders: [URL] = []
    private(set) var hasFolderConfig = false
    /// Sube cada vez que el usuario pulsa "Reiniciar" para que los módulos vuelvan a sus valores.
    private(set) var configResetToken = 0

    // MARK: Destino
    var destinationMode: DestinationModeChoice = .newCopy
    var destinationFolder: URL?
    var destinationFile: URL?
    /// Nombre por defecto que propone el diálogo de guardar (lo fija cada módulo).
    var destinationFileDefaultName = "caoba.jpg"
    /// Tipos que admite el diálogo de guardar del módulo activo.
    var destinationFileTypes: [UTType] = [.jpeg]

    // MARK: Trabajo en curso
    let jobRunner = JobRunner()
    let thumbnails = ThumbnailProvider()

    // MARK: Aviso de versión
    private(set) var availableUpdate: VersionCheck.Release?

    init() {
        recentFolders = RecentFolders.load()
    }

    // MARK: - Carpeta de origen

    /// Ficheros marcados, en el orden actual. Es lo que se envía al motor.
    var checkedFiles: [URL] {
        files.filter { !excludedNames.contains($0.name) }.map(\.url)
    }

    var checkedCount: Int { files.count - files.filter { excludedNames.contains($0.name) }.count }

    func chooseSourceFolder() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.prompt = L("Elegir carpeta")
        if panel.runModal() == .OK, let url = panel.url {
            Task { await selectSourceFolder(url) }
        }
    }

    func selectSourceFolder(_ url: URL) async {
        var isDir: ObjCBool = false
        guard FileManager.default.fileExists(atPath: url.path, isDirectory: &isDir), isDir.boolValue else { return }
        sourceFolder = url
        excludedNames = []
        recentFolders = RecentFolders.add(url)
        // Destino por defecto: subcarpeta "caoba" dentro del origen.
        destinationFolder = url.appendingPathComponent("caoba", isDirectory: true)
        hasFolderConfig = CaobaConfig.hasSettings(in: url)
        await rescan()
    }

    func rescan() async {
        guard let folder = sourceFolder else { files = []; return }
        isScanning = true
        defer { isScanning = false }
        do {
            files = try await FolderScanner().scan(folder: folder, sort: sortMode, orientation: orientationFilter)
        } catch {
            files = []
        }
        // Si la carpeta ha cambiado por fuera, las exclusiones de ficheros que ya no existen sobran.
        let names = Set(files.map(\.name))
        excludedNames = excludedNames.intersection(names)
    }

    /// Reordenación manual desde la lista (arrastrar).
    func moveFiles(from source: IndexSet, to destination: Int) {
        files.move(fromOffsets: source, toOffset: destination)
    }

    /// Aplica un orden guardado (por nombre); los ficheros no listados van al final.
    func applyOrder(names: [String]) {
        let index = Dictionary(uniqueKeysWithValues: names.enumerated().map { ($1, $0) })
        files.sort { (index[$0.name] ?? Int.max, $0.name) < (index[$1.name] ?? Int.max, $1.name) }
    }

    func setAllChecked(_ checked: Bool) {
        excludedNames = checked ? [] : Set(files.map(\.name))
    }

    func toggle(_ file: ScannedFile) {
        if excludedNames.contains(file.name) { excludedNames.remove(file.name) } else { excludedNames.insert(file.name) }
    }

    /// Lo llama el módulo que acaba de guardar su sección en el `.caoba`.
    func markFolderConfigSaved() {
        hasFolderConfig = true
    }

    func resetFolderConfig() {
        guard let folder = sourceFolder else { return }
        // Borra la configuración pero conserva el historial de renombrados.
        CaobaConfig.resetSettings(in: folder)
        hasFolderConfig = false
        configResetToken += 1
    }

    // MARK: - Destino

    /// Carpeta de salida efectiva para módulos de carpeta.
    var saveMode: SaveMode {
        switch destinationMode {
        case .newCopy: return .newCopy(outputFolder: destinationFolder)
        case .overwrite: return .overwrite
        }
    }

    /// Diálogo de guardar para los módulos que producen un único fichero.
    func chooseDestinationFile(contentTypes: [UTType]) {
        let panel = NSSavePanel()
        panel.allowedContentTypes = contentTypes
        panel.nameFieldStringValue = destinationFileDefaultName
        panel.directoryURL = destinationFolder ?? sourceFolder
        panel.canCreateDirectories = true
        if panel.runModal() == .OK, let url = panel.url { destinationFile = url }
    }

    /// Sufijo de fecha y hora para nombres de salida, como la app antigua.
    static func timestampSuffix() -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyyMMdd_HHmmss"
        return f.string(from: Date())
    }

    func chooseDestinationFolder() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.canCreateDirectories = true
        panel.prompt = L("Elegir destino")
        if panel.runModal() == .OK, let url = panel.url { destinationFolder = url }
    }

    // MARK: - Versión

    func checkForUpdates() async {
        availableUpdate = await VersionCheck.fetchNewerRelease(than: CaobaCoreInfo.version)
    }

    func openExternal(_ url: URL) {
        NSWorkspace.shared.open(url)
    }

    func revealInFinder(_ url: URL) {
        NSWorkspace.shared.activateFileViewerSelecting([url])
    }
}

/// Elección del usuario en la barra de destino.
enum DestinationModeChoice: String, CaseIterable, Identifiable {
    case newCopy, overwrite
    var id: String { rawValue }
}

/// Carpetas recientes en UserDefaults (máximo 5), igual que la app antigua.
enum RecentFolders {
    static let maxCount = 5

    static func load() -> [URL] {
        let paths = UserDefaults.standard.stringArray(forKey: Preferences.recentFoldersKey) ?? []
        return paths.map { URL(fileURLWithPath: $0) }.filter { FileManager.default.fileExists(atPath: $0.path) }
    }

    @discardableResult
    static func add(_ url: URL) -> [URL] {
        var list = load().filter { $0.standardizedFileURL != url.standardizedFileURL }
        list.insert(url, at: 0)
        list = Array(list.prefix(maxCount))
        UserDefaults.standard.set(list.map(\.path), forKey: Preferences.recentFoldersKey)
        return list
    }
}

/// Consulta la última release publicada en GitHub y la compara como semver
/// (la app antigua comparaba cadenas y "2.10.0" no ganaba a "2.9.0").
enum VersionCheck {
    struct Release: Equatable {
        var version: String
        var url: URL
    }

    static let releasesAPI = URL(string: "https://api.github.com/repos/marcosesperon/caoba-photo-utils/releases/latest")!

    static func fetchNewerRelease(than current: String) async -> Release? {
        var request = URLRequest(url: releasesAPI)
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        request.timeoutInterval = 10
        guard let (data, _) = try? await URLSession.shared.data(for: request),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let tag = json["tag_name"] as? String,
              let html = (json["html_url"] as? String).flatMap(URL.init(string:)) else { return nil }
        let latest = tag.hasPrefix("v") ? String(tag.dropFirst()) : tag
        return isNewer(latest, than: current) ? Release(version: latest, url: html) : nil
    }

    static func isNewer(_ candidate: String, than current: String) -> Bool {
        let a = candidate.split(separator: ".").compactMap { Int($0) }
        let b = current.split(separator: ".").compactMap { Int($0) }
        for i in 0..<max(a.count, b.count) {
            let x = i < a.count ? a[i] : 0
            let y = i < b.count ? b[i] : 0
            if x != y { return x > y }
        }
        return false
    }
}
