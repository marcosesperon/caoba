import Foundation
import AppKit
import Observation
import UserNotifications
import CaobaCore

/// Estado del módulo «Descargar tarjeta»: tarjeta y opciones, el resumen de lo que falta,
/// la descarga en marcha y cómo acabó. Vive en `AppState` para que una descarga larga siga
/// aunque se cambie de módulo.
@MainActor
@Observable
final class CardImportSession {
    enum Phase: Equatable {
        /// Eligiendo tarjeta y opciones (con el resumen de lo que falta).
        case setup
        case copying
        /// Detenida entre fotos. `automatic`: la paró CAOBA porque la siguiente no cabía.
        case paused(automatic: Bool)
        case cancelling
        case finished(CardImportSummary)
    }

    // MARK: Opciones (se recuerdan)
    let diskMonitor: ExternalDiskMonitor
    /// Con otra tarjeta, lo marcado de la anterior no sirve: se vuelve a marcar lo pendiente.
    var selectedDiskID: String? { didSet { if selectedDiskID != oldValue { scheduleScan(keepingSelection: false) } } }
    var groups: Set<RecoveryFileGroup> = CardImportSession.loadGroups() {
        didSet {
            UserDefaults.standard.set(groups.map(\.rawValue), forKey: Keys.groups)
            scheduleScan()
        }
    }
    var destinationFolder: URL? = UserDefaults.standard.url(forKey: Keys.destination) {
        didSet {
            UserDefaults.standard.set(destinationFolder, forKey: Keys.destination)
            scheduleScan()
        }
    }
    var layout: CardImportLayout = CardImportLayout(rawValue: UserDefaults.standard.string(forKey: Keys.layout) ?? "") ?? .flat {
        didSet {
            UserDefaults.standard.set(layout.rawValue, forKey: Keys.layout)
            scheduleScan()
        }
    }
    var ejectWhenDone: Bool = UserDefaults.standard.bool(forKey: Keys.eject) {
        didSet { UserDefaults.standard.set(ejectWhenDone, forKey: Keys.eject) }
    }
    /// Hueco sin fotos que separa dos sesiones. Cambiarlo solo reagrupa: no relee la tarjeta.
    var sessionGap: CardSessionGap = CardSessionGap(rawValue: UserDefaults.standard.string(forKey: Keys.gap) ?? "") ?? .fourHours {
        didSet {
            UserDefaults.standard.set(sessionGap.rawValue, forKey: Keys.gap)
            regroup()
        }
    }

    // MARK: Resumen y descarga
    private(set) var phase: Phase = .setup
    /// Sesiones de la tarjeta (de la más reciente a la más antigua) y las marcadas para descargar.
    private(set) var sessions: [CardSession] = []
    private(set) var selectedSessionIDs: Set<CardSession.ID> = []
    /// Plan de toda la tarjeta: dice qué falta de cada sesión.
    private(set) var fullPlan: CardImportPlan?
    /// Lo que hay que copiar de las sesiones marcadas (`nil` mientras se calcula o sin tarjeta).
    private(set) var plan: CardImportPlan?
    private(set) var isScanning = false
    private(set) var progress = CardImportProgress()
    /// Espacio libre en el destino, durante la descarga.
    private(set) var freeSpace: Int64?
    /// Lo que hace falta libre para seguir, cuando se ha pausado por espacio.
    private(set) var neededSpace: Int64?
    /// Segundos descargando de verdad (sin pausas), para la velocidad y el tiempo restante.
    private(set) var activeSeconds: TimeInterval = 0
    private(set) var ejectError: String?
    /// La tarjeta de la última descarga (para expulsarla).
    private(set) var finishedDiskID: String?
    /// Discos que ya estaban conectados al empezar la descarga. La «siguiente tarjeta» es una que
    /// no esté aquí: así no se ofrece un disco que estaba de antes (el propio disco de destino,
    /// por ejemplo). Al sacar un disco se borra de la lista, por si se mete otra tarjeta en su ranura.
    private var disksBeforeImport: Set<String> = []

    private enum Keys {
        static let destination = "caoba.cardImport.destination"
        static let layout = "caoba.cardImport.layout"
        static let groups = "caoba.cardImport.groups"
        static let eject = "caoba.cardImport.ejectWhenDone"
        static let gap = "caoba.cardImport.sessionGap"
    }

    @ObservationIgnored private var scanTask: Task<Void, Never>?
    @ObservationIgnored private var planTask: Task<Void, Never>?
    /// Fotos leídas de la tarjeta, para reagrupar sin volver a leerla.
    @ObservationIgnored private var items: [CardItem] = []
    /// Sesiones marcadas que la próxima lectura debe respetar: al cambiar el destino, los tipos o la
    /// organización no se pierde lo que el usuario había marcado.
    @ObservationIgnored private var selectionToKeep: Set<CardSession.ID>?
    @ObservationIgnored private var control: CardImportControl?
    @ObservationIgnored private let liveProgress = ProgressBox()

    init(diskMonitor: ExternalDiskMonitor) {
        self.diskMonitor = diskMonitor
        diskMonitor.onChange.append { [weak self] in self?.disksChanged() }
    }

    // MARK: Tarjetas

    /// Solo las tarjetas montadas: se leen como ficheros normales.
    var mountedDisks: [ExternalDisk] { diskMonitor.disks.filter { !$0.mountPoints.isEmpty } }
    var selectedDisk: ExternalDisk? { mountedDisks.first { $0.id == selectedDiskID } }

    /// Volumen de la tarjeta donde están las fotos: el que tiene `DCIM` o, si no, el primero.
    var cardVolume: URL? {
        guard let disk = selectedDisk else { return nil }
        return disk.mountPoints.first { FileManager.default.fileExists(atPath: $0.appendingPathComponent("DCIM").path) }
            ?? disk.mountPoints.first
    }

    var isBusy: Bool {
        switch phase {
        case .copying, .paused, .cancelling: return true
        case .setup, .finished: return false
        }
    }

    var isPaused: Bool {
        if case .paused = phase { return true }
        return false
    }

    /// Al meter o sacar tarjetas: si no hay ninguna elegida y solo hay una, se elige sola; y se
    /// apunta si la tarjeta de la última descarga ya se ha sacado.
    func disksChanged() {
        disksBeforeImport.formIntersection(diskMonitor.disks.map(\.id))
        if selectedDisk == nil, phase == .setup, mountedDisks.count == 1 {
            selectedDiskID = mountedDisks[0].id
        } else if selectedDisk == nil, fullPlan != nil {
            clearScan()
        }
    }

    /// Otra tarjeta lista para descargar tras terminar con una: una que se haya metido después
    /// de empezar (aunque sea en la misma ranura) y que no sea el disco de destino.
    var nextCard: ExternalDisk? {
        guard case .finished = phase else { return nil }
        return mountedDisks.first { disk in
            !disksBeforeImport.contains(disk.id) && !(destinationFolder.map { RecoverySession.isOnDisk($0, disk) } ?? false)
        }
    }

    // MARK: Comprobaciones

    /// Lo que impide empezar, ya explicado. `nil` si se puede.
    var blockingProblem: String? {
        guard let disk = selectedDisk else {
            return mountedDisks.isEmpty ? L("Mete la tarjeta en el lector. Aparecerá aquí sola.") : L("Elige la tarjeta.")
        }
        guard !groups.isEmpty else { return L("Elige qué tipo de ficheros descargar.") }
        guard let destination = destinationFolder else { return L("Elige dónde descargar las fotos.") }
        if RecoverySession.isOnDisk(destination, disk) {
            return L("La carpeta de destino está en la propia tarjeta. Elige una en el Mac o en otro disco.")
        }
        if isScanning || fullPlan == nil { return L("Leyendo la tarjeta…") }
        // Sin nada de los tipos elegidos no es que esté «todo descargado»: no hay nada que bajar.
        if items.isEmpty { return L("En la tarjeta no hay ficheros de los tipos elegidos.") }
        if fullPlan?.tasks.isEmpty == true { return L("Ya está todo descargado en esta carpeta.") }
        if selectedSessionIDs.isEmpty { return L("Marca al menos una sesión.") }
        guard let plan else { return L("Leyendo la tarjeta…") }
        if plan.tasks.isEmpty { return L("Lo de las sesiones marcadas ya está descargado.") }
        return nil
    }

    /// Aviso (no impide empezar) si lo que falta no cabe en el destino.
    var spaceWarning: String? {
        guard let plan, !plan.tasks.isEmpty, let destination = destinationFolder,
              let free = CardImporter.freeSpace(at: destination), free < plan.bytesToCopy + CardImporter.spaceMargin else { return nil }
        return L("En el destino quedan \(Self.bytes(free)) libres y faltan \(Self.bytes(plan.bytesToCopy)). Cuando se llene, la descarga se pausará para que liberes espacio y sigas.")
    }

    /// Bytes por segundo, contando solo el tiempo descargando.
    var speed: Double? {
        activeSeconds >= 2 && progress.bytesDone > 0 ? Double(progress.bytesDone) / activeSeconds : nil
    }

    var remainingSeconds: TimeInterval? {
        guard let speed, speed > 0 else { return nil }
        return Double(progress.bytesTotal - progress.bytesDone) / speed
    }

    // MARK: Leer la tarjeta

    /// Vuelve a leer la tarjeta y a calcular lo que falta (al cambiar cualquier opción). Al
    /// acabar, agrupa en sesiones y prepara el plan. Las sesiones que estaban marcadas lo siguen
    /// estando; con `keepingSelection: false` (otra tarjeta, o tras descargar) se marcan las que
    /// tienen algo pendiente.
    func scheduleScan(keepingSelection: Bool = true) {
        guard phase == .setup || isFinished else { return }
        if keepingSelection, !selectedSessionIDs.isEmpty {
            selectionToKeep = selectedSessionIDs
        } else if !keepingSelection {
            selectionToKeep = nil
        }
        scanTask?.cancel()
        clearScan()
        guard let volume = cardVolume, let destination = destinationFolder, !groups.isEmpty,
              let disk = selectedDisk, !RecoverySession.isOnDisk(destination, disk) else {
            isScanning = false
            return
        }
        isScanning = true
        let (groups, layout) = (groups, layout)
        scanTask = Task {
            let (items, fullPlan) = await Task.detached {
                let items = CardScanner.scan(volume: volume, groups: groups)
                return (items, CardImportPlan.make(items: items, destination: destination, layout: layout))
            }.value
            guard !Task.isCancelled else { return }
            self.items = items
            self.fullPlan = fullPlan
            regroup()
            await planTask?.value
            self.isScanning = false
        }
    }

    private func clearScan() {
        items = []
        sessions = []
        selectedSessionIDs = []
        fullPlan = nil
        plan = nil
    }

    /// Agrupa lo leído con el hueco elegido y marca las sesiones con algo pendiente.
    private func regroup() {
        sessions = CardSessions.group(items, gap: sessionGap)
        // Si nada de lo marcado sigue existiendo (otro hueco entre sesiones…), lo pendiente.
        let kept = selectionToKeep?.intersection(sessions.map(\.id)) ?? []
        selectionToKeep = nil
        if !kept.isEmpty {
            selectedSessionIDs = kept
        } else {
            selectedSessionIDs = Set(sessions.filter { pending(in: $0) > 0 }.map(\.id))
        }
        rebuildPlan()
    }

    // MARK: Sesiones

    /// Cambia el destino (el `RAW` de la sesión del estudio o el elegido a mano). Con una descarga
    /// en marcha no se toca; si es el mismo, no se vuelve a leer la tarjeta.
    func changeDestination(to folder: URL) {
        guard !isBusy, folder.standardizedFileURL != destinationFolder?.standardizedFileURL else { return }
        destinationFolder = folder
    }

    /// Quita el destino (al pasar a «Sin sesión»). Con una descarga en marcha no se toca.
    func clearDestination() {
        guard !isBusy else { return }
        destinationFolder = nil
    }

    /// Hora de la primera foto marcada: la fecha que se propone al crear una sesión del estudio.
    var firstMarkedDate: Date? {
        sessions.filter { selectedSessionIDs.contains($0.id) }.map(\.start).min()
    }

    /// Días en los que se hicieron las fotos marcadas.
    var markedDays: Set<Date> {
        Set(sessions.filter { selectedSessionIDs.contains($0.id) }.map { Calendar.current.startOfDay(for: $0.start) })
    }

    /// Empieza en cuanto termine de leer la tarjeta y de preparar el plan, si no hay nada que lo impida.
    func startWhenReady() {
        Task {
            await scanTask?.value
            await planTask?.value
            if blockingProblem == nil { start() }
        }
    }

    /// Cuántas fotos de la sesión faltan por descargar.
    func pending(in session: CardSession) -> Int {
        guard let fullPlan else { return 0 }
        let urls = session.urls
        return fullPlan.tasks.filter { urls.contains($0.source.url) }.count
    }

    func isSelected(_ session: CardSession) -> Bool { selectedSessionIDs.contains(session.id) }

    func toggle(_ session: CardSession) {
        if selectedSessionIDs.contains(session.id) { selectedSessionIDs.remove(session.id) } else { selectedSessionIDs.insert(session.id) }
        rebuildPlan()
    }

    func selectAllSessions() {
        selectedSessionIDs = Set(sessions.map(\.id))
        rebuildPlan()
    }

    func deselectAllSessions() {
        selectedSessionIDs = []
        rebuildPlan()
    }

    /// Plan solo con las sesiones marcadas. Se rehace entero (y no filtrando el de toda la tarjeta)
    /// para que los sufijos `_2` cuenten solo con lo que de verdad se va a copiar.
    private func rebuildPlan() {
        planTask?.cancel()
        plan = nil
        guard let destination = destinationFolder, fullPlan != nil else { return }
        let selected = sessions.filter { selectedSessionIDs.contains($0.id) }.flatMap(\.items)
            .sorted { $0.file.url.path.localizedStandardCompare($1.file.url.path) == .orderedAscending }
        let layout = layout
        planTask = Task {
            let plan = await Task.detached { CardImportPlan.make(items: selected, destination: destination, layout: layout) }.value
            guard !Task.isCancelled else { return }
            self.plan = plan
        }
    }

    private var isFinished: Bool {
        if case .finished = phase { return true }
        return false
    }

    // MARK: Acciones

    func start() {
        guard blockingProblem == nil, let plan, let volume = cardVolume else { return }
        let control = CardImportControl()
        self.control = control
        progress = CardImportProgress(filesTotal: plan.tasks.count, bytesTotal: plan.bytesToCopy)
        liveProgress.value = progress
        activeSeconds = 0
        neededSpace = nil
        ejectError = nil
        finishedDiskID = selectedDiskID
        disksBeforeImport = Set(diskMonitor.disks.map(\.id))
        phase = .copying
        let box = liveProgress
        let watcher = startWatching()
        Task {
            let summary = await Task.detached {
                await CardImporter.run(plan, cardVolume: volume, control: control,
                                       onNeedsSpace: { needed in
                                           Task { @MainActor [weak self] in self?.pausedForSpace(needed) }
                                       },
                                       progress: { box.value = $0 })
            }.value
            watcher.cancel()
            await finish(summary)
        }
    }

    func pause() {
        guard phase == .copying else { return }
        control?.pause()
        phase = .paused(automatic: false)
    }

    /// Sigue donde se quedó. Si se paró por espacio, solo cuando ya hay sitio.
    func resume() {
        guard isPaused, hasEnoughSpaceToResume else { return }
        neededSpace = nil
        control?.resume()
        phase = .copying
    }

    var hasEnoughSpaceToResume: Bool {
        guard let neededSpace else { return true }
        return (freeSpace ?? 0) >= neededSpace
    }

    func cancel() {
        guard phase == .copying || isPaused else { return }
        phase = .cancelling
        control?.cancel()
    }

    /// Expulsa la tarjeta de la última descarga (o la elegida).
    func eject() {
        guard let disk = diskMonitor.disks.first(where: { $0.id == (finishedDiskID ?? selectedDiskID) }) else { return }
        ejectError = nil
        Task {
            do {
                try await DiskMounter.eject(disk)
            } catch DiskMounter.Failure.busy(let message) {
                ejectError = L("No se ha podido expulsar la tarjeta: \(message)")
            } catch {
                ejectError = error.localizedDescription
            }
        }
    }

    /// Vuelve a las opciones con los mismos ajustes; si se ha metido otra tarjeta, ya elegida.
    func reset() {
        guard !isBusy else { return }
        let next = nextCard
        phase = .setup
        progress = CardImportProgress()
        if let next {
            // Puede ser el mismo identificador (`disk4`) con otra tarjeta: se relee siempre.
            selectedDiskID = next.id
            scheduleScan(keepingSelection: false)
        } else if selectedDisk == nil {
            selectedDiskID = nil
            disksChanged()
        } else {
            scheduleScan(keepingSelection: false)
        }
    }

    /// La tarjeta nueva con los mismos ajustes, desde la pantalla final. Se descarga directamente
    /// si solo tiene una sesión pendiente; si tiene varias (puede haber encargos antiguos), se
    /// queda en las opciones para elegir cuáles.
    func downloadNextCard() {
        guard let next = nextCard else { return }
        phase = .setup
        progress = CardImportProgress()
        selectedDiskID = next.id
        scheduleScan(keepingSelection: false)
        Task {
            await scanTask?.value
            let pendingSessions = sessions.filter { pending(in: $0) > 0 }.count
            if pendingSessions == 1, blockingProblem == nil { start() }
        }
    }

    // MARK: Por dentro

    /// Cada cuarto de segundo: progreso, espacio libre y tiempo descargando.
    private func startWatching() -> Task<Void, Never> {
        Task { [weak self] in
            var last = Date()
            while !Task.isCancelled {
                try? await Task.sleep(for: .milliseconds(250))
                guard let self else { return }
                let now = Date()
                if self.phase == .copying { self.activeSeconds += now.timeIntervalSince(last) }
                last = now
                self.progress = self.liveProgress.value
                if let destination = self.destinationFolder {
                    self.freeSpace = await Task.detached { CardImporter.freeSpace(at: destination) }.value
                }
            }
        }
    }

    private func pausedForSpace(_ needed: Int64) {
        guard phase == .copying else { return }
        neededSpace = needed
        phase = .paused(automatic: true)
    }

    private func finish(_ summary: CardImportSummary) async {
        progress = liveProgress.value
        control = nil
        phase = .finished(summary)
        if ejectWhenDone, summary.ending == .completed { eject() }
        notifyIfInBackground(summary)
        disksChanged()
    }

    /// Aviso de macOS si la app no está delante. La primera vez macOS pide permiso; si no se
    /// da, no pasa nada.
    private func notifyIfInBackground(_ summary: CardImportSummary) {
        guard !NSApp.isActive else { return }
        let content = UNMutableNotificationContent()
        content.title = L("Descarga terminada")
        content.body = summary.failures.isEmpty
            ? L("\(summary.copied) copiadas, \(summary.alreadyThere) ya estaban.")
            : L("\(summary.copied) copiadas, \(summary.alreadyThere) ya estaban y \(summary.failures.count) con problemas.")
        let center = UNUserNotificationCenter.current()
        center.requestAuthorization(options: [.alert, .sound]) { granted, _ in
            guard granted else { return }
            center.add(UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil))
        }
    }

    static func bytes(_ count: Int64) -> String {
        ByteCountFormatter.string(fromByteCount: count, countStyle: .file)
    }

    private static func loadGroups() -> Set<RecoveryFileGroup> {
        guard let saved = UserDefaults.standard.stringArray(forKey: Keys.groups) else { return RecoveryFileGroup.photographerDefault }
        return Set(saved.compactMap(RecoveryFileGroup.init(rawValue:)))
    }
}

/// Último progreso que manda la descarga desde su hilo; la sesión lo recoge cada poco.
private final class ProgressBox: @unchecked Sendable {
    private let lock = NSLock()
    private var _value = CardImportProgress()
    var value: CardImportProgress {
        get { lock.withLock { _value } }
        set { lock.withLock { _value = newValue } }
    }
}
