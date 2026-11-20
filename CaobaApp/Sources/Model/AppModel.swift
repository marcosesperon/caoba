import SwiftUI
import Observation
import CaobaCore

/// Lo que es de toda la app y no de una ventana: las sesiones del estudio (estructura y
/// lista), las tarjetas y discos conectados con Descargar tarjeta y Recuperar fotos (el
/// lector es uno), las carpetas recientes, el aviso de versión, las novedades y el donativo,
/// y los argumentos de arranque de las capturas. Cada ventana tiene su `AppState` y todas
/// comparten este.
@MainActor
@Observable
final class AppModel {
    // MARK: Compartido por todas las ventanas
    /// Tarjetas y discos externos conectados, compartidos por «Recuperar fotos» y «Descargar tarjeta».
    let disks = ExternalDiskMonitor()
    /// Recuperar fotos y descargar tarjeta: aquí y no en la vista, para que un trabajo largo
    /// siga al cambiar de módulo (y, con varias ventanas, se vea el mismo en todas).
    let recovery: RecoverySession
    let cardImport: CardImportSession
    let thumbnails = ThumbnailProvider()
    /// Estructura de sesiones de Ajustes y lista de la carpeta raíz. La sesión activa es de cada ventana.
    let sessions = StudioSessions()
    private(set) var recentFolders: [URL] = []

    // MARK: Aviso de versión y donativo
    var availableUpdate: VersionCheck.Release?
    /// Banda «Nueva versión disponible»: se enseña hasta que el usuario la cierra (se recuerda por versión).
    var showUpdateBanner = false
    /// Hoja de donativo: al arrancar, como mucho cada 7 días.
    var showDonationPrompt = false
    /// Hoja «Novedades»: tras actualizar, con las versiones que tocan; desde Ayuda, todas.
    var whatsNewSections: [Changelog.Section]?
    var whatsNewTitle: LocalizedStringKey = "Novedades de CAOBA"

    // MARK: Arranque
    /// Estado inicial pedido por línea de comandos con `--state clave=valor`
    /// (solo para capturas: pestaña del Collage, texto del QR, PNG de la marca…).
    var launchState: [String: String]
    /// True cuando la app arranca solo para hacer una captura: sin hojas ni avisos.
    var isScreenshotMode: Bool

    // MARK: Ventanas
    /// Ventanas abiertas, en el orden en que se abrieron. Sirve para que una sesión o una
    /// carpeta no se abra en dos ventanas y para volver a abrirlas todas al arrancar.
    private(set) var openWindows: [AppState] = []
    /// La ventana de delante: la que enseña las novedades y el donativo, y donde se abren los diálogos.
    private(set) var frontWindow: AppState?
    /// La primera ventana ya hizo lo de arrancar (argumentos, ventanas guardadas, avisos).
    var didLaunch = false
    /// Al salir de la app no se toca la lista guardada: las ventanas se cierran, pero se quiere volver a ellas.
    @ObservationIgnored private var isTerminating = false
    static let windowsKey = "caoba.windows"

    static let donationURL = URL(string: "https://buymeacoffee.com/marcosesperon")!
    static let websiteURL = URL(string: "https://caobafoto.com/")!
    /// Días entre dos avisos de donativo (la misma cadencia que la app antigua).
    static let donationInterval: TimeInterval = 7 * 24 * 3600

    init(arguments: [String] = CommandLine.arguments) {
        isScreenshotMode = arguments.contains("--screenshot")
        // `--state clave=valor` (repetible) deja preparado un módulo con contenido.
        var state: [String: String] = [:]
        for (i, argument) in arguments.enumerated() where argument == "--state" && arguments.indices.contains(i + 1) {
            let pair = arguments[i + 1].split(separator: "=", maxSplits: 1).map(String.init)
            if pair.count == 2 { state[pair[0]] = pair[1] }
        }
        launchState = state
        recentFolders = RecentFolders.load()
        recovery = RecoverySession(diskMonitor: disks)
        cardImport = CardImportSession(diskMonitor: disks)
        NotificationCenter.default.addObserver(forName: NSApplication.willTerminateNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.isTerminating = true }
        }
    }

    // MARK: - Ventanas

    func register(_ window: AppState) {
        guard !openWindows.contains(where: { $0 === window }) else { return }
        openWindows.append(window)
        if frontWindow == nil { bringToFront(window) }
        saveWindows()
    }

    func unregister(_ window: AppState) {
        openWindows.removeAll { $0 === window }
        if frontWindow === window { frontWindow = openWindows.last }
        saveWindows()
    }

    /// Una ventana pasa al frente: sus diálogos se abren en su sesión.
    func bringToFront(_ window: AppState) {
        frontWindow = window
        DialogFolders.sessionFolder = window.activeSession?.folder
    }

    /// Si la sesión está abierta en otra ventana distinta de `window`.
    func isSessionOpen(_ session: StudioSession, besides window: AppState) -> Bool {
        openWindows.contains { $0 !== window && $0.activeSession?.folder.standardizedFileURL == session.folder.standardizedFileURL }
    }

    /// Si otra ventana tiene abierta esa carpeta, o una sesión que la contiene: las dos guardarían
    /// en ella (el montaje del Slideshow, el orden de las fotos…) y se pisarían.
    func isFolderOpen(_ folder: URL, besides window: AppState) -> Bool {
        let path = folder.standardizedFileURL.resolvingSymlinksInPath().path
        return openWindows.contains { other in
            guard other !== window else { return false }
            if let source = other.sourceFolder, source.standardizedFileURL.resolvingSymlinksInPath().path == path { return true }
            if let session = other.activeSession {
                let sessionPath = session.folder.standardizedFileURL.resolvingSymlinksInPath().path
                return path == sessionPath || path.hasPrefix(sessionPath + "/")
            }
            return false
        }
    }

    /// Guarda qué ventanas hay abiertas (sesión o carpeta y módulo de cada una), para volver a
    /// ellas al abrir la app. No en capturas ni al salir.
    func saveWindows() {
        guard !isScreenshotMode, !isTerminating, didLaunch else { return }
        if let data = try? JSONEncoder().encode(openWindows.map(\.seed)) {
            UserDefaults.standard.set(data, forKey: Self.windowsKey)
        }
    }

    /// Las ventanas que había al cerrar la app la última vez.
    func savedWindows() -> [WindowSeed] {
        UserDefaults.standard.data(forKey: Self.windowsKey)
            .flatMap { try? JSONDecoder().decode([WindowSeed].self, from: $0) } ?? []
    }

    /// Apunta una carpeta recién abierta en cualquier ventana.
    func addRecentFolder(_ url: URL) {
        recentFolders = RecentFolders.add(url)
    }

    // MARK: - Versión

    func checkForUpdates() async {
        availableUpdate = await VersionCheck.fetchNewerRelease(than: CaobaCoreInfo.version)
        guard availableUpdate != nil, !isScreenshotMode else { return }
        showUpdateBanner = true
    }

    /// La × solo oculta la banda hasta cerrar la app: en el siguiente arranque
    /// vuelve a salir mientras siga habiendo una versión más nueva.
    func dismissUpdateBanner() {
        showUpdateBanner = false
    }

    /// Tras una actualización enseña las novedades de las versiones que se han
    /// saltado; en una instalación nueva solo apunta la versión. Devuelve si se enseñó.
    @discardableResult
    func checkWhatsNew() -> Bool {
        guard !isScreenshotMode else { return false }
        let current = CaobaCoreInfo.version
        let defaults = UserDefaults.standard
        defer { defaults.set(current, forKey: Preferences.lastSeenVersionKey) }
        guard let lastSeen = defaults.string(forKey: Preferences.lastSeenVersionKey), VersionCheck.isNewer(current, than: lastSeen) else { return false }
        let sections = Changelog.bundled().sections(after: lastSeen, upTo: current)
        guard !sections.isEmpty else { return false }
        whatsNewTitle = "Novedades desde la versión \(lastSeen)"
        whatsNewSections = sections
        return true
    }

    /// Desde el menú Ayuda: todo el historial.
    func showAllWhatsNew() {
        whatsNewTitle = "Novedades de CAOBA"
        whatsNewSections = Changelog.bundled().sections
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
