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
    /// Estado inicial pedido por línea de comandos con `--state clave=valor`
    /// (solo para capturas: pestaña del Collage, texto del QR, PNG de la marca…).
    var launchState: [String: String] = [:]

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

    // MARK: Aviso de versión y donativo
    private(set) var availableUpdate: VersionCheck.Release?
    /// Banda «Nueva versión disponible»: se enseña hasta que el usuario la cierra (se recuerda por versión).
    var showUpdateBanner = false
    /// Hoja de donativo: al arrancar, como mucho cada 7 días.
    var showDonationPrompt = false
    /// True cuando la app arranca solo para hacer una captura: sin hojas ni avisos.
    private(set) var isScreenshotMode = false

    static let donationURL = URL(string: "https://buymeacoffee.com/marcosesperon")!
    static let websiteURL = URL(string: "https://caobafoto.com/")!
    /// Días entre dos avisos de donativo (la misma cadencia que la app antigua).
    static let donationInterval: TimeInterval = 7 * 24 * 3600

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

    /// Reordena las fotos marcadas según `order` dejando las no marcadas en su sitio.
    /// Lo usa el reparto por contenido, que decide el orden de las fotos de cada collage.
    func reorderCheckedFiles(to order: [URL]) {
        let position = Dictionary(uniqueKeysWithValues: order.enumerated().map { ($1, $0) })
        let checkedSlots = files.indices.filter { !excludedNames.contains(files[$0].name) }
        let sortedChecked = checkedSlots.map { files[$0] }.sorted { (position[$0.url] ?? Int.max) < (position[$1.url] ?? Int.max) }
        for (slot, file) in zip(checkedSlots, sortedChecked) { files[slot] = file }
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

    // MARK: - Argumentos de arranque

    /// Para capturas y pruebas: `--folder <ruta>` abre una carpeta, `--module <id>`
    /// elige la sección y `--window <ancho>x<alto>` fija el tamaño de la ventana.
    func applyLaunchArguments(_ arguments: [String] = CommandLine.arguments) async {
        func value(after flag: String) -> String? {
            guard let i = arguments.firstIndex(of: flag), arguments.indices.contains(i + 1) else { return nil }
            return arguments[i + 1]
        }
        isScreenshotMode = arguments.contains("--screenshot")
        // `--state clave=valor` (repetible) deja preparado un módulo con contenido.
        // Va lo primero porque el módulo recordado puede estar ya en pantalla.
        for (i, argument) in arguments.enumerated() where argument == "--state" && arguments.indices.contains(i + 1) {
            let pair = arguments[i + 1].split(separator: "=", maxSplits: 1).map(String.init)
            if pair.count == 2 { launchState[pair[0]] = pair[1] }
        }
        if let size = value(after: "--window") {
            let parts = size.lowercased().split(separator: "x").compactMap { Double($0) }
            // La ventana tarda un instante en existir con su tamaño inicial.
            try? await Task.sleep(for: .milliseconds(600))
            if parts.count == 2, let window = NSApp.windows.first(where: { $0.isVisible }) {
                let frame = window.frameRect(forContentRect: NSRect(x: 0, y: 0, width: parts[0], height: parts[1]))
                window.setFrame(frame, display: true)
                window.center()
            }
        }
        if let id = value(after: "--module"), let module = Module(rawValue: id) {
            currentModule = module
        }
        if let path = value(after: "--folder") {
            await selectSourceFolder(URL(fileURLWithPath: path))
        }
        // Para pruebas: `--state presets.export=/ruta.json` e `--state presets.import=/ruta.json`.
        if let path = launchState["presets.export"] { try? PresetStore.shared.exportData().write(to: URL(fileURLWithPath: path)) }
        if let path = launchState["presets.import"], let data = try? Data(contentsOf: URL(fileURLWithPath: path)) { _ = try? PresetStore.shared.importData(data) }
        // Para probar la actualización: `--state update.target=/ruta/CAOBA.app` sustituye esa copia
        // (en lugar de la app en ejecución) por el DMG de la última release y no relanza.
        if let target = launchState["update.target"] {
            Updater.shared.testTarget = URL(fileURLWithPath: target)
        }
        // `--state update.force=1` enseña la banda con la última release aunque no sea más nueva,
        // y `update.auto=1` lanza la actualización al momento.
        if launchState["update.force"] != nil, let latest = await VersionCheck.fetchLatest() {
            availableUpdate = latest
            showUpdateBanner = true
            if launchState["update.auto"] != nil { Updater.shared.update(to: latest) }
        }
        // Para capturar la banda y la hoja sin esperar a que exista una versión nueva ni a los 7 días.
        if let version = launchState["demo.update"] {
            availableUpdate = VersionCheck.Release(version: version, url: URL(string: "https://github.com/marcosesperon/caoba/releases/latest")!)
            showUpdateBanner = true
        }
        if launchState["demo.donation"] != nil {
            showDonationPrompt = true
        }
        // `--screenshot <png>` guarda la ventana tras `--delay` segundos (8 por defecto) y cierra.
        // Se dibuja la propia jerarquía de vistas, así no hace falta permiso de grabación de pantalla.
        if let output = value(after: "--screenshot") {
            let delay = value(after: "--delay").flatMap(Double.init) ?? 8
            try? await Task.sleep(for: .seconds(delay))
            // Una vista invisible se queda con el foco del teclado para que el
            // primer control de la ventana no salga con el anillo rojo.
            if let window = NSApp.windows.first(where: { $0.isVisible }), let content = window.contentView {
                // La app tiene que estar delante: si no, la ventana sale con los controles apagados.
                NSApp.activate(ignoringOtherApps: true)
                window.makeKeyAndOrderFront(nil)
                let sink = FocusSink(frame: .zero)
                content.addSubview(sink)
                window.makeFirstResponder(sink)
                try? await Task.sleep(for: .milliseconds(300))
            }
            Self.captureMainWindow(to: URL(fileURLWithPath: output), includingSheets: launchState["demo.donation"] != nil || launchState["capture.sheets"] != nil)
            NSApp.terminate(nil)
        }
    }

    /// Imagen de una ventana propia vía `CGWindowListCreateImage`. Está marcada como
    /// obsoleta en macOS 14 pero sigue funcionando y, a diferencia de ScreenCaptureKit,
    /// no pide permiso de grabación de pantalla; se resuelve por `dlsym` para no
    /// arrastrar el aviso de obsolescencia en cada compilación.
    private static func windowImage(of window: NSWindow, includingSheets: Bool) -> CGImage? {
        typealias CreateImage = @convention(c) (CGRect, UInt32, UInt32, UInt32) -> Unmanaged<CGImage>?
        guard let symbol = dlsym(dlopen(nil, RTLD_NOW), "CGWindowListCreateImage") else { return nil }
        let create = unsafeBitCast(symbol, to: CreateImage.self)
        var options: CGWindowListOption = .optionIncludingWindow
        var bounds = CGRect.null
        if includingSheets {
            // Las hojas son ventanas aparte por encima de la principal: se piden las que
            // están sobre ella dentro de su marco (coordenadas de pantalla con origen arriba).
            options.insert(.optionOnScreenAboveWindow)
            let screenHeight = NSScreen.screens.first?.frame.height ?? 0
            let frame = window.frame
            bounds = CGRect(x: frame.minX, y: screenHeight - frame.maxY, width: frame.width, height: frame.height)
        }
        let imageOptions: CGWindowImageOption = [.boundsIgnoreFraming, .bestResolution]
        return create(bounds, options.rawValue, CGWindowID(window.windowNumber), imageOptions.rawValue)?.takeRetainedValue()
    }

    static func captureMainWindow(to url: URL, includingSheets: Bool = false) {
        guard let window = NSApp.windows.first(where: { $0.isVisible }) else { return }
        // Primero la imagen real de la ventana (incluye los fondos translúcidos);
        // si el sistema no la da, se dibuja la jerarquía de vistas.
        if let cg = Self.windowImage(of: window, includingSheets: includingSheets), cg.width > 10 {
            let rep = NSBitmapImageRep(cgImage: cg)
            try? rep.representation(using: .png, properties: [:])?.write(to: url)
            return
        }
        guard let view = window.contentView?.superview ?? window.contentView,
              let rep = view.bitmapImageRepForCachingDisplay(in: view.bounds) else { return }
        view.cacheDisplay(in: view.bounds, to: rep)
        try? rep.representation(using: .png, properties: [:])?.write(to: url)
    }

    // MARK: - Versión

    func checkForUpdates() async {
        availableUpdate = await VersionCheck.fetchNewerRelease(than: CaobaCoreInfo.version)
        guard let update = availableUpdate, !isScreenshotMode else { return }
        // Si el usuario ya cerró la banda de esta versión, no se insiste; el enlace del pie se queda.
        let dismissed = UserDefaults.standard.string(forKey: Preferences.updateDismissedVersionKey)
        showUpdateBanner = dismissed != update.version
    }

    func dismissUpdateBanner() {
        if let version = availableUpdate?.version {
            UserDefaults.standard.set(version, forKey: Preferences.updateDismissedVersionKey)
        }
        showUpdateBanner = false
    }

    /// Un segundo después de arrancar pide apoyo al proyecto, si nunca se hizo
    /// o han pasado al menos 7 días desde la última vez.
    func scheduleDonationPrompt() async {
        guard !isScreenshotMode else { return }
        let lastShown = UserDefaults.standard.double(forKey: Preferences.donationLastShownKey)
        let now = Date().timeIntervalSince1970
        guard lastShown == 0 || now - lastShown >= Self.donationInterval else { return }
        try? await Task.sleep(for: .seconds(1))
        UserDefaults.standard.set(now, forKey: Preferences.donationLastShownKey)
        showDonationPrompt = true
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
        /// Página de la release.
        var url: URL
        /// El DMG adjunto, si lo hay.
        var dmg: URL?
    }

    static let releasesAPI = URL(string: "https://api.github.com/repos/marcosesperon/caoba/releases/latest")!

    static func fetchNewerRelease(than current: String) async -> Release? {
        guard let latest = await fetchLatest(), isNewer(latest.version, than: current) else { return nil }
        return latest
    }

    /// Última release publicada, sea más nueva o no.
    static func fetchLatest() async -> Release? {
        var request = URLRequest(url: releasesAPI)
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        request.timeoutInterval = 10
        guard let (data, _) = try? await URLSession.shared.data(for: request),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let tag = json["tag_name"] as? String,
              let html = (json["html_url"] as? String).flatMap(URL.init(string:)) else { return nil }
        let latest = tag.hasPrefix("v") ? String(tag.dropFirst()) : tag
        let assets = json["assets"] as? [[String: Any]] ?? []
        let dmg = assets.first { ($0["name"] as? String)?.lowercased().hasSuffix(".dmg") == true }
            .flatMap { $0["browser_download_url"] as? String }.flatMap(URL.init(string:))
        return Release(version: latest, url: html, dmg: dmg)
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

/// Vista vacía que acepta el foco; solo se usa al hacer capturas desde línea de comandos.
private final class FocusSink: NSView {
    override var acceptsFirstResponder: Bool { true }
}
