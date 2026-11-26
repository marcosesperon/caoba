import Foundation
import Observation
import CaobaCore

/// Los álbumes de la carpeta (o sesión) de una ventana y el que está abierto: su tira de fotos,
/// sus pliegos, el análisis de caras en segundo plano y el guardado automático.
///
/// Vive en `AppState` (no en la vista) para que el álbum siga abierto al cambiar de módulo.
@MainActor
@Observable
final class AlbumWorkspace {
    /// La ventana dueña (la pone `AppState` al crearse).
    @ObservationIgnored weak var window: AppState?

    /// Carpeta de álbumes de la carpeta de origen; `nil` sin origen.
    private(set) var library: AlbumLibrary?
    private(set) var names: [String] = []
    /// Álbum abierto.
    private(set) var name: String?
    private(set) var document: AlbumDocument?
    /// Pliego que se ve en grande.
    var selectedSpread = 0
    /// Fotos que faltan por analizar (caras) en el álbum abierto.
    private(set) var pendingAnalysis = 0
    /// Último error al guardar o al cambiar ficheros, para enseñarlo.
    var lastError: String?
    /// Se está calculando un reparto en segundo plano (mientras, no se retoca a mano).
    private(set) var isRelayouting = false

    @ObservationIgnored private var saveTask: Task<Void, Never>?
    @ObservationIgnored private var analysisTask: Task<Void, Never>?
    @ObservationIgnored private var relayoutTask: Task<Void, Never>?
    /// Sube con cada cambio de los pliegos: un reparto que acaba tarde no pisa lo que se hizo mientras.
    @ObservationIgnored private var revision = 0

    // MARK: - Carpeta

    /// Con otra carpeta de origen, se buscan sus álbumes y se abre el primero.
    func folderChanged() {
        flushSave()
        analysisTask?.cancel()
        guard let window, let source = window.sourceFolder else {
            library = nil; names = []; name = nil; document = nil
            clearUndo()
            return
        }
        let layout = window.sessions.layout
        let folder = layout.session(containing: source).map { layout.output(.album, in: $0) }
            ?? source.appendingPathComponent(SessionLayout.defaultOutputs[.album] ?? "Álbum", isDirectory: true)
        guard library?.folder != folder else { refreshPhotoInfo(); return }
        library = AlbumLibrary(folder: folder)
        reloadNames()
        open(names.first)
    }

    private func reloadNames() {
        names = library?.albumNames() ?? []
    }

    // MARK: - Abrir, crear, duplicar, renombrar, borrar

    func open(_ albumName: String?) {
        flushSave()
        analysisTask?.cancel()
        // Otro álbum: su historial empieza de cero.
        clearUndo()
        guard let library, let albumName else { name = nil; document = nil; return }
        do {
            document = Self.withCover(try AlbumDocument.load(from: library.file(of: albumName)))
            name = albumName
            selectedSpread = 0
            refreshPhotoInfo()
            analyzePending()
        } catch {
            lastError = L("No se puede abrir el álbum «\(albumName)»: \(error.localizedDescription)")
        }
    }

    /// Álbum nuevo con una copia de las medidas del tipo. Arranca sin fotos.
    func create(named requested: String, type: AlbumType) {
        guard let library else { return }
        let newName = library.uniqueName(requested.isEmpty ? type.name : requested)
        let doc = AlbumDocument(typeName: type.name, spec: type.spec)
        write(doc, as: newName)
        reloadNames()
        open(newName)
    }

    /// Copia del álbum abierto (para sacar otra versión).
    func duplicate() {
        guard let library, let name, let document else { return }
        flushSave()
        let copyName = library.uniqueName(L("\(name) copia"))
        write(document, as: copyName)
        reloadNames()
        open(copyName)
    }

    func rename(to requested: String) {
        guard let library, let name else { return }
        let target = AlbumLibrary.cleanName(requested)
        guard !target.isEmpty, target != name else { return }
        guard !names.contains(where: { $0.lowercased() == target.lowercased() && $0 != name }) else {
            lastError = L("Ya hay un álbum que se llama «\(target)».")
            return
        }
        flushSave()
        do {
            try library.rename(name, to: target)
            reloadNames()
            open(target)
        } catch {
            lastError = L("No se puede renombrar: \(error.localizedDescription)")
        }
    }

    /// Borra el álbum abierto: su carpeta va a la Papelera (con lo exportado dentro).
    func deleteCurrent() {
        guard let library, let name else { return }
        saveTask?.cancel()
        do {
            try FileManager.default.trashItem(at: library.folder(of: name), resultingItemURL: nil)
        } catch {
            lastError = L("No se puede borrar: \(error.localizedDescription)")
        }
        document = nil
        self.name = nil
        reloadNames()
        open(names.first)
    }

    // MARK: - Ajustes del álbum

    /// Cambia las medidas del álbum abierto. Si cambia algo que afecta al reparto, se rehace.
    func updateSpec(_ spec: AlbumSpec) {
        guard var doc = document, doc.spec != spec, spec.isValid else { return }
        record(L("Ajustes del álbum"))
        let relayout = doc.spec.spreads != spec.spreads || doc.spec.pageWidthMM != spec.pageWidthMM
            || doc.spec.pageHeightMM != spec.pageHeightMM || doc.spec.safetyMM != spec.safetyMM || doc.spec.spineMM != spec.spineMM
            || doc.spec.singleFirstLast != spec.singleFirstLast
        doc.spec = spec
        // A mano, el cambio espera al siguiente reparto.
        if relayout && isManual { doc.pendingLayout = true }
        document = Self.withCover(doc)
        if spec.cover == nil, selectedSpread < 0 { selectedSpread = 0 }
        if relayout && !isManual { redistribute(from: 0) } else { scheduleSave() }
    }

    // MARK: - Tira de fotos

    /// Fotos de la carpeta de origen, por nombre, para sacar su formato y su fecha.
    private var folderFiles: [String: ScannedFile] {
        Dictionary((window?.files ?? []).map { ($0.name, $0) }, uniquingKeysWith: { a, _ in a })
    }

    func contains(_ photo: String) -> Bool { document?.photos.contains(photo) ?? false }

    /// Mete o saca una foto de la tira. Al meterla va al final (el orden en que se eligen).
    func toggle(_ photo: String) {
        guard var doc = document else { return }
        record(doc.photos.contains(photo) ? L("Sacar foto") : L("Meter foto"))
        if let index = doc.photos.firstIndex(of: photo) {
            doc.photos.remove(at: index)
            // Su pliego se tiene que rehacer: fuera el candado (si lo tenía).
            if let spread = doc.spreads.firstIndex(where: { $0.photos.contains(photo) }) {
                doc.spreads[spread].locked = false
            }
        } else {
            // Si hay una casilla vacía (en el pliego que se ve o, si no, en el primero que la tenga),
            // la foto entra ahí: el usuario la dejó para eso.
            let order = doc.spreads.indices.contains(selectedSpread)
                ? [selectedSpread] + doc.spreads.indices.filter { $0 != selectedSpread } : Array(doc.spreads.indices)
            if let index = order.first(where: { i in doc.spreads[i].layout.cells.contains { $0.photo == nil } }),
               let cell = doc.spreads[index].layout.cells.first(where: { $0.photo == nil }) {
                doc.spreads[index].layout = doc.spreads[index].layout.settingPhoto(photo, in: cell.id)
                // En la tira, detrás de las fotos de ese pliego (o de los de antes, si no tenía).
                let placed = doc.spreads.prefix(index + 1).flatMap(\.photos).filter { $0 != photo }
                let after = placed.compactMap { doc.photos.firstIndex(of: $0) }.max()
                doc.photos.insert(photo, at: after.map { $0 + 1 } ?? 0)
                revision += 1
                document = doc
                refreshPhotoInfo()
                scheduleSave()
                analyzePending()
                return
            }
            // Al final de la tira: el álbum sigue el orden en que se eligen las fotos.
            doc.photos.append(photo)
        }
        stripChanged(doc)
    }

    /// Mete todas las fotos de la carpeta (o las saca si ya están todas).
    func toggleAll() {
        guard var doc = document, let window else { return }
        record(L("Todas o ninguna"))
        let all = window.files.sorted { $0.captureDate < $1.captureDate }.map(\.name)
        // «Ninguna» si ya están todas; si no, las que faltan al final, por fecha de disparo.
        doc.photos = doc.photos.count == all.count ? [] : doc.photos + all.filter { !doc.photos.contains($0) }
        stripChanged(doc)
    }

    /// Mueve fotos de la tira (arrastrando). Las que están fijadas no se mueven.
    func movePhotos(from source: IndexSet, to destination: Int) {
        guard var doc = document else { return }
        let fixed = fixedPhotos
        let movable = IndexSet(source.filter { doc.photos.indices.contains($0) && !fixed.contains(doc.photos[$0]) })
        guard !movable.isEmpty else { return }
        record(L("Ordenar la tira"))
        // A mano, soltar una foto delante de una de un pliego la mete en ese pliego. Si no puede
        // entrar, va detrás de ese pliego: nunca se queda en la tira en medio de sus fotos.
        if isManual, movable.count == 1, let from = movable.first, doc.photos.indices.contains(destination) {
            let photo = doc.photos[from], target = doc.photos[destination]
            if moveIntoSpread(photo, before: target) { return }
            if let place = location(of: target), location(of: photo)?.spread != place.spread {
                let after = doc.spreads[place.spread].photos.compactMap { doc.photos.firstIndex(of: $0) }.max() ?? destination
                doc.photos.move(fromOffsets: movable, toOffset: after + 1)
                stripChanged(doc)
                return
            }
        }
        doc.photos.move(fromOffsets: movable, toOffset: destination)
        stripChanged(doc)
    }

    /// A mano, en la tira: `photo` entra en el pliego de `target`, en su casilla; las fotos
    /// siguientes de ese pliego se corren una casilla y la última, si no cabe (no hay casillas
    /// vacías), pasa a sin colocar, justo detrás en la tira. La rejilla no cambia y el pliego queda
    /// con candado. Si `photo` venía de otro pliego, allí deja su casilla vacía. `false` si `target`
    /// no está en un pliego que se pueda tocar (entonces solo se reordena la tira).
    private func moveIntoSpread(_ photo: String, before target: String) -> Bool {
        // También en pliegos con candado: el candado es para que «Repartir» no los toque, no para
        // impedir cambiarlos a mano. Las fotos fijadas sí se respetan.
        guard var doc = document, photo != target, let place = location(of: target) else { return false }
        let index = place.spread
        let cells = doc.spreads[index].layout.cells
        // Solo las casillas sin foto fijada se corren.
        let free = cells.filter { !($0.locked && $0.photo != nil) }
        guard let slot = free.firstIndex(where: { $0.photo == target }) else { return false }
        var sequence: [String?] = free.map(\.photo)
        let source = location(of: photo)
        if source?.spread == index, let old = sequence.firstIndex(of: photo) {
            // Del mismo pliego: solo cambian de orden.
            sequence.remove(at: old)
            sequence.insert(photo, at: old < slot ? slot - 1 : slot)
        } else {
            sequence.insert(photo, at: slot)
            // Se aprovecha una casilla vacía (la primera detrás o, si no, cualquiera); si no hay,
            // la última foto se queda fuera.
            if let hole = sequence.indices.dropFirst(slot + 1).first(where: { sequence[$0] == nil })
                ?? sequence.indices.first(where: { sequence[$0] == nil }) {
                sequence.remove(at: hole)
            }
        }
        // La que se queda fuera (si se coló una foto y no había hueco).
        var displaced: String?
        if sequence.count > free.count { displaced = sequence.removeLast() ?? nil }
        var layout = doc.spreads[index].layout
        for (cell, newPhoto) in zip(free, sequence) where cell.photo != newPhoto {
            layout = layout.settingPhoto(newPhoto, in: cell.id)
        }
        doc.spreads[index].layout = layout
        doc.spreads[index].locked = true
        doc.spreads[index].manualCount = nil
        if let source, source.spread != index {
            doc.spreads[source.spread].layout = doc.spreads[source.spread].layout.settingPhoto(nil, in: source.cell)
            doc.spreads[source.spread].locked = false
        }
        // La tira: la foto delante de la de destino; la que sale, detrás de las de este pliego.
        if !doc.photos.contains(photo) { doc.photos.append(photo) }
        doc.photos.removeAll { $0 == photo }
        doc.photos.insert(photo, at: doc.photos.firstIndex(of: target) ?? doc.photos.count)
        if let out = displaced {
            doc.photos.removeAll { $0 == out }
            let last = doc.spreads[index].photos.compactMap { doc.photos.firstIndex(of: $0) }.max()
            doc.photos.insert(out, at: last.map { $0 + 1 } ?? doc.photos.count)
        }
        if displaced != nil || source.map({ $0.spread != index }) ?? false { doc.pendingLayout = true }
        revision += 1
        document = doc
        refreshPhotoInfo()
        scheduleSave()
        return true
    }

    /// Intercambia dos fotos de la tira: su sitio en la tira y su casilla en los pliegos. Si una
    /// está sin colocar, ocupa la casilla de la otra, que queda sin colocar. Las fijadas no se tocan.
    func swapPhotos(_ a: String, _ b: String) {
        guard var doc = document, !isRelayouting, a != b,
              let ia = doc.photos.firstIndex(of: a), let ib = doc.photos.firstIndex(of: b) else { return }
        let la = location(of: a), lb = location(of: b)
        let cell = { (loc: (spread: Int, cell: UUID)?) in loc.flatMap { l in doc.spreads[l.spread].layout.cells.first { $0.id == l.cell } } }
        if cell(la)?.locked == true || cell(lb)?.locked == true { return }
        record(L("Intercambiar fotos"))
        doc.photos.swapAt(ia, ib)
        // Primero se vacían las dos casillas y luego se rellenan cruzadas (pueden estar en el mismo pliego).
        if let la { doc.spreads[la.spread].layout = doc.spreads[la.spread].layout.settingPhoto(nil, in: la.cell) }
        if let lb { doc.spreads[lb.spread].layout = doc.spreads[lb.spread].layout.settingPhoto(nil, in: lb.cell) }
        if let la { doc.spreads[la.spread].layout = doc.spreads[la.spread].layout.settingPhoto(b, in: la.cell); doc.spreads[la.spread].locked = true }
        if let lb { doc.spreads[lb.spread].layout = doc.spreads[lb.spread].layout.settingPhoto(a, in: lb.cell); doc.spreads[lb.spread].locked = true }
        revision += 1
        // Si una quedó sin colocar: a mano, espera; en automático, se reparte desde donde está.
        if la == nil || lb == nil {
            if isManual {
                doc.pendingLayout = true
            } else {
                document = doc
                redistribute(from: autoStart((la ?? lb)?.spread ?? 0))
                return
            }
        }
        document = doc
        scheduleSave()
    }

    /// Fotos que no se pueden arrastrar en la tira: las de pliegos con candado y las fijadas.
    var fixedPhotos: Set<String> {
        Set(document?.spreads.flatMap { $0.locked ? $0.photos : $0.lockedPhotos } ?? [])
    }

    /// La tira ha cambiado: se rehace desde el primer pliego afectado y se analiza lo nuevo. A mano,
    /// no se mueve nada: las fotos nuevas quedan sin colocar y las que salen dejan su casilla vacía.
    private func stripChanged(_ doc: AlbumDocument) {
        let old = document?.spreads.flatMap(\.photos) ?? []
        var doc = doc
        if isManual {
            let inAlbum = Set(doc.photos)
            for i in doc.spreads.indices {
                for cell in doc.spreads[i].layout.cells {
                    guard let photo = cell.photo, !inAlbum.contains(photo) else { continue }
                    doc.spreads[i].layout = doc.spreads[i].layout.settingPhoto(nil, in: cell.id)
                    // Ese pliego se tendrá que rehacer al repartir.
                    doc.spreads[i].locked = false
                }
            }
            doc.pendingLayout = true
            document = Self.withCover(doc)
            refreshPhotoInfo()
            scheduleSave()
            analyzePending()
            return
        }
        // Un pliego con fotos que ya no están en el álbum se tiene que rehacer: fuera su candado y
        // el de esas fotos (pasa con «Ninguna», o al sacar fotos sueltas).
        let inAlbum = Set(doc.photos)
        for i in doc.spreads.indices where doc.spreads[i].photos.contains(where: { !inAlbum.contains($0) }) {
            doc.spreads[i].locked = false
            for cell in doc.spreads[i].layout.cells where cell.locked && !(cell.photo.map(inAlbum.contains) ?? false) {
                doc.spreads[i].layout = doc.spreads[i].layout.updatingCell(cell.id) { $0.locked = false }
            }
        }
        document = Self.withCover(doc)
        refreshPhotoInfo()
        // Primer sitio donde la tira ya no coincide con lo maquetado.
        let firstDiff = zip(old, doc.photos).enumerated().first { $0.element.0 != $0.element.1 }?.offset ?? min(old.count, doc.photos.count)
        redistribute(from: autoStart(spreadIndex(ofPhotoAt: firstDiff)))
        analyzePending()
    }

    /// Pliego desde el que rehacer si la tira cambia en la foto número `index`: el que la tiene
    /// y, si delante hay pliegos en blanco sin candado, desde el primero de ellos (si no, se
    /// quedarían en blanco: pasaba al marcar «Todas» después de «Ninguna»).
    private func spreadIndex(ofPhotoAt index: Int) -> Int {
        guard let doc = document else { return 0 }
        var count = 0
        var found = doc.spreads.count
        for (i, spread) in doc.spreads.enumerated() {
            count += spread.photos.count
            if index < count { found = i; break }
        }
        while found > 0, doc.spreads[found - 1].photos.isEmpty, !doc.spreads[found - 1].locked { found -= 1 }
        return found
    }

    /// Completa formato y fecha de las fotos de la tira con lo que dice la carpeta (sin tocar
    /// las caras ya analizadas). El análisis de las que salen del álbum se conserva mientras la
    /// foto siga en la carpeta: si se deshace, no hay que volver a buscar sus caras.
    private func refreshPhotoInfo() {
        guard var doc = document else { return }
        let files = folderFiles
        var info = doc.info.filter { files[$0.key] != nil }
        for photo in doc.allPhotos {
            var entry = doc.info[photo] ?? AlbumPhotoInfo(aspect: 1.5, captureDate: .distantPast)
            if let file = files[photo] {
                entry.aspect = file.size?.aspectRatio ?? entry.aspect
                entry.captureDate = file.captureDate
            }
            info[photo] = entry
        }
        doc.info = info
        if doc != document { document = doc }
    }

    // MARK: - Pliegos

    /// Rehace el reparto desde un pliego, en segundo plano (con muchas fotos tarda). Los pliegos
    /// con candado no se tocan. `clearingManual` olvida los números pedidos a mano.
    func redistribute(from start: Int, clearingManual: Bool = false) {
        guard var doc = document else { return }
        if clearingManual {
            for i in doc.spreads.indices { doc.spreads[i].manualCount = nil }
        }
        document = doc
        revision += 1
        let current = revision
        let snapshot = doc
        relayoutTask?.cancel()
        isRelayouting = true
        relayoutTask = Task { [weak self] in
            let spreads = await Task.detached(priority: .userInitiated) {
                AlbumAutoLayout.redistribute(snapshot, from: start)
            }.value
            guard let self, !Task.isCancelled, self.revision == current, var doc = self.document else { return }
            doc.spreads = spreads
            doc.pendingLayout = false
            self.document = Self.withStripInAlbumOrder(doc)
            self.isRelayouting = false
            self.selectedSpread = min(self.selectedSpread, max(0, spreads.count - 1))
            self.scheduleSave()
        }
    }

    /// Desde dónde se recalcula en automático: desde el pliego en el que se está hacia delante (los
    /// de antes no se tocan) o, si el cambio cae antes, desde ahí. Así, estando en el pliego 1
    /// mientras se eligen fotos, se ve el álbum entero tal como quedará.
    private func autoStart(_ change: Int) -> Int {
        max(0, min(change, selectedSpread))
    }

    /// Después de cada cambio, la tira sigue el orden del álbum (si están las mismas fotos).
    private static func withStripInAlbumOrder(_ doc: AlbumDocument) -> AlbumDocument {
        var doc = doc
        let order = doc.spreads.flatMap(\.photos)
        if order.count == doc.photos.count, Set(order) == Set(doc.photos) { doc.photos = order }
        return doc
    }

    /// Reparto a mano: con la casilla «Reparto automático» desmarcada y el álbum ya repartido una
    /// vez, nada se recoloca solo hasta pulsar «Repartir». (Un álbum sin pliegos se reparte solo
    /// la primera vez, para tener ya una primera versión).
    var isManual: Bool {
        guard let doc = document else { return false }
        return !doc.autoLayout && !doc.spreads.isEmpty
    }

    /// «Repartir»: todo el álbum con los pliegos que tenga, respetando candados, fotos fijadas y
    /// las fotos pedidas en cada pliego.
    func autoLayoutAll() {
        guard document != nil else { return }
        record(L("Repartir"))
        redistribute(from: 0)
    }

    /// «Quitar los números de fotos fijados a mano»: el siguiente reparto decide en todos los pliegos.
    func forgetRequestedCounts() {
        guard var doc = document else { return }
        record(L("Quitar los números fijados a mano"))
        for i in doc.spreads.indices { doc.spreads[i].manualCount = nil }
        if isManual { doc.pendingLayout = true }
        document = doc
        if isManual { scheduleSave() } else { redistribute(from: 0) }
    }

    /// Marca o desmarca «Reparto automático». Al marcarla con cambios pendientes, reparte ya.
    func setAutoLayout(_ on: Bool) {
        guard var doc = document, doc.autoLayout != on else { return }
        record(L("Reparto automático"))
        doc.autoLayout = on
        document = doc
        if on && doc.pendingLayout { redistribute(from: 0) } else { scheduleSave() }
    }

    /// El usuario pide `count` fotos en un pliego: lo recoloca y las demás corren por los siguientes.
    func setPhotoCount(_ count: Int, forSpread index: Int) {
        guard var doc = document, doc.spreads.indices.contains(index), count >= 1 else { return }
        record(L("Número de fotos"))
        // Pliego vacío: se le hace al momento una rejilla con ese número de casillas vacías, con
        // candado, para maquetarlo a mano y luego soltarle fotos.
        if doc.spreads[index].photos.isEmpty {
            let side = doc.singleSide(ofSpread: index)
            doc.spreads[index].layout = AlbumAutoLayout.emptyLayouts(count: min(count, side == nil ? 12 : 6), spec: doc.spec, side: side, limit: 1).first ?? .empty
            doc.spreads[index].manualCount = nil
            doc.spreads[index].locked = true
            revision += 1
            document = doc
            scheduleSave()
            return
        }
        // Fotos que podría coger este pliego: las suyas y las de la tira que van detrás de los
        // pliegos anteriores. Si se piden más, se ponen casillas en blanco (en automático también).
        let before = Set(doc.spreads.prefix(index).flatMap(\.photos))
        let available = doc.photos.filter { !before.contains($0) }.count
        if isManual || count > available {
            // A mano se aplica ya a este pliego: se recompone con ese número de casillas y sus fotos
            // en orden. Si hay más casillas, las de más quedan vacías; si hay menos, las fotos que
            // sobran quedan sin colocar (y entonces hay cambios pendientes). Los demás no se tocan.
            let spread = doc.spreads[index]
            let photos = spread.photos
            doc.spreads[index].layout = AlbumAutoLayout.composed(photos, cells: count, document: doc, keeping: spread,
                                                                 side: doc.singleSide(ofSpread: index))
            doc.spreads[index].manualCount = nil
            doc.spreads[index].locked = true
            if photos.count > count { doc.pendingLayout = true }
            revision += 1
            document = doc
            scheduleSave()
            return
        }
        doc.spreads[index].manualCount = count
        // Pedir otro número es pedir que se rehaga: fuera el candado del pliego.
        doc.spreads[index].locked = false
        document = doc
        redistribute(from: autoStart(index))
    }

    /// Añade un pliego al álbum (o quita el que se ve) y reparte de nuevo todo el álbum con ese
    /// número, sin tocar los pliegos con candado. Con eso el álbum pasa a tener número fijo de
    /// pliegos. (Repartir solo desde el que se ve no valía: si ese tenía candado o era el último,
    /// las fotos no tenían dónde ir y no cambiaba nada).
    func changeSpreadCount(by delta: Int) {
        guard var doc = document, !isRelayouting else { return }
        let current = doc.spreads.count
        let target = max(1, current + delta)
        guard target != current else { return }
        record(delta > 0 ? L("Añadir pliego") : L("Quitar pliego"))
        doc.spec.spreads = target
        if isManual {
            // A mano: uno en blanco detrás del que se ve, o fuera el que se ve (sus fotos quedan
            // sin colocar). Todo espera al siguiente reparto.
            if delta > 0 {
                let at = min(max(selectedSpread + 1, 0), doc.spreads.count)
                doc.spreads.insert(AlbumSpread(), at: at)
                selectedSpread = at
            } else if doc.spreads.indices.contains(selectedSpread) {
                doc.spreads.remove(at: selectedSpread)
                selectedSpread = min(selectedSpread, doc.spreads.count - 1)
            }
            doc.pendingLayout = true
            document = doc
            scheduleSave()
            return
        }
        if delta < 0, doc.spreads.indices.contains(selectedSpread) {
            // Se quita el pliego que se ve (aunque tuviera candado): sus fotos se reparten.
            doc.spreads.remove(at: selectedSpread)
        }
        document = doc
        if delta > 0 { selectedSpread = target - 1 }
        // Desde el pliego en el que se está hacia delante (los anteriores no se tocan).
        redistribute(from: autoStart(min(selectedSpread, doc.spreads.count)))
    }

    // MARK: - Portada (fase 4)

    /// Hay portada que maquetar (el álbum la lleva y ya está creada).
    var hasCover: Bool { document?.spec.cover != nil && document?.cover != nil }
    /// Primera pieza de la fila: la portada (`AlbumExport.coverIndex`) o el pliego 1.
    var firstPiece: Int { hasCover ? AlbumExport.coverIndex : 0 }

    /// Si el álbum lleva portada y aún no tiene, la crea con la primera foto a sangre en la tapa;
    /// si la tiene vacía (sin candado), le pone la primera foto en cuanto la haya.
    private static func withCover(_ doc: AlbumDocument) -> AlbumDocument {
        guard doc.spec.cover != nil else { return doc }
        var doc = doc
        if doc.cover == nil {
            doc.cover = AlbumDocument.initialCover(photo: doc.photos.first)
        } else if var cover = doc.cover, cover.photos.isEmpty, !cover.locked,
                  let first = doc.photos.first, let cell = cover.layout.cells.first {
            cover.layout = cover.layout.settingPhoto(first, in: cell.id)
            cover.layout = cover.layout.updatingCell(cell.id) { $0.bleed = true }
            doc.cover = cover
        }
        return doc
    }

    /// Una pieza del álbum: un pliego o, con `AlbumExport.coverIndex`, la portada.
    func piece(_ index: Int) -> AlbumSpread? {
        guard let doc = document else { return nil }
        if index == AlbumExport.coverIndex { return hasCover ? doc.cover : nil }
        return doc.spreads.indices.contains(index) ? doc.spreads[index] : nil
    }

    /// Medidas con las que se maqueta una pieza (la portada tiene las suyas).
    func spec(ofPiece index: Int) -> AlbumSpec? {
        guard let doc = document else { return nil }
        return index == AlbumExport.coverIndex ? doc.spec.coverSpec : doc.spec
    }

    /// Página útil si la pieza es un pliego de una página (el primero o el último).
    func singleSide(ofPiece index: Int) -> AlbumPageSide? {
        document?.singleSide(ofSpread: index)
    }

    /// Cambia una pieza dentro del documento. `false` si no existe.
    private func update(_ index: Int, in doc: inout AlbumDocument, _ change: (inout AlbumSpread) -> Void) -> Bool {
        if index == AlbumExport.coverIndex {
            guard var cover = doc.cover else { return false }
            change(&cover)
            doc.cover = cover
            return true
        }
        guard doc.spreads.indices.contains(index) else { return false }
        change(&doc.spreads[index])
        return true
    }

    /// La portada es una sola foto en la tapa (de partida, o tal como se deja con «Una sola foto
    /// en la tapa»).
    var coverIsSinglePhoto: Bool {
        guard let cover = document?.cover, case .pages(nil, let right?) = cover.layout,
              case .cell = right.node, right.area == AlbumBlock.wholeArea else { return false }
        return true
    }

    /// «Una sola foto en la tapa»: deja la portada como al principio, con su primera foto (o la
    /// primera del álbum) a sangre en la tapa. Para portadas con otra rejilla de antes.
    func resetCover() {
        guard var doc = document, doc.cover != nil else { return }
        record(L("Portada"))
        let photo = doc.cover?.photos.first ?? doc.photos.first
        doc.cover = AlbumDocument.initialCover(photo: photo)
        revision += 1
        document = doc
        scheduleSave()
    }

    /// Pone una foto en una casilla de la portada (o la quita con `nil`). Las fotos de la portada
    /// son libres: no tocan la tira ni la cascada.
    func setCoverPhoto(_ photo: String?, inCell id: UUID) {
        guard let cover = document?.cover else { return }
        setLayout(cover.layout.settingPhoto(photo, in: id), forSpread: AlbumExport.coverIndex, action: L("Portada"))
        refreshPhotoInfo()
        analyzePending()
    }

    // MARK: - Retoques a mano (fase 2)

    /// Cambia la composición de una pieza a mano (guía, encuadre, otra composición, plantilla…).
    /// Retocar un pliego le pone el candado, para que la cascada no lo deshaga.
    func setLayout(_ layout: AlbumSpreadLayout, forSpread index: Int, lock: Bool = true, action: String? = nil) {
        guard var doc = document, !isRelayouting, piece(index) != nil else { return }
        record(action ?? L("Retocar el pliego"))
        guard update(index, in: &doc, { spread in
            spread.layout = layout
            if lock { spread.locked = true }
        }) else { return }
        revision += 1
        document = doc
        scheduleSave()
    }

    func toggleSpreadLock(_ index: Int) {
        guard piece(index) != nil else { return }
        record(L("Candado"))
        guard var doc = document, update(index, in: &doc, { $0.locked.toggle() }) else { return }
        revision += 1
        document = doc
        scheduleSave()
    }

    /// Fija o suelta una foto en su casilla. Fijarla también es retocar: el pliego coge candado.
    func togglePhotoLock(cell id: UUID, inSpread index: Int) {
        guard let spread = piece(index), let cell = spread.layout.cells.first(where: { $0.id == id }) else { return }
        let layout = spread.layout.updatingCell(id) { $0.locked.toggle() }
        setLayout(layout, forSpread: index, lock: !cell.locked, action: L("Fijar foto"))
    }

    /// Quita los candados de todos los pliegos y fotos.
    func unlockAll() {
        guard var doc = document else { return }
        record(L("Quitar candados"))
        for i in doc.spreads.indices {
            doc.spreads[i].locked = false
            for cell in doc.spreads[i].layout.cells where cell.locked {
                doc.spreads[i].layout = doc.spreads[i].layout.updatingCell(cell.id) { $0.locked = false }
            }
        }
        revision += 1
        document = doc
        scheduleSave()
    }

    /// Dónde está una foto: su pliego y su casilla.
    func location(of photo: String) -> (spread: Int, cell: UUID)? {
        guard let doc = document else { return nil }
        for (i, spread) in doc.spreads.enumerated() {
            if let cell = spread.layout.cells.first(where: { $0.photo == photo }) { return (i, cell.id) }
        }
        return nil
    }

    /// Qué hacer al soltar una foto sobre una casilla que ya tiene otra.
    enum DropAction {
        /// Las dos cambian de sitio (aunque estén en pliegos distintos); no corre nada.
        case swap
        /// La nueva entra y la de antes vuelve a la tira justo detrás; los siguientes se rehacen.
        case replaceAndFlow
        /// La nueva entra y la de antes sale del álbum.
        case replaceAndRemove
    }

    /// Suelta `photo` en la casilla `cell` del pliego `index`. Si la casilla está vacía, entra sin más.
    func drop(_ photo: String, onCell cell: UUID, inSpread index: Int, action: DropAction) {
        guard var doc = document, !isRelayouting, doc.spreads.indices.contains(index),
              let target = doc.spreads[index].layout.cells.first(where: { $0.id == cell }), target.photo != photo else { return }
        record(L("Cambiar fotos de casilla"))
        let source = location(of: photo)
        let previous = target.photo
        if action == .swap, let source, let previous {
            // Las dos fotos cambian de casilla; los dos pliegos quedan retocados.
            doc.spreads[index].layout = doc.spreads[index].layout.settingPhoto(photo, in: cell)
            doc.spreads[source.spread].layout = doc.spreads[source.spread].layout.settingPhoto(previous, in: source.cell)
            doc.spreads[index].locked = true
            doc.spreads[source.spread].locked = true
            revision += 1
            document = Self.withStripInAlbumOrder(doc)
            scheduleSave()
            return
        }
        if isManual {
            // A mano: la nueva entra en la casilla; la de antes queda sin colocar (o sale del álbum)
            // y la casilla de donde venía la nueva se queda vacía. Todo espera al reparto.
            if !doc.photos.contains(photo) {
                let at = previous.flatMap { doc.photos.firstIndex(of: $0) }.map { $0 + 1 } ?? doc.photos.count
                doc.photos.insert(photo, at: at)
            }
            if action == .replaceAndRemove, let previous { doc.photos.removeAll { $0 == previous } }
            doc.spreads[index].layout = doc.spreads[index].layout.settingPhoto(photo, in: cell)
            doc.spreads[index].locked = true
            if let source {
                doc.spreads[source.spread].layout = doc.spreads[source.spread].layout.settingPhoto(nil, in: source.cell)
                doc.spreads[source.spread].locked = false
            }
            doc.pendingLayout = true
            revision += 1
            document = doc
            refreshPhotoInfo()
            scheduleSave()
            analyzePending()
            return
        }
        // Sustituir: la tira pasa a tener la nueva en el sitio de la de antes.
        var strip = doc.spreads.flatMap(\.photos)
        strip.removeAll { $0 == photo }
        if let previous, let at = strip.firstIndex(of: previous) {
            strip[at] = photo
            // La de antes vuelve a la tira justo detrás de este pliego: así los anteriores no se tocan.
            if action == .replaceAndFlow {
                let last = doc.spreads[index].photos.last { $0 != photo && $0 != previous }
                let after = max(at, last.flatMap { strip.firstIndex(of: $0) } ?? at)
                strip.insert(previous, at: after + 1)
            }
        } else {
            // Casilla vacía: la foto va detrás de la última del pliego (o al principio).
            let before = doc.spreads.prefix(index + 1).flatMap(\.photos).last { $0 != photo }
            strip.insert(photo, at: before.flatMap { strip.firstIndex(of: $0) }.map { $0 + 1 } ?? 0)
        }
        // Lo que no estuviera en el álbum se conserva al final (no debería quedar nada).
        doc.photos = strip + doc.photos.filter { !strip.contains($0) && $0 != previous && $0 != photo }
        doc.spreads[index].layout = doc.spreads[index].layout.settingPhoto(photo, in: cell)
        doc.spreads[index].locked = true
        // La casilla de donde venía se queda vacía hasta que el reparto la rehaga.
        var from = index + 1
        if let source {
            doc.spreads[source.spread].layout = doc.spreads[source.spread].layout.settingPhoto(nil, in: source.cell)
            doc.spreads[source.spread].locked = false
            from = min(from, source.spread)
        }
        document = doc
        refreshPhotoInfo()
        redistribute(from: autoStart(from))
        analyzePending()
    }

    /// Suelta una foto sobre un pliego (en una zona libre del pliego grande o en su miniatura): va a
    /// la primera casilla vacía o, si no hay, el pliego se recompone con una foto más. En la
    /// portada, la pone en la tapa.
    func dropOnSpread(_ photo: String, index: Int) {
        guard var doc = document, !isRelayouting, let target = piece(index) else { return }
        if index == AlbumExport.coverIndex {
            if let cell = target.layout.cells.first { setCoverPhoto(photo, inCell: cell.id) }
            return
        }
        guard !target.photos.contains(photo) else { return }
        if let empty = target.layout.cells.first(where: { $0.photo == nil }) {
            drop(photo, onCell: empty.id, inSpread: index, action: .replaceAndFlow)
            return
        }
        record(L("Llevar foto al pliego"))
        let source = location(of: photo)
        // La foto pasa en la tira detrás de las de este pliego.
        doc.photos.removeAll { $0 == photo }
        let last = target.photos.last.flatMap { doc.photos.firstIndex(of: $0) }
        doc.photos.insert(photo, at: last.map { $0 + 1 } ?? min(doc.photos.count, doc.spreads.prefix(index).flatMap(\.photos).count))
        doc.spreads[index].layout = AlbumAutoLayout.recomposed(target, adding: photo, document: doc, side: doc.singleSide(ofSpread: index))
        doc.spreads[index].locked = true
        doc.spreads[index].manualCount = nil
        if let source, source.spread != index {
            doc.spreads[source.spread].layout = doc.spreads[source.spread].layout.settingPhoto(nil, in: source.cell)
            doc.spreads[source.spread].locked = false
        }
        revision += 1
        if isManual || source == nil {
            if isManual { doc.pendingLayout = doc.pendingLayout || source != nil }
            document = doc
            refreshPhotoInfo()
            scheduleSave()
            analyzePending()
        } else if let source {
            // En automático, el pliego de donde venía se rehace (y lo que corra detrás).
            document = doc
            refreshPhotoInfo()
            redistribute(from: autoStart(source.spread))
            analyzePending()
        }
    }

    // MARK: - Casillas como las de una tabla

    /// Qué se le hace a una casilla.
    enum CellAction {
        case splitColumns, splitRows, merge(AlbumMergeSide), remove
    }

    /// Si se puede fusionar una casilla por ese lado (para encender o apagar la opción).
    func canMerge(cell id: UUID, side: AlbumMergeSide, inSpread index: Int) -> Bool {
        piece(index)?.layout.merging(id, side: side) != nil
    }

    func canRemove(cell id: UUID, inSpread index: Int) -> Bool {
        piece(index)?.layout.removing(id) != nil
    }

    /// Divide, fusiona o quita una casilla. El pliego queda con candado y con las casillas que se
    /// ven (sin número pendiente). La foto que sale del pliego sigue en el álbum: sin colocar en
    /// manual, o se reparte desde el pliego siguiente en automático.
    func cellAction(_ action: CellAction, cell id: UUID, inSpread index: Int) {
        guard var doc = document, !isRelayouting, index != AlbumExport.coverIndex, doc.spreads.indices.contains(index) else { return }
        let layout = doc.spreads[index].layout
        let result: (layout: AlbumSpreadLayout, displaced: String?)?
        let name: String
        switch action {
        case .splitColumns: result = (layout.splitting(id, axis: .columns), nil); name = L("Dividir casilla")
        case .splitRows: result = (layout.splitting(id, axis: .rows), nil); name = L("Dividir casilla")
        case .merge(let side): result = layout.merging(id, side: side); name = L("Fusionar casillas")
        case .remove: result = layout.removing(id); name = L("Quitar casilla")
        }
        guard let result else { return }
        record(name)
        doc.spreads[index].layout = result.layout
        doc.spreads[index].locked = true
        doc.spreads[index].manualCount = nil
        revision += 1
        if result.displaced != nil && !isManual {
            document = doc
            redistribute(from: autoStart(index + 1))
            return
        }
        if result.displaced != nil { doc.pendingLayout = true }
        document = doc
        scheduleSave()
    }

    /// «Otras composiciones» del pliego, de mejor a peor (con las mismas fotos).
    func alternatives(forSpread index: Int) -> [AlbumSpreadLayout] {
        guard let doc = document, let spread = piece(index), let spec = spec(ofPiece: index) else { return [] }
        // Pliego con casillas vacías y sin fotos: otras rejillas vacías con el mismo número.
        if spread.photos.isEmpty {
            return AlbumAutoLayout.emptyLayouts(count: spread.layout.cells.count, spec: spec, side: singleSide(ofPiece: index))
        }
        // Con fotos y alguna casilla vacía: otras con el mismo número de casillas (las vacías se mantienen).
        if spread.layout.cells.contains(where: { $0.photo == nil }) {
            return AlbumAutoLayout.composedOptions(spread.photos, cells: spread.layout.cells.count, document: doc,
                                                   keeping: spread, spec: spec, side: singleSide(ofPiece: index))
        }
        return AlbumAutoLayout.alternatives(for: spread, document: doc, spec: spec, side: singleSide(ofPiece: index))
    }

    /// Aplica una plantilla de collage a una página o al pliego entero, con sus fotos en orden.
    func apply(_ template: AlbumTemplates.Entry, to place: AlbumBlockPlace, inSpread index: Int) {
        guard let layout = piece(index)?.layout else { return }
        // Las fotos de esa parte, en orden (con casillas vacías, la plantilla también las deja vacías).
        let node: (([String]) -> AlbumNode) = { template.node(with: $0) }
        switch (place, layout) {
        case (.full, _):
            setLayout(.full(AlbumBlock(node: node(layout.cells.compactMap(\.photo)))), forSpread: index, action: L("Plantilla"))
        case (.left, .pages(let left, let right)):
            setLayout(.pages(left: AlbumBlock(node: node(left?.cells.compactMap(\.photo) ?? [])), right: right), forSpread: index, action: L("Plantilla"))
        case (.right, .pages(let left, let right)):
            setLayout(.pages(left: left, right: AlbumBlock(node: node(right?.cells.compactMap(\.photo) ?? []))), forSpread: index, action: L("Plantilla"))
        default:
            break
        }
    }

    /// Fotos que tiene cada parte del pliego, para filtrar las plantillas.
    func photoCount(of place: AlbumBlockPlace, inSpread index: Int) -> Int {
        guard let layout = piece(index)?.layout else { return 0 }
        // Se cuentan las casillas (también las vacías), para que un pliego vacío tenga plantillas.
        switch (place, layout) {
        case (.full, let layout): return layout.cells.count
        case (.left, .pages(let left, _)): return left?.cells.count ?? 0
        case (.right, .pages(_, let right)): return right?.cells.count ?? 0
        default: return 0
        }
    }

    // MARK: - Exportación (fase 3)

    /// Carpeta del álbum abierto, donde van los pliegos exportados (junto a su `.caobaalbum`).
    var exportFolder: URL? {
        guard let library, let name else { return nil }
        return library.folder(of: name)
    }

    /// Tamaño real de cada foto de la carpeta, para los ppp efectivos.
    var pixelSizes: [String: PixelSize] {
        Dictionary((window?.files ?? []).compactMap { file in file.size.map { (file.name, $0) } }, uniquingKeysWith: { a, _ in a })
    }

    /// Fotos que se amplían demasiado en estos pliegos (todos si es `nil`).
    func resolutionIssues(spreads: [Int]? = nil) -> [AlbumExport.Issue] {
        guard let document else { return [] }
        return AlbumExport.issues(in: document, pixels: pixelSizes, spreads: spreads)
    }

    /// Exporta el álbum entero o, con `only`, un pliego. Se guarda antes, y va con la hoja de
    /// progreso de siempre (que se puede cancelar).
    func export(only: Int? = nil) {
        guard let window, let document, let folder = exportFolder, let source = window.sourceFolder,
              !document.spreads.isEmpty, !isRelayouting else { return }
        flushSave()
        window.jobRunner.run(openURL: folder) { progress in
            try await AlbumExport.export(document, photos: source, to: folder, only: only, progress: progress)
        }
    }

    // MARK: - Análisis de caras

    /// Analiza en segundo plano las fotos de la tira que aún no tienen caras. Al terminar,
    /// rehace el reparto desde el primer pliego que tenía alguna sin analizar.
    private func analyzePending() {
        analysisTask?.cancel()
        guard let doc = document, let source = window?.sourceFolder else { pendingAnalysis = 0; return }
        let pending = doc.allPhotos.filter { !(doc.info[$0]?.isAnalyzed ?? false) }
        pendingAnalysis = pending.count
        guard !pending.isEmpty else { return }
        let firstPending = doc.photos.firstIndex(of: pending[0]) ?? 0
        let albumName = name
        analysisTask = Task { [weak self] in
            await withTaskGroup(of: (String, AlbumPhotoInfo).self) { group in
                var queue = pending[...]
                let parallel = max(2, ProcessInfo.processInfo.activeProcessorCount / 2)
                func addNext() {
                    guard let photo = queue.popFirst() else { return }
                    let info = doc.info[photo] ?? AlbumPhotoInfo(aspect: 1.5, captureDate: .distantPast)
                    let url = source.appendingPathComponent(photo)
                    group.addTask { (photo, AlbumAnalyzer.analyze(url, info: info)) }
                }
                for _ in 0..<parallel { addNext() }
                for await (photo, info) in group {
                    guard !Task.isCancelled else { group.cancelAll(); return }
                    self?.store(info, for: photo, album: albumName)
                    addNext()
                }
            }
            guard !Task.isCancelled, let self, self.name == albumName else { return }
            // A mano no se recoloca nada al acabar de analizar: se aprovechará en el siguiente reparto.
            guard !self.isManual else { return }
            self.redistribute(from: self.autoStart(self.spreadIndex(ofPhotoAt: firstPending)))
        }
    }

    private func store(_ info: AlbumPhotoInfo, for photo: String, album: String?) {
        guard name == album, var doc = document, doc.photos.contains(photo) else { return }
        var analyzed = info
        // La fecha y el formato son los de la carpeta, por si cambiaron mientras tanto.
        if let current = doc.info[photo] { analyzed.aspect = current.aspect; analyzed.captureDate = current.captureDate }
        doc.info[photo] = analyzed
        document = doc
        pendingAnalysis = max(0, pendingAnalysis - 1)
    }

    // MARK: - Deshacer (con el deshacer de la ventana: ⌘Z, ⇧⌘Z y Edición › Deshacer)

    /// El deshacer de la ventana (lo pone la vista del álbum). Guarda hasta 50 pasos.
    @ObservationIgnored weak var undoManager: UndoManager? {
        didSet { undoManager?.levelsOfUndo = 50 }
    }
    /// Sube con cada paso, deshacer o rehacer, para que los botones ↶ ↷ se refresquen.
    private(set) var undoToken = 0
    /// Último paso apuntado, para juntar en uno los cambios seguidos de lo mismo (teclear una
    /// medida en los ajustes, pulsar varias veces el número de fotos).
    @ObservationIgnored private var lastRecord: (action: String, date: Date)?

    /// Lo que se deshace: todo el álbum menos las caras analizadas (no cambian el álbum).
    private struct Snapshot: Sendable {
        var photos: [String]
        var spreads: [AlbumSpread]
        var spec: AlbumSpec
        var cover: AlbumSpread?
        var autoLayout: Bool
        var pendingLayout: Bool
    }

    private var snapshot: Snapshot? {
        document.map { Snapshot(photos: $0.photos, spreads: $0.spreads, spec: $0.spec, cover: $0.cover,
                                autoLayout: $0.autoLayout, pendingLayout: $0.pendingLayout) }
    }

    /// Apunta un paso antes de cambiar el álbum. Lo llama cada acción del usuario (no el reparto,
    /// que va en el mismo paso que lo provocó, ni el análisis de caras).
    private func record(_ action: String) {
        guard let undoManager, let before = snapshot else { return }
        // Lo mismo otra vez en menos de un segundo es el mismo paso.
        if let last = lastRecord, last.action == action, Date().timeIntervalSince(last.date) < 1, undoManager.canUndo {
            lastRecord = (action, Date())
            return
        }
        lastRecord = (action, Date())
        register(before, action: action, album: name)
        undoToken += 1
    }

    private func register(_ state: Snapshot, action: String, album: String?) {
        undoManager?.registerUndo(withTarget: self) { workspace in
            MainActor.assumeIsolated { workspace.restore(state, action: action, album: album) }
        }
        undoManager?.setActionName(action)
    }

    /// Vuelve a un estado guardado y deja el de ahora para rehacer (o deshacer otra vez).
    private func restore(_ state: Snapshot, action: String, album: String?) {
        guard name == album, let current = snapshot, var doc = document else { return }
        register(current, action: action, album: album)
        // Si se estaba calculando un reparto, ya no vale.
        relayoutTask?.cancel()
        isRelayouting = false
        revision += 1
        lastRecord = nil
        doc.photos = state.photos
        doc.spreads = state.spreads
        doc.spec = state.spec
        doc.cover = state.cover
        doc.autoLayout = state.autoLayout
        doc.pendingLayout = state.pendingLayout
        document = doc
        selectedSpread = max(firstPiece, min(selectedSpread, max(0, doc.spreads.count - 1)))
        refreshPhotoInfo()
        analyzePending()
        scheduleSave()
        undoToken += 1
    }

    func undo() { undoManager?.undo() }
    func redo() { undoManager?.redo() }

    /// Olvida el historial de este álbum (al abrir otro o cambiar de carpeta).
    func clearUndo() {
        undoManager?.removeAllActions(withTarget: self)
        lastRecord = nil
        undoToken += 1
    }

    // MARK: - Guardado

    private func scheduleSave() {
        saveTask?.cancel()
        saveTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(700))
            guard !Task.isCancelled else { return }
            self?.flushSave()
        }
    }

    /// Guarda ya lo pendiente (al cambiar de álbum o de carpeta).
    func flushSave() {
        saveTask?.cancel()
        saveTask = nil
        guard let document, let name else { return }
        write(document, as: name)
    }

    private func write(_ doc: AlbumDocument, as albumName: String) {
        guard let library else { return }
        do {
            try doc.save(to: library.file(of: albumName))
        } catch {
            lastError = L("No se puede guardar el álbum: \(error.localizedDescription)")
        }
    }
}
