import SwiftUI
import Observation
import UniformTypeIdentifiers
import CaobaCore

/// Estado de una ventana: módulo activo, sesión, carpeta de origen, lista de ficheros con
/// sus marcas, destino por módulo y trabajo en curso. Lo que es de toda la app (sesiones del
/// estudio, tarjetas, avisos…) está en `AppModel`, que comparten todas las ventanas.
@MainActor
@Observable
final class AppState {
    /// Lo compartido por todas las ventanas.
    let app: AppModel

    // MARK: Navegación
    /// Módulo activo. Arranca en el último usado y se recuerda al cambiar
    /// (salvo en modo captura, para no pisar lo que tenga el usuario).
    /// Cada sección empieza con el destino limpio: así un proceso no escribe sin querer
    /// donde había elegido otro (ni sobrescribe originales porque se quedó marcado).
    var currentModule: Module = Module(rawValue: UserDefaults.standard.string(forKey: Preferences.lastModuleKey) ?? "") ?? .processor {
        didSet {
            if currentModule != oldValue {
                clearDestination()
                applySessionDestination()
            }
            app.saveWindows()
            guard !isScreenshotMode else { return }
            UserDefaults.standard.set(currentModule.rawValue, forKey: Preferences.lastModuleKey)
        }
    }

    // MARK: Carpeta de origen
    private(set) var sourceFolder: URL? {
        didSet { if sourceFolder != oldValue { app.saveWindows() } }
    }
    private(set) var files: [ScannedFile] = []
    /// Ficheros desmarcados (por nombre) que no entran en el resultado.
    var excludedNames: Set<String> = []
    var sortMode: SortMode = .name { didSet { Task { await rescan() } } }
    /// Orden hecho a mano arrastrando en la lista: mientras dure, la carpeta no se reordena
    /// sola por nombre ni por fecha (el selector «Orden» enseña «Manual»).
    var isManualOrder = false
    /// El orden manual (por nombre), para volver a aplicarlo cada vez que se lee la carpeta:
    /// el proyecto puede aplicarlo antes de que termine la lectura, y esta lo pisaría.
    private var manualNames: [String] = []
    var orientationFilter: OrientationFilter = .all { didSet { Task { await rescan() } } }
    private(set) var isScanning = false
    private(set) var hasFolderConfig = false
    /// Nombres de las fotos de la carpeta al leerla (antes del filtro de orientación), para
    /// saber antes de lanzar un proceso si alguien ha borrado, renombrado o añadido fotos.
    private var knownNames: Set<String> = []
    /// Cambios encontrados al ir a lanzar un proceso; mientras no sea `nil` sale el aviso.
    var pendingFolderChanges: FolderChanges?
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

    // MARK: Sesión
    /// Sesión con la que trabaja esta ventana (`nil`, sin sesión). Se recuerda al cerrar la app.
    private(set) var activeSession: StudioSession? {
        didSet {
            // Los diálogos se abren en la sesión de la ventana de delante.
            if app.frontWindow === self { DialogFolders.sessionFolder = activeSession?.folder }
            app.saveWindows()
        }
    }
    /// La sesión activa no tiene carpeta de fotos finales: el origen se queda vacío y se avisa.
    private(set) var sessionLacksFinals = false

    /// Dónde descarga la tarjeta cuando esta ventana está delante: el `RAW` de su sesión, el elegido
    /// a mano en ella o ninguno. Descargar tarjeta es una para toda la app y toma el de la de delante.
    private(set) var cardDestination: URL?

    /// La ventana pide que se despliegue la lista de sesiones del título (ventana nueva de ⌘N).
    var requestSessionList = false

    init(app: AppModel) {
        self.app = app
    }

    // MARK: Ventana
    /// Lo que se guarda de esta ventana para volver a abrirla igual.
    var seed: WindowSeed {
        WindowSeed(sessionPath: activeSession?.folder.path,
                   folderPath: activeSession == nil ? sourceFolder?.path : nil,
                   module: currentModule.rawValue)
    }

    /// Deja la ventana como dice `seed`: módulo y sesión (si existe y no está abierta en otra
    /// ventana) o carpeta suelta, y la lista de sesiones desplegada si se pidió.
    func restore(_ seed: WindowSeed) async {
        if let id = seed.module, let module = Module(rawValue: id) { currentModule = module }
        if let path = seed.sessionPath, FileManager.default.fileExists(atPath: path),
           let session = sessions.layout.session(containing: URL(fileURLWithPath: path, isDirectory: true)),
           !app.isSessionOpen(session, besides: self) {
            await activateSession(session)
        } else if let path = seed.folderPath, FileManager.default.fileExists(atPath: path) {
            await selectSourceFolder(URL(fileURLWithPath: path, isDirectory: true), warnIfOpen: false)
        }
        if seed.showSessionList { requestSessionList = true }
    }

    /// Arranque de la primera ventana: vuelve a lo que había al cerrar la app (esta ventana se
    /// queda con la primera de la lista y devuelve las demás para abrirlas) y aplica los
    /// argumentos de las capturas. Sin lista guardada, la sesión recordada de siempre.
    func startAsFirstWindow() async -> [WindowSeed] {
        app.didLaunch = true
        // Sin sesión, la primera ventana sigue con el destino de descarga que había recordado.
        cardDestination = cardImport.destinationFolder
        // En capturas no se vuelve a nada, salvo con `--state windows.restore=1` (para probarlo).
        let restores = !isScreenshotMode || launchState["windows.restore"] != nil
        var saved = restores ? app.savedWindows() : []
        if saved.isEmpty, restores, let path = UserDefaults.standard.string(forKey: StudioSessions.activeKey) {
            saved = [WindowSeed(sessionPath: path)]
        }
        if let first = saved.first { await restore(first) }
        await applyLaunchArguments()
        app.saveWindows()
        // Cada ventana nueva lleva un id nuevo, para que se abra aparte.
        return saved.dropFirst().map { var seed = $0; seed.id = UUID(); return seed }
    }

    // MARK: Atajos a lo compartido (las vistas los usan como si fueran de la ventana)
    var sessions: StudioSessions { app.sessions }
    var cardImport: CardImportSession { app.cardImport }
    var recovery: RecoverySession { app.recovery }
    var thumbnails: ThumbnailProvider { app.thumbnails }
    var recentFolders: [URL] { app.recentFolders }
    /// Algunos módulos borran su clave al usarla, para no repetirla al volver a entrar.
    var launchState: [String: String] {
        get { app.launchState }
        set { app.launchState = newValue }
    }
    var isScreenshotMode: Bool { app.isScreenshotMode }
    func openExternal(_ url: URL) { app.openExternal(url) }
    func revealInFinder(_ url: URL) { app.revealInFinder(url) }

    // MARK: - Carpeta de origen

    /// Ficheros marcados, en el orden actual. Es lo que se envía al motor.
    var checkedFiles: [URL] {
        files.filter { !excludedNames.contains($0.name) }.map(\.url)
    }

    var checkedCount: Int { files.count - files.filter { excludedNames.contains($0.name) }.count }

    /// Solo sin sesión se puede cambiar la carpeta de origen: con sesión, el origen es siempre
    /// su carpeta de fotos finales. Lo miran «Elegir carpeta…», el menú ⌘O y el arrastrar y soltar.
    var canChangeSource: Bool { activeSession == nil }

    func chooseSourceFolder() {
        // Por si se llega desde algún sitio que no lo haya mirado.
        guard canChangeSource else { return }
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.prompt = L("Elegir carpeta")
        if panel.runFromStartFolder() == .OK, let url = panel.url {
            Task { await selectSourceFolder(url) }
        }
    }

    /// Abre una carpeta como origen. Si otra ventana ya la tiene abierta (o tiene abierta la
    /// sesión que la contiene), avisa y no la abre: las dos guardarían en ella y se pisarían.
    func selectSourceFolder(_ url: URL, warnIfOpen: Bool = true) async {
        var isDir: ObjCBool = false
        guard FileManager.default.fileExists(atPath: url.path, isDirectory: &isDir), isDir.boolValue else { return }
        guard !app.isFolderOpen(url, besides: self) else {
            if warnIfOpen { warnFolderOpenElsewhere() }
            return
        }
        // Con otra carpeta, fuera el destino anterior: si no, un Slideshow o un collage
        // hecho con la carpeta nueva podría pisar el que se generó con la de antes.
        // Sin carpeta de salida, Procesador, Marca de agua y Renombrador guardan junto al original con sufijo.
        let isNewFolder = url.standardizedFileURL != sourceFolder?.standardizedFileURL
        if isNewFolder {
            destinationFolder = nil
            destinationFile = nil
        }
        sourceFolder = url
        sessionLacksFinals = false
        // Si la carpeta está dentro de una sesión, el destino sale ya puesto.
        if isNewFolder { applySessionDestination() }
        excludedNames = []
        // Orden manual guardado en la carpeta (común a Slideshow, Collage y Contact Sheet); si no, por nombre o fecha.
        let savedOrder = FileOrderSettings.load(from: url)?.names ?? []
        isManualOrder = !savedOrder.isEmpty
        manualNames = savedOrder
        app.addRecentFolder(url)
        hasFolderConfig = CaobaConfig.hasSettings(in: url)
        await rescan()
    }

    func rescan() async {
        guard let folder = sourceFolder else { files = []; return }
        isScanning = true
        defer { isScanning = false }
        let scanner = FolderScanner()
        knownNames = Set((try? scanner.listImageURLs(in: folder))?.map(\.lastPathComponent) ?? [])
        do {
            files = try await scanner.scan(folder: folder, sort: sortMode, orientation: orientationFilter)
        } catch {
            files = []
        }
        // Con orden manual, al volver a leer la carpeta (al abrirla, al cambiar el filtro…) se mantiene.
        if isManualOrder, !manualNames.isEmpty { applyOrder(names: manualNames) }
        // Si la carpeta ha cambiado por fuera, las exclusiones de ficheros que ya no existen sobran.
        let names = Set(files.map(\.name))
        excludedNames = excludedNames.intersection(names)
    }

    /// Antes de lanzar un proceso: si la carpeta ya no coincide con la lista (fotos que
    /// faltan o nuevas), deja los cambios en `pendingFolderChanges` (sale el aviso con
    /// «Recargar») y devuelve `false`, y el proceso no se lanza. Sin carpeta, deja seguir.
    func ensureFolderUnchanged() -> Bool {
        guard let folder = sourceFolder,
              let changes = try? FolderScanner().changes(in: folder, known: knownNames),
              !changes.isEmpty else { return true }
        pendingFolderChanges = changes
        return false
    }

    /// Vuelve a leer la carpeta (botón «Recargar» y aviso). Conserva el orden manual y las
    /// fotos desmarcadas que sigan existiendo; las nuevas entran marcadas.
    func reload() async {
        pendingFolderChanges = nil
        await rescan()
    }

    /// Relee la carpeta cuando termine el trabajo en curso. Para los procesos que escriben en
    /// la carpeta de origen (sobrescribir originales, que puede cambiar la extensión): así la
    /// lista queda al día y el siguiente proceso no lo confunde con un cambio hecho por fuera.
    func rescanWhenJobFinishes() {
        Task {
            while jobRunner.isRunning { try? await Task.sleep(for: .milliseconds(200)) }
            await rescan()
        }
    }

    /// Reordenación manual desde la lista (arrastrar).
    func moveFiles(from source: IndexSet, to destination: Int) {
        files.move(fromOffsets: source, toOffset: destination)
        isManualOrder = true
        manualNames = files.map(\.name)
        saveManualOrder()
    }

    /// «Manual» elegido en el selector: el orden actual pasa a ser el manual.
    func keepCurrentOrderAsManual() {
        adoptManualOrder(names: files.map(\.name))
    }

    /// Un orden guardado (por nombre) pasa a ser el orden manual común de la carpeta. No depende de
    /// que la carpeta ya esté leída: si aún no lo está, se aplica al terminar la lectura.
    func adoptManualOrder(names: [String]) {
        guard !names.isEmpty else { return }
        isManualOrder = true
        applyOrder(names: names)
        saveManualOrder()
    }

    /// Guarda el orden manual en la carpeta, para todos los módulos.
    private func saveManualOrder() {
        guard let folder = sourceFolder else { return }
        try? FileOrderSettings(names: manualNames).save(in: folder)
        hasFolderConfig = true
    }

    /// Vuelve a ordenar por nombre o fecha, dejando el orden manual.
    func sortAutomatically(by mode: SortMode) {
        isManualOrder = false
        manualNames = []
        if let folder = sourceFolder { try? FileOrderSettings.remove(from: folder) }
        sortMode = mode   // aunque sea el mismo, `didSet` vuelve a leer la carpeta ya ordenada
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
        manualNames = names
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
        // También el orden manual: las fotos vuelven a ir por nombre o fecha.
        if isManualOrder {
            isManualOrder = false
            manualNames = []
            Task { await rescan() }
        }
    }

    // MARK: - Sesiones

    /// Activa una sesión (o ninguna). Con sesión, el origen pasa a su carpeta de fotos finales;
    /// si no la tiene, el origen se queda vacío y sale el aviso. «Sin sesión» no toca el origen.
    func activateSession(_ session: StudioSession?) async {
        let hadSession = activeSession != nil
        activeSession = session
        // En capturas y pruebas no se guarda, para no cambiar la sesión del usuario.
        if !isScreenshotMode { StudioSessions.remember(session) }
        guard let session else {
            sessionLacksFinals = false
            // Al quitar la sesión se empieza de cero: sin origen, sin destinos y sin el destino
            // de la descarga (que era el RAW de esa sesión), para no seguir trabajando en ella sin querer.
            if hadSession {
                clearSource()
                setCardDestination(nil)
            }
            return
        }
        // Las tarjetas se descargan en la carpeta de descargas de la sesión (`RAW`).
        setCardDestination(sessions.layout.downloads(of: session))
        if sessions.lacksFinals(session) {
            clearSource()
            sessionLacksFinals = true
        } else {
            await selectSourceFolder(sessions.layout.finals(of: session))
        }
    }

    /// Cambia el destino de descarga de esta ventana (al cambiar de sesión o al elegirlo a mano).
    func setCardDestination(_ folder: URL?) {
        cardDestination = folder
        applyCardDestination()
    }

    /// Si esta ventana está delante, Descargar tarjeta pasa a su destino (salvo con una descarga en marcha).
    func applyCardDestination() {
        guard app.frontWindow === self else { return }
        cardImport.changeDestination(to: cardDestination)
    }

    /// Sesión sin carpeta de fotos finales: la crea dentro de la sesión y la abre como origen.
    /// Si no se puede crear (permisos, disco…), el error sube para que la barra lo enseñe.
    func createSessionFinals() async throws {
        guard let session = activeSession else { return }
        try sessions.createFinals(for: session)
        await selectSourceFolder(sessions.layout.finals(of: session))
    }

    /// Con otra estructura de sesiones (otro formato de fecha…) la activa puede dejar de
    /// reconocerse o cambiar de nombre: se vuelve a buscar con la estructura nueva.
    func sessionLayoutChanged() {
        if let current = activeSession { activeSession = sessions.layout.session(containing: current.folder) }
    }

    /// Deja la app sin carpeta de origen (y sin el destino que dependía de ella).
    private func clearSource() {
        sourceFolder = nil
        files = []
        excludedNames = []
        knownNames = []
        hasFolderConfig = false
        destinationFolder = nil
        destinationFile = nil
    }

    /// Si el origen está dentro de una sesión (la activa u otra elegida a mano), rellena el
    /// destino del módulo con el nombre de Ajustes. Solo se llama con el destino recién vaciado.
    func applySessionDestination() {
        guard let source = sourceFolder, let session = sessions.layout.session(containing: source) else { return }
        let layout = sessions.layout
        switch currentModule {
        case .processor:
            setSessionFolder(layout.output(.processor, in: session))
        case .watermark:
            setSessionFolder(layout.output(.watermark, in: session))
        case .collage:
            setSessionFolder(layout.output(.collage, in: session))
        case .renamer:
            // El Renombrador trabaja en el sitio (se puede deshacer desde el historial).
            destinationMode = .overwrite
        case .slideshow:
            destinationFile = layout.output(.slideshow, in: session, fileExtension: "mp4")
        case .contactSheet:
            destinationFile = layout.output(.contactSheet, in: session, fileExtension: "jpg")
        case .metadata, .qr, .shutterCount, .cardImport, .recovery:
            break
        }
    }

    /// Carpeta de salida de la sesión, salvo que coincida con el origen (las fotos se mezclarían).
    private func setSessionFolder(_ folder: URL) {
        guard !isSourceFolder(folder) else { return }
        destinationMode = .newCopy
        destinationFolder = folder
    }

    // MARK: - Destino

    /// Vacía la carpeta y el fichero de destino y vuelve a «Copias nuevas».
    func clearDestination() {
        destinationFolder = nil
        destinationFile = nil
        destinationMode = .newCopy
    }

    /// Con «Copias nuevas» hay que elegir carpeta: ya no se guarda junto a los originales.
    var needsDestinationFolder: Bool {
        destinationMode == .newCopy && destinationFolder == nil
    }

    /// Si `url` es la carpeta de origen (rutas normalizadas y con los enlaces resueltos).
    /// Ningún módulo guarda ahí: lo nuevo se mezclaría con las fotos de la lista.
    func isSourceFolder(_ url: URL) -> Bool {
        guard let sourceFolder else { return false }
        return url.standardizedFileURL.resolvingSymlinksInPath().path
            == sourceFolder.standardizedFileURL.resolvingSymlinksInPath().path
    }

    /// Aviso cuando la carpeta elegida ya está abierta en otra ventana.
    private func warnFolderOpenElsewhere() {
        let alert = NSAlert()
        alert.messageText = L("Esta carpeta ya está abierta en otra ventana")
        alert.informativeText = L("Cada carpeta solo puede estar abierta en una ventana, para que no se pisen lo que guardan en ella (el montaje del Slideshow, el orden de las fotos…).")
        alert.alertStyle = .warning
        alert.runModal()
    }

    /// Aviso cuando se elige la carpeta de origen como destino.
    private func warnSourceFolderNotAllowed() {
        let alert = NSAlert()
        alert.messageText = L("No se puede guardar en la carpeta de las fotos")
        alert.informativeText = L("Lo que se genere se mezclaría con las fotos originales. Elige otra carpeta o crea una subcarpeta dentro de esta.")
        alert.alertStyle = .warning
        alert.runModal()
    }

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
        // Si ya hay un fichero puesto (p. ej. el de la sesión), se parte de él.
        panel.nameFieldStringValue = destinationFile?.lastPathComponent ?? destinationFileDefaultName
        panel.directoryURL = destinationFile?.deletingLastPathComponent() ?? destinationFolder ?? sourceFolder ?? DialogFolders.startFolder
        panel.canCreateDirectories = true
        guard panel.runKeepingFolder() == .OK, let url = panel.url else { return }
        if isSourceFolder(url.deletingLastPathComponent()) {
            warnSourceFolderNotAllowed()
        } else {
            destinationFile = url
        }
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
        guard panel.runFromStartFolder() == .OK, let url = panel.url else { return }
        if isSourceFolder(url) {
            warnSourceFolderNotAllowed()
        } else {
            destinationFolder = url
        }
    }

    // MARK: - Argumentos de arranque

    /// Para capturas y pruebas: `--folder <ruta>` abre una carpeta, `--module <id>`
    /// elige la sección y `--window <ancho>x<alto>` fija el tamaño de la ventana.
    func applyLaunchArguments(_ arguments: [String] = CommandLine.arguments) async {
        func value(after flag: String) -> String? {
            guard let i = arguments.firstIndex(of: flag), arguments.indices.contains(i + 1) else { return nil }
            return arguments[i + 1]
        }
        // `--state clave=valor` y el modo captura ya los ha leído `AppModel` al arrancar.
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
        // Para pruebas y capturas: `--state session.activate=<carpeta de una sesión>` la activa
        // sin guardarla (en modo captura no cambia la sesión del usuario); con `none`, sin sesión.
        if let path = launchState["session.activate"] {
            if path == "none" {
                await activateSession(nil)
            } else if let session = sessions.layout.session(containing: URL(fileURLWithPath: path, isDirectory: true)) {
                await activateSession(session)
                // `--state session.clear=1`: justo después la quita, para ver cómo queda «Sin sesión».
                if launchState["session.clear"] != nil { await activateSession(nil) }
            }
        }
        // Para pruebas: `--state presets.export=/ruta.json` e `--state presets.import=/ruta.json`.
        if let path = launchState["presets.export"] { try? PresetStore.shared.exportData().write(to: URL(fileURLWithPath: path)) }
        if let path = launchState["presets.import"], let data = try? Data(contentsOf: URL(fileURLWithPath: path)) { _ = try? PresetStore.shared.importData(data) }
        // Para probar las novedades: `--state demo.lastSeen=3.0.1` simula esa última versión vista.
        if let seen = launchState["demo.lastSeen"] {
            UserDefaults.standard.set(seen, forKey: Preferences.lastSeenVersionKey)
            app.isScreenshotMode = false
            app.checkWhatsNew()
            app.isScreenshotMode = arguments.contains("--screenshot")
        }
        // Para probar la actualización: `--state update.target=/ruta/CAOBA.app` sustituye esa copia
        // (en lugar de la app en ejecución) por el DMG de la última release y no relanza.
        if let target = launchState["update.target"] {
            Updater.shared.testTarget = URL(fileURLWithPath: target)
        }
        // `--state update.force=1` enseña la banda con la última release aunque no sea más nueva,
        // y `update.auto=1` lanza la actualización al momento.
        if launchState["update.force"] != nil, let latest = await VersionCheck.fetchLatest() {
            app.availableUpdate = latest
            app.showUpdateBanner = true
            if launchState["update.auto"] != nil { Updater.shared.update(to: latest) }
        }
        // Para capturar la banda y la hoja sin esperar a que exista una versión nueva ni a los 7 días.
        if let version = launchState["demo.update"] {
            app.availableUpdate = VersionCheck.Release(version: version, url: URL(string: "https://github.com/marcosesperon/caoba/releases/latest")!)
            app.showUpdateBanner = true
        }
        if launchState["demo.donation"] != nil {
            app.showDonationPrompt = true
        }
    }

    /// `--screenshot <png>` guarda la ventana tras `--delay` segundos (8 por defecto) y cierra.
    /// Va aparte de `applyLaunchArguments` para que antes se abran las demás ventanas guardadas.
    func captureIfRequested(_ arguments: [String] = CommandLine.arguments) async {
        func value(after flag: String) -> String? {
            guard let i = arguments.firstIndex(of: flag), arguments.indices.contains(i + 1) else { return nil }
            return arguments[i + 1]
        }
        // Se dibuja la propia jerarquía de vistas, así no hace falta permiso de grabación de pantalla.
        if let output = value(after: "--screenshot") {
            // Con varias ventanas, la app tiene que estar activa para que la de delante pase a
            // activa (y CAOBA sepa cuál es) como cuando se usa; sin tocar cuál está delante.
            if launchState["capture.windows"] != nil { NSApp.activate(ignoringOtherApps: true) }
            let delay = value(after: "--delay").flatMap(Double.init) ?? 8
            try? await Task.sleep(for: .seconds(delay))
            // Una vista invisible se queda con el foco del teclado para que el
            // primer control de la ventana no salga con el anillo rojo.
            // Con `capture.windows` se deja delante la que esté (la última abierta), como al usarla.
            if launchState["capture.windows"] == nil, let window = NSApp.windows.first(where: { $0.isVisible }), let content = window.contentView {
                // La app tiene que estar delante: si no, la ventana sale con los controles apagados.
                NSApp.activate(ignoringOtherApps: true)
                window.makeKeyAndOrderFront(nil)
                let sink = FocusSink(frame: .zero)
                content.addSubview(sink)
                window.makeFirstResponder(sink)
                try? await Task.sleep(for: .milliseconds(300))
            }
            // `--state demo.settings=1`: abre Ajustes y captura esa ventana en lugar de la principal.
            if launchState["demo.settings"] != nil {
                let main = NSApp.windows.first(where: { $0.isVisible })
                // En macOS 14 SwiftUI no atiende `showSettingsWindow:`; se pulsa el «Ajustes…» (⌘,) del menú de la app.
                if let appMenu = NSApp.mainMenu?.items.first?.submenu,
                   let index = appMenu.items.firstIndex(where: { $0.keyEquivalent == "," }) {
                    appMenu.performActionForItem(at: index)
                }
                try? await Task.sleep(for: .milliseconds(800))
                let settings = NSApp.windows.first { $0.isVisible && $0 !== main && $0.frame.width > 100 }
                Self.captureMainWindow(to: URL(fileURLWithPath: output), window: settings)
                NSApp.terminate(nil)
                return
            }
            // `--state capture.windows=1`: todas las ventanas, de izquierda a derecha, en `<png>-1.png`, `-2.png`…
            if launchState["capture.windows"] != nil {
                let windows = NSApp.windows.filter { $0.isVisible && $0.frame.width > 400 && !($0 is NSPanel) }.sorted { $0.frame.minX < $1.frame.minX }
                let base = URL(fileURLWithPath: output).deletingPathExtension().path
                // Cada ventana sola (sin lo que tenga encima), y la de delante también con sus hojas y globos.
                for (i, window) in windows.enumerated() {
                    Self.captureMainWindow(to: URL(fileURLWithPath: "\(base)-\(i + 1).png"), window: window)
                }
                if let key = NSApp.keyWindow {
                    Self.captureMainWindow(to: URL(fileURLWithPath: "\(base)-delante.png"), includingSheets: true, window: key)
                }
                NSApp.terminate(nil)
                return
            }
            Self.captureMainWindow(to: URL(fileURLWithPath: output), includingSheets: launchState["demo.donation"] != nil || launchState["demo.lastSeen"] != nil || launchState["capture.sheets"] != nil)
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

    static func captureMainWindow(to url: URL, includingSheets: Bool = false, window chosen: NSWindow? = nil) {
        guard let window = chosen ?? NSApp.windows.first(where: { $0.isVisible }) else { return }
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
