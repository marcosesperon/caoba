import SwiftUI
import CaobaCore

/// Módulo Álbum: maqueta de álbumes por pliegos. Arriba el álbum abierto (con sus ajustes),
/// a la izquierda las fotos de la carpeta para meterlas o sacarlas, en el centro el pliego en
/// grande y abajo la fila de pliegos y la tira de fotos en el orden del álbum.
struct AlbumView: View {
    @Environment(AppState.self) private var appState
    @Environment(\.openSettings) private var openSettings
    /// El deshacer de la ventana: el álbum apunta en él cada cambio (⌘Z, ⇧⌘Z, Edición › Deshacer).
    @Environment(\.undoManager) private var undoManager
    @State private var types = AlbumTypeStore.shared
    @AppStorage("album.bottomHeight") private var bottomHeight = 260.0

    @State private var showNewAlbum = false
    @State private var showSettings = false
    @State private var renameText: String?
    @State private var confirmDelete = false

    private var album: AlbumWorkspace { appState.album }

    var body: some View {
        Group {
            if album.document == nil && album.names.isEmpty {
                if types.types.isEmpty { noTypes } else { noAlbums }
            } else if let document = album.document {
                VStack(spacing: 12) {
                    header(document)
                        .caobaPanel(padding: 8)
                    // Cada zona en su bloque, como en los demás módulos, y ocupando todo el alto
                    // aunque el álbum esté vacío.
                    // Abajo caben siempre la fila de pliegos y la tira enteras (si no, se montaban
                    // sobre el bloque de arriba).
                    BottomSplit(bottomHeight: $bottomHeight, minTop: 300, minBottom: 250) {
                        HSplitView {
                            AlbumPhotoPicker()
                                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                                .caobaPanel()
                                .padding(.trailing, 6)
                                .frame(minWidth: 230, idealWidth: 270, maxWidth: 380)
                            AlbumSpreadEditor(document: document)
                                .frame(maxWidth: .infinity, maxHeight: .infinity)
                                .caobaPanel()
                                .padding(.leading, 6)
                                .frame(minWidth: 440)
                        }
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                    } bottom: {
                        AlbumBottomBlock(document: document)
                            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                            .caobaPanel()
                            .clipped()
                    }
                    AlbumExportBar(document: document)
                }
            } else {
                // Hay álbumes pero ninguno abierto (falló al abrir).
                noAlbums
            }
        }
        .sheet(isPresented: $showNewAlbum) { NewAlbumSheet() }
        .alert("Renombrar álbum", isPresented: Binding(get: { renameText != nil }, set: { if !$0 { renameText = nil } })) {
            TextField("Nombre", text: Binding(get: { renameText ?? "" }, set: { renameText = $0 }))
            Button("Renombrar") { if let text = renameText { album.rename(to: text) } }
            Button("Cancelar", role: .cancel) {}
        }
        .confirmationDialog(Text("¿Borrar el álbum «\(album.name ?? "")»?"), isPresented: $confirmDelete) {
            Button("Mover a la Papelera", role: .destructive) { album.deleteCurrent() }
        } message: {
            Text("Su carpeta, con lo exportado dentro, va a la Papelera.")
        }
        .alert("Álbum", isPresented: Binding(get: { album.lastError != nil }, set: { if !$0 { album.lastError = nil } })) {
            Button("Aceptar", role: .cancel) {}
        } message: {
            Text(album.lastError ?? "")
        }
        .onDisappear { album.flushSave() }
        .onAppear { album.undoManager = undoManager }
        .onChange(of: undoManager) { album.undoManager = undoManager }
        .task { await applyLaunchState() }
    }

    /// Para capturas y pruebas: `--state album.demo=1` crea un álbum con todas las fotos (si la
    /// carpeta no tiene ninguno) con el primer tipo, y `--state album.spread=N` va al pliego N.
    private func applyLaunchState() async {
        let state = appState.launchState
        // Primero, que la carpeta esté leída (sus fotos y su carpeta de álbumes).
        for _ in 0..<40 where album.library == nil || appState.files.isEmpty { try? await Task.sleep(for: .milliseconds(250)) }
        if state["album.demo"] != nil, album.names.isEmpty, let type = types.types.first {
            album.create(named: "Alex & Sofía", type: type)
            // `album.demo=empty` lo deja sin fotos (para ver el álbum recién creado).
            if state["album.demo"] != "empty" { album.toggleAll() }
        }
        // `album.pick=N`: marca una a una las N últimas fotos de la carpeta, de la más nueva a la más
        // antigua (para ver que la tira sigue el orden en que se eligen).
        if let n = state["album.pick"].flatMap(Int.init) {
            for file in appState.files.sorted(by: { $0.captureDate > $1.captureDate }).prefix(n) {
                album.toggle(file.name)
                for _ in 0..<40 where album.isRelayouting { try? await Task.sleep(for: .milliseconds(100)) }
            }
        }
        if let spread = state["album.spread"].flatMap(Int.init) {
            // Se espera al análisis de caras, que rehace el reparto al acabar.
            for _ in 0..<40 where album.pendingAnalysis > 0 { try? await Task.sleep(for: .milliseconds(250)) }
            // `album.spread=0` es la portada.
            album.selectedSpread = spread == 0 ? AlbumExport.coverIndex : max(0, spread - 1)
        }
    }

    // MARK: - Sin tipos o sin álbumes

    private var noTypes: some View {
        ContentUnavailableView {
            Label("Primero, un tipo de álbum", systemImage: "book")
        } description: {
            Text("Los tipos de álbum guardan las medidas del laboratorio: tamaño de página, sangrado, margen de seguridad, franja del lomo y número de pliegos. Se crean en Ajustes › Álbumes.")
        } actions: {
            Button("Abrir Ajustes › Álbumes") {
                UserDefaults.standard.set("albums", forKey: Preferences.settingsTabKey)
                openSettings()
            }
            .buttonStyle(.borderedProminent)
        }
    }

    private var noAlbums: some View {
        ContentUnavailableView {
            Label("Sin álbumes en esta sesión", systemImage: "book")
        } description: {
            Text("Crea un álbum a partir de uno de tus tipos. Cada sesión puede tener varios: por localizaciones, por personas o versiones.")
        } actions: {
            Button("Nuevo álbum…") { showNewAlbum = true }
                .buttonStyle(.borderedProminent)
        }
    }

    // MARK: - Cabecera

    private func header(_ document: AlbumDocument) -> some View {
        HStack(spacing: 10) {
            Picker("Álbum", selection: Binding(get: { album.name }, set: { album.open($0) })) {
                ForEach(album.names, id: \.self) { Text($0).tag(Optional($0)) }
            }
            .labelsHidden()
            .fixedSize()
            Button { showNewAlbum = true } label: { Image(systemName: "plus") }
                .help("Nuevo álbum")
            undoButtons
            Menu {
                Button("Duplicar") { album.duplicate() }
                Button("Renombrar…") { renameText = album.name }
                Divider()
                Button("Borrar…", role: .destructive) { confirmDelete = true }
            } label: {
                Image(systemName: "ellipsis.circle")
            }
            .menuStyle(.borderlessButton)
            .fixedSize()
            Button { showSettings = true } label: { Label("Ajustes del álbum", systemImage: "slider.horizontal.3") }
                .popover(isPresented: $showSettings, arrowEdge: .bottom) {
                    AlbumSettingsPopover(spec: document.spec, typeName: document.typeName) { album.updateSpec($0) }
                }
            Text(summary(document))
                .font(.caption).foregroundStyle(.secondary)
                .lineLimit(1)
            Spacer()
            // Del álbum entero: cómo se reparte y el botón para repartirlo.
            layoutControls(document)
            if album.isRelayouting {
                ProgressView().controlSize(.small)
                Text("Repartiendo…").font(.caption).foregroundStyle(.secondary)
            } else if album.pendingAnalysis > 0 {
                ProgressView().controlSize(.small)
                Text("Analizando caras: faltan \(album.pendingAnalysis)")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
    }

    /// «Reparto automático» y «Repartir»: son del álbum entero, así que van en su cabecera.
    private func layoutControls(_ document: AlbumDocument) -> some View {
        HStack(spacing: 10) {
            Toggle("Reparto automático", isOn: Binding(get: { document.autoLayout }, set: { album.setAutoLayout($0) }))
                .toggleStyle(.checkbox)
                .fixedSize()
                .help("Marcada, cada cambio vuelve a repartir el álbum solo. Desmarcada, lo maquetado no se mueve hasta pulsar «Repartir».")
            // Con cambios sin repartir, un punto naranja delante (dentro del menú no se ve).
            if document.pendingLayout {
                Circle().fill(Color.orange).frame(width: 8, height: 8)
                    .help("Hay cambios sin repartir")
            }
            Menu {
                Button("Quitar los números de fotos fijados a mano") { album.forgetRequestedCounts() }
                Button("Quitar todos los candados") { album.unlockAll() }
            } label: {
                Label("Repartir", systemImage: "wand.and.stars")
            } primaryAction: {
                album.autoLayoutAll()
            }
            .fixedSize()
            .help("Reparte todo el álbum con sus pliegos, respetando los candados, las fotos fijadas y las fotos pedidas en cada pliego")
        }
        .disabled(album.isRelayouting || document.spreads.isEmpty && document.photos.isEmpty)
    }

    /// ↶ ↷: deshacer y rehacer el último cambio del álbum (lo mismo que ⌘Z y ⇧⌘Z).
    private var undoButtons: some View {
        // `undoToken` cambia con cada paso: así los botones se encienden y apagan a tiempo.
        let _ = album.undoToken
        let canUndo = undoManager?.canUndo ?? false
        let canRedo = undoManager?.canRedo ?? false
        return HStack(spacing: 2) {
            Button { album.undo() } label: { Image(systemName: "arrow.uturn.backward") }
                .disabled(!canUndo || album.isRelayouting)
                .help(canUndo ? (undoManager?.undoMenuItemTitle ?? "") : L("Nada que deshacer"))
            Button { album.redo() } label: { Image(systemName: "arrow.uturn.forward") }
                .disabled(!canRedo || album.isRelayouting)
                .help(canRedo ? (undoManager?.redoMenuItemTitle ?? "") : L("Nada que rehacer"))
        }
    }

    /// «30 × 30 cm · 12 pliegos · 64 fotos».
    private func summary(_ document: AlbumDocument) -> String {
        let size = "\(AlbumSpecPreview.cm(document.spec.pageWidthMM)) × \(AlbumSpecPreview.cm(document.spec.pageHeightMM)) cm"
        return L("\(size) · \(document.spreads.count) pliegos · \(document.photos.count) fotos")
    }
}

// MARK: - Álbum nuevo

/// Nombre y tipo del álbum nuevo.
private struct NewAlbumSheet: View {
    @Environment(AppState.self) private var appState
    @Environment(\.dismiss) private var dismiss
    @State private var types = AlbumTypeStore.shared
    @State private var name = ""
    @State private var typeID: UUID?

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Nuevo álbum").font(.headline)
            LabeledRow("Nombre") {
                TextField("", text: $name, prompt: Text("Por ejemplo, Novios"))
                    .labelsHidden().frame(width: 240)
            }
            LabeledRow("Tipo") {
                Picker("", selection: $typeID) {
                    ForEach(types.types) { Text($0.name).tag(Optional($0.id)) }
                }
                .labelsHidden().frame(width: 240)
            }
            Text("El álbum se queda con una copia de las medidas del tipo: si luego cambias el tipo, este álbum no cambia.")
                .font(.caption).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            HStack {
                Spacer()
                Button("Cancelar", role: .cancel) { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button("Crear") {
                    if let type = types.type(id: typeID) {
                        appState.album.create(named: name.trimmingCharacters(in: .whitespaces), type: type)
                    }
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
                .disabled(typeID == nil)
            }
        }
        .padding(20)
        .frame(width: 440)
        .onAppear { typeID = typeID ?? types.types.first?.id }
    }
}

// MARK: - Ajustes del álbum

/// Las medidas del álbum abierto (empiezan siendo una copia de las de su tipo).
private struct AlbumSettingsPopover: View {
    @State var spec: AlbumSpec
    let typeName: String
    let onChange: (AlbumSpec) -> Void

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 10) {
                Text("Ajustes de este álbum").font(.headline)
                if !typeName.isEmpty {
                    Text("Creado con el tipo «\(typeName)». Los cambios solo afectan a este álbum.")
                        .font(.caption).foregroundStyle(.secondary)
                }
                AlbumSpecForm(spec: $spec)
            }
            .padding(16)
        }
        .frame(width: 600, height: 560)
        .onChange(of: spec) { onChange(spec) }
    }
}

// MARK: - Fotos de la carpeta

/// Las fotos de la carpeta: pulsando una entra o sale del álbum (entra en su sitio por fecha).
private struct AlbumPhotoPicker: View {
    @Environment(AppState.self) private var appState
    /// Foto abierta en grande (con la lupa del centro de la miniatura).
    @State private var viewerTarget: PhotoViewerTarget?
    /// Miniatura con el ratón encima, para enseñar la lupa.
    @State private var hovered: String?

    var body: some View {
        let album = appState.album
        let inAlbum = album.document?.photos.count ?? 0
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("Fotos de la carpeta").font(.headline)
                Spacer()
                Button(inAlbum == appState.files.count && inAlbum > 0 ? "Ninguna" : "Todas") { album.toggleAll() }
                    .controlSize(.small)
            }
            Text("\(inAlbum) de \(appState.files.count) en el álbum · pulsa una foto para meterla o sacarla, o arrástrala a una casilla")
                .font(.caption).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            ScrollView {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 74), spacing: 6)], spacing: 6) {
                    ForEach(Array(appState.files.enumerated()), id: \.element.id) { index, file in
                        let chosen = album.contains(file.name)
                        ThumbnailView(url: file.url, maxPixelSize: 200, displaySize: 74)
                            .opacity(chosen ? 1 : 0.55)
                            // En el centro, con el ratón encima, una lupa que la abre en grande.
                            .overlay {
                                if hovered == file.name {
                                    Image(systemName: "magnifyingglass")
                                        .font(.system(size: 13, weight: .semibold))
                                        .foregroundStyle(.white)
                                        .padding(7)
                                        .background(.black.opacity(0.55), in: Circle())
                                        .contentShape(Circle())
                                        .onTapGesture { viewerTarget = PhotoViewerTarget(index: index) }
                                        .help("Ver en grande")
                                }
                            }
                            .onHover { inside in hovered = inside ? file.name : (hovered == file.name ? nil : hovered) }
                            .overlay(alignment: .topTrailing) {
                                Image(systemName: chosen ? "checkmark.circle.fill" : "circle")
                                    .foregroundStyle(chosen ? Color.accentColor : .white)
                                    .shadow(radius: 1)
                                    .padding(3)
                            }
                            .contentShape(Rectangle())
                            .onTapGesture { album.toggle(file.name) }
                            // Se puede soltar en una casilla del pliego (para sustituir una foto).
                            .draggable((chosen ? "album:" : "folder:") + file.name)
                            .help(file.name)
                    }
                }
            }
        }
        .sheet(item: $viewerTarget) { target in
            // En el visor, la casilla mete o saca la foto del álbum.
            PhotoViewerSheet(target: target, inclusion: ("En el álbum",
                                                         { appState.album.contains($0.name) },
                                                         { appState.album.toggle($0.name) }))
        }
    }
}

// MARK: - Pliego en grande

/// El pliego elegido, que se retoca a mano, y sus controles: navegación y número de fotos
/// arriba; candado, otras composiciones, igualar, ajustar a las fotos y plantillas abajo.
private struct AlbumSpreadEditor: View {
    @Environment(AppState.self) private var appState
    let document: AlbumDocument

    @State private var selectedCell: UUID?
    @State private var croppingCell: UUID?
    /// «Otras composiciones» del pliego que se ve (se calculan al pedirlas).
    @State private var alternatives: [AlbumSpreadLayout] = []
    @State private var alternativesKey = ""
    @State private var alternativeIndex = -1
    @State private var showTemplates = false

    var body: some View {
        let album = appState.album
        // La pieza que se ve: un pliego o la portada (`AlbumExport.coverIndex`, delante del 1).
        let index = max(album.firstPiece, min(album.selectedSpread, max(0, document.spreads.count - 1)))
        let isCover = index == AlbumExport.coverIndex
        VStack(spacing: 8) {
            if document.spreads.isEmpty && !isCover {
                ContentUnavailableView {
                    Label("Sin fotos en el álbum", systemImage: "photo.on.rectangle.angled")
                } description: {
                    Text("Marca a la izquierda las fotos que van al álbum. CAOBA las reparte en pliegos según su formato, sus caras y el momento en que se hicieron.")
                }
            } else {
                let spread = album.piece(index) ?? AlbumSpread()
                let spec = album.spec(ofPiece: index) ?? document.spec
                let glued = document.singleSide(ofSpread: index).map { $0 == .left ? AlbumPageSide.right : .left }
                SpreadEditorCanvas(spreadIndex: index, spread: spread, document: document, spec: spec, glued: glued,
                                   selectedCell: $selectedCell, croppingCell: $croppingCell)
                    .padding(.horizontal, 8)
                    .disabled(album.isRelayouting)
                // Los controles del pliego, en su propio bloque (con otro fondo y borde) para que no
                // se mezclen con el pliego y se lean bien; nunca se recortan por abajo.
                VStack(alignment: .leading, spacing: 8) {
                    navigation(spread: spread, index: index)
                    Divider()
                    if isCover {
                        coverTools
                    } else {
                        tools(spread: spread, index: index, spec: spec)
                    }
                    statusLine(spread: spread, isCover: isCover)
                }
                .caobaPanel(padding: 10, fill: Color(nsColor: .underPageBackgroundColor), border: Color(nsColor: .separatorColor))
                .fixedSize(horizontal: false, vertical: true)
            }
        }
        .onChange(of: album.selectedSpread) { selectedCell = nil; croppingCell = nil }
        .task { await applyLaunchState() }
    }

    /// Para capturas y pruebas, después de `album.spread`: `--state album.alternative=N` aplica la
    /// composición N de la lista, `album.lockPhoto=1` fija la primera foto y `album.crop=1` entra
    /// en el encuadre de la primera casilla (con `album.zoom=1.6`, ampliada).
    private func applyLaunchState() async {
        let state = appState.launchState
        guard state["album.alternative"] != nil || state["album.crop"] != nil || state["album.lockPhoto"] != nil
                || state["album.bleed"] != nil || state["album.export"] != nil || state["album.retoggle"] != nil
                || state["album.undo"] != nil || state["album.manualtest"] != nil || state["album.emptytest"] != nil || state["album.celltest"] != nil || state["album.striptest"] != nil || state["album.count"] != nil || state["album.addone"] != nil || state["album.swaptest"] != nil else { return }
        // Se espera a que acaben el análisis y el reparto (y a que `album.spread` elija el pliego).
        try? await Task.sleep(for: .seconds(2))
        for _ in 0..<60 where appState.album.pendingAnalysis > 0 || appState.album.isRelayouting { try? await Task.sleep(for: .milliseconds(250)) }
        try? await Task.sleep(for: .milliseconds(500))
        let album = appState.album
        let index = album.selectedSpread
        guard album.piece(index) != nil else { return }
        if let n = state["album.alternative"].flatMap(Int.init) {
            let options = album.alternatives(forSpread: index)
            if options.indices.contains(n - 1) { album.setLayout(options[n - 1], forSpread: index) }
        }
        // `album.manualtest=1`: en manual, saca la primera foto, añade un pliego y pide 2 fotos
        // en el pliego que se ve (para ver lo pendiente antes de repartir).
        if state["album.manualtest"] != nil, let doc = album.document {
            album.setAutoLayout(false)
            if let first = doc.photos.first { album.toggle(first) }
            album.changeSpreadCount(by: 1)
            album.setPhotoCount(2, forSpread: max(0, index))
            if state["album.manualtest"] == "repartir" {
                album.autoLayoutAll()
                for _ in 0..<60 where album.isRelayouting { try? await Task.sleep(for: .milliseconds(250)) }
            }
        }
        // `album.emptytest=1`: en manual, añade un pliego vacío, le pone 3 casillas y (con `=drop`)
        // le suelta la última foto de la tira.
        if let mode = state["album.emptytest"] {
            album.setAutoLayout(false)
            album.changeSpreadCount(by: 1)
            let target = album.selectedSpread
            album.setPhotoCount(3, forSpread: target)
            if mode == "drop", let last = album.document?.photos.last {
                album.dropOnSpread(last, index: target)
            }
        }
        // `album.celltest=empty|remove|merge`: en manual, saca la primera foto del pliego que se ve
        // (deja su casilla vacía) y luego la quita o la fusiona con la primera vecina posible.
        if let mode = state["album.celltest"], let spread = album.piece(index), let first = spread.layout.cells.first {
            album.setAutoLayout(false)
            if let photo = first.photo { album.toggle(photo) }
            switch mode {
            case "remove": album.cellAction(.remove, cell: first.id, inSpread: index)
            case "merge":
                if let side = AlbumMergeSide.allCases.first(where: { album.canMerge(cell: first.id, side: $0, inSpread: index) }) {
                    album.cellAction(.merge(side), cell: first.id, inSpread: index)
                }
            default: break
            }
            selectedCell = first.id
        }
        // `album.striptest=1`: en manual, quita el pliego que se ve (sus fotos quedan sin colocar) y
        // lleva en la tira la primera de ellas delante de la primera foto del pliego siguiente.
        if state["album.striptest"] != nil {
            album.setAutoLayout(false)
            album.changeSpreadCount(by: -1)
            if let doc = album.document, let moving = doc.photos.first(where: { doc.unplacedPhotos.contains($0) }),
               doc.spreads.indices.contains(album.selectedSpread), let target = doc.spreads[album.selectedSpread].photos.first,
               let from = doc.photos.firstIndex(of: moving), let to = doc.photos.firstIndex(of: target) {
                album.movePhotos(from: IndexSet(integer: from), to: to)
            }
            // `=twice`: otra «?» entre la 1.ª y la 2.ª foto de ese pliego (que ya tiene candado).
            if state["album.striptest"] == "twice", let doc = album.document,
               let moving = doc.photos.first(where: { doc.unplacedPhotos.contains($0) }),
               doc.spreads.indices.contains(album.selectedSpread), doc.spreads[album.selectedSpread].photos.count > 1,
               let from = doc.photos.firstIndex(of: moving),
               let to = doc.photos.firstIndex(of: doc.spreads[album.selectedSpread].photos[1]) {
                album.movePhotos(from: IndexSet(integer: from), to: to)
            }
        }
        // `album.addone=1`: marca la foto más antigua que aún no está en el álbum.
        if state["album.addone"] != nil,
           let file = appState.files.sorted(by: { $0.captureDate < $1.captureDate }).first(where: { !album.contains($0.name) }) {
            album.toggle(file.name)
        }
        // `album.swaptest=1`: intercambia la primera foto del pliego 1 con la primera del 2.
        if state["album.swaptest"] != nil, let doc = album.document, doc.spreads.count > 1,
           let a = doc.spreads[0].photos.first, let b = doc.spreads[1].photos.first {
            album.swapPhotos(a, b)
        }
        // `album.count=N`: pide N fotos en el pliego que se ve.
        if let n = state["album.count"].flatMap(Int.init) { album.setPhotoCount(n, forSpread: index) }
        // `album.undo=N`: deshace N pasos (para probar el deshacer).
        if let steps = state["album.undo"].flatMap(Int.init) {
            try? await Task.sleep(for: .milliseconds(300))
            for _ in 0..<steps { album.undo() }
        }
        if state["album.lockPhoto"] != nil, let cell = album.piece(index)?.layout.cells.first {
            album.togglePhotoLock(cell: cell.id, inSpread: index)
        }
        // `album.retoggle=1`: «Ninguna» y luego «Todas», como al probarlo a mano.
        if state["album.retoggle"] != nil {
            album.toggleAll()
            for _ in 0..<60 where album.isRelayouting { try? await Task.sleep(for: .milliseconds(250)) }
            album.toggleAll()
            for _ in 0..<60 where album.isRelayouting { try? await Task.sleep(for: .milliseconds(250)) }
        }
        if state["album.bleed"] != nil, let layout = album.piece(index)?.layout, let cell = layout.cells.first {
            album.setLayout(layout.updatingCell(cell.id) { $0.bleed = true }, forSpread: index)
        }
        // `--state album.export=all` (o el número de un pliego) exporta sin el aviso de ampliación.
        if let what = state["album.export"] {
            album.export(only: what == "all" ? nil : Int(what).map { $0 - 1 })
        }
        if state["album.crop"] != nil, let cell = album.piece(index)?.layout.cells.first {
            if let zoom = state["album.zoom"].flatMap(Double.init), let layout = album.piece(index)?.layout {
                album.setLayout(layout.updatingCell(cell.id) { $0.zoom = zoom }, forSpread: index)
            }
            selectedCell = cell.id
            croppingCell = cell.id
        }
    }

    private func navigation(spread: AlbumSpread, index: Int) -> some View {
        let album = appState.album
        // A mano, el número pedido se ve aunque aún no se haya repartido («5 fotos, pendiente»).
        // En un pliego vacío maquetado a mano cuentan sus casillas.
        let shown = spread.layout.cells.contains { $0.photo == nil } ? spread.layout.cells.count : spread.photos.count
        let count = spread.manualCount ?? shown
        let countPending = spread.manualCount.map { $0 != shown } ?? false
        let isCover = index == AlbumExport.coverIndex
        return HStack(spacing: 12) {
            Button { album.selectedSpread = max(album.firstPiece, index - 1) } label: { Image(systemName: "chevron.left") }
                .disabled(index <= album.firstPiece)
                .keyboardShortcut(.leftArrow, modifiers: [])
            Group {
                if isCover { Text("Portada") } else { Text("Pliego \(index + 1) de \(document.spreads.count)") }
            }
            .monospacedDigit()
            Button { album.selectedSpread = min(document.spreads.count - 1, index + 1) } label: { Image(systemName: "chevron.right") }
                .disabled(index >= document.spreads.count - 1)
                .keyboardShortcut(.rightArrow, modifiers: [])
            if !isCover {
                Divider().frame(height: 16)
                Stepper(value: Binding(get: { max(count, 1) }, set: { album.setPhotoCount($0, forSpread: index) }),
                        in: 1...(document.singleSide(ofSpread: index) == nil ? 12 : 6)) {
                    HStack(spacing: 4) {
                        Text(count == 1 ? LocalizedStringKey("1 foto") : LocalizedStringKey("\(count) fotos"))
                            .monospacedDigit()
                        if countPending {
                            Text("(pendiente)").foregroundStyle(.orange)
                        }
                    }
                }
                .fixedSize()
                .help(document.autoLayout
                      ? LocalizedStringKey("Cambia cuántas fotos lleva este pliego: lo recoloca y las demás corren a los siguientes")
                      : LocalizedStringKey("Pide cuántas fotos lleva este pliego; se aplica al pulsar «Repartir»"))
                Divider().frame(height: 16)
                Button { album.changeSpreadCount(by: 1) } label: { Label("Añadir pliego", systemImage: "plus.rectangle.on.rectangle") }
                    .help(document.autoLayout
                          ? LocalizedStringKey("Añade un pliego al álbum y reparte de nuevo las fotos entre todos (los que tienen candado no se tocan)")
                          : LocalizedStringKey("Añade un pliego en blanco detrás de este; las fotos se reparten al pulsar «Repartir»"))
                Button { album.changeSpreadCount(by: -1) } label: { Label("Quitar pliego", systemImage: "minus.rectangle") }
                    .help(document.autoLayout
                          ? LocalizedStringKey("Quita este pliego y reparte sus fotos entre los demás (los que tienen candado no se tocan)")
                          : LocalizedStringKey("Quita este pliego; sus fotos quedan sin colocar hasta pulsar «Repartir»"))
                    .disabled(document.spreads.count <= 1)
            }
            Spacer(minLength: 0)
        }
        .controlSize(.small)
        .disabled(album.isRelayouting)
    }

    private func tools(spread: AlbumSpread, index: Int, spec: AlbumSpec) -> some View {
        let album = appState.album
        // La lista de otras composiciones vale mientras no cambien las fotos ni el número de casillas.
        let key = spread.id.uuidString + spread.photos.joined(separator: "|") + "#\(spread.layout.cells.count)"
        return HStack(spacing: 12) {
            Button { album.toggleSpreadLock(index) } label: {
                Label(spread.locked ? LocalizedStringKey("Con candado") : LocalizedStringKey("Sin candado"), systemImage: spread.locked ? "lock.fill" : "lock.open")
            }
            .help("Con candado, la cascada y «Repartir automáticamente» no tocan este pliego. Se pone solo al retocarlo.")
            Divider().frame(height: 16)
            HStack(spacing: 4) {
                Button { showAlternative(-1, spread: spread, index: index, key: key) } label: { Image(systemName: "chevron.backward.circle") }
                Text(alternativesKey == key && alternativeIndex >= 0
                     ? L("Composición \(alternativeIndex + 1) de \(alternatives.count)") : L("Otras composiciones"))
                    .monospacedDigit()
                    .fixedSize()
                Button { showAlternative(1, spread: spread, index: index, key: key) } label: { Image(systemName: "chevron.forward.circle") }
            }
            .disabled(spread.layout.cells.isEmpty)
            .help("Otras formas de componer este pliego con las mismas fotos, de mejor a peor")
            Button { if let cell = selectedCell { album.setLayout(spread.layout.equalizing(around: cell, spec: spec), forSpread: index, action: L("Igualar")) } } label: {
                Label("Igualar", systemImage: "equal.square")
            }
            .disabled(selectedCell == nil)
            .help("Reparte a partes iguales la fila o columna de la casilla elegida")
            Button {
                album.setLayout(spread.layout.fittedToPhotos({ document.info[$0]?.aspect }, spec: spec), forSpread: index, action: L("Ajustar a las fotos"))
            } label: {
                Label("Ajustar a las fotos", systemImage: "rectangle.arrowtriangle.2.inward")
            }
            .disabled(spread.layout.cells.isEmpty)
            .help("Coloca las guías para que cada casilla tenga la proporción de su foto, sin cambiar la rejilla")
            Menu {
                if let cell = selectedCell {
                    AlbumCellMenuItems(cell: cell, spreadIndex: index)
                }
            } label: {
                Label("Casilla", systemImage: "rectangle.split.2x1")
            }
            .fixedSize()
            .disabled(selectedCell == nil)
            .help("Dividir, fusionar o quitar la casilla elegida (como las celdas de una tabla)")
            Button { showTemplates = true } label: { Label("Plantilla…", systemImage: "square.grid.3x2") }
                .disabled(spread.layout.cells.isEmpty)
                .popover(isPresented: $showTemplates, arrowEdge: .bottom) {
                    AlbumTemplatePicker(spread: spread, index: index, spec: spec, single: document.singleSide(ofSpread: index)) { showTemplates = false }
                }
            Spacer(minLength: 0)
        }
        .controlSize(.small)
        .disabled(album.isRelayouting)
    }

    /// Debajo de los controles: si hay cambios sin repartir, qué es la portada o por qué el pliego
    /// quedó así.
    @ViewBuilder
    private func statusLine(spread: AlbumSpread, isCover: Bool) -> some View {
        Group {
            if document.pendingLayout && !isCover {
                Label("Hay cambios sin repartir: pulsa «Repartir» cuando acabes", systemImage: "exclamationmark.circle.fill")
                    .foregroundStyle(.orange)
            } else if isCover {
                Label("Portada: contraportada, lomo y tapa. Suelta aquí fotos de la carpeta o de la tira; no cambian el álbum.", systemImage: "book.closed")
                    .foregroundStyle(.secondary)
            } else if let reason = spread.reason, !spread.locked {
                Label(reasonText(reason), systemImage: "wand.and.stars")
                    .foregroundStyle(.secondary)
            } else if spread.locked {
                Label("Retocado a mano: «Repartir» no lo toca · doble clic en una foto para encuadrarla", systemImage: "lock.fill")
                    .foregroundStyle(.secondary)
            }
        }
        .font(.caption)
        .lineLimit(1)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// En la portada solo se cambia la foto y su encuadre (sin composiciones, plantillas, guías
    /// ni candado). Si viene con otra rejilla de antes, se puede volver a una sola foto.
    private var coverTools: some View {
        let album = appState.album
        return HStack(spacing: 12) {
            if !album.coverIsSinglePhoto {
                Button { album.resetCover() } label: { Label("Una sola foto en la tapa", systemImage: "rectangle.portrait") }
                    .help("Deja la portada con una sola foto a sangre en la tapa")
            }
            Spacer()
            Text("Suelta una foto en la tapa para cambiarla · doble clic para encuadrarla")
                .font(.caption).foregroundStyle(.secondary)
                .lineLimit(1)
        }
        .controlSize(.small)
        .disabled(album.isRelayouting)
    }

    /// Pasa a la composición siguiente (o anterior) de la lista; la lista se calcula la primera vez.
    private func showAlternative(_ step: Int, spread: AlbumSpread, index: Int, key: String) {
        let album = appState.album
        if alternativesKey != key {
            alternatives = album.alternatives(forSpread: index)
            alternativesKey = key
            alternativeIndex = -1
        }
        guard !alternatives.isEmpty else { return }
        alternativeIndex = alternativeIndex < 0
            ? (step > 0 ? 0 : alternatives.count - 1)
            : (alternativeIndex + step + alternatives.count) % alternatives.count
        album.setLayout(alternatives[alternativeIndex], forSpread: index, action: L("Otra composición"))
        // Al aplicarla cambian los ids de las casillas, pero no las fotos: la lista sigue valiendo.
        alternativesKey = key
    }

    private func reasonText(_ reason: AlbumSpreadReason) -> String {
        switch reason {
        case .panorama: return L("Panorámica: ocupa el pliego entero")
        case .group(let faces): return L("Grupo de \(faces) personas: necesita sitio para que se vean las caras")
        case .sameMoment(let seconds): return L("Fotos del mismo momento (en \(seconds) s)")
        case .manualCount: return L("Número de fotos elegido a mano")
        case .bestFit: return L("Lo que mejor encaja con el formato y las caras de estas fotos")
        }
    }
}

/// Lo que se puede hacer con una casilla, como con las celdas de una tabla: dividirla, fusionarla
/// con una vecina que comparte todo el lado o quitarla. Va en el menú de la casilla y en el menú
/// «Casilla» de la barra.
struct AlbumCellMenuItems: View {
    @Environment(AppState.self) private var appState
    let cell: UUID
    let spreadIndex: Int

    var body: some View {
        let album = appState.album
        Button("Dividir en columnas") { album.cellAction(.splitColumns, cell: cell, inSpread: spreadIndex) }
        Button("Dividir en filas") { album.cellAction(.splitRows, cell: cell, inSpread: spreadIndex) }
        Divider()
        Button("Fusionar con la de la izquierda") { album.cellAction(.merge(.left), cell: cell, inSpread: spreadIndex) }
            .disabled(!album.canMerge(cell: cell, side: .left, inSpread: spreadIndex))
        Button("Fusionar con la de la derecha") { album.cellAction(.merge(.right), cell: cell, inSpread: spreadIndex) }
            .disabled(!album.canMerge(cell: cell, side: .right, inSpread: spreadIndex))
        Button("Fusionar con la de arriba") { album.cellAction(.merge(.top), cell: cell, inSpread: spreadIndex) }
            .disabled(!album.canMerge(cell: cell, side: .top, inSpread: spreadIndex))
        Button("Fusionar con la de abajo") { album.cellAction(.merge(.bottom), cell: cell, inSpread: spreadIndex) }
            .disabled(!album.canMerge(cell: cell, side: .bottom, inSpread: spreadIndex))
        Divider()
        Button("Quitar casilla") { album.cellAction(.remove, cell: cell, inSpread: spreadIndex) }
            .disabled(!album.canRemove(cell: cell, inSpread: spreadIndex))
    }
}

/// Plantillas de collage para la rejilla de una página o del pliego entero, con el mismo
/// número de fotos que tiene esa parte.
private struct AlbumTemplatePicker: View {
    @Environment(AppState.self) private var appState
    let spread: AlbumSpread
    let index: Int
    let spec: AlbumSpec
    /// En un pliego de una página, la única página que se puede tocar.
    var single: AlbumPageSide? = nil
    let onApply: () -> Void

    @State private var place: AlbumBlockPlace = .full

    var body: some View {
        let album = appState.album
        let count = album.photoCount(of: place, inSpread: index)
        let templates = AlbumTemplates.templates(photos: count)
        let isPages: Bool = { if case .pages = spread.layout { return true }; return false }()
        // Proporción de la zona donde se aplica, para dibujar las miniaturas como quedarán.
        let zone = place == .full ? spec.spreadContent : spec.pageContent(.left)
        VStack(alignment: .leading, spacing: 10) {
            Text("Plantilla para la rejilla").font(.headline)
            if isPages && single == nil {
                Picker("", selection: $place) {
                    Text("Página izquierda").tag(AlbumBlockPlace.left)
                    Text("Pliego entero").tag(AlbumBlockPlace.full)
                    Text("Página derecha").tag(AlbumBlockPlace.right)
                }
                .pickerStyle(.segmented)
                .labelsHidden()
            }
            Text(count == 1 ? LocalizedStringKey("Plantillas de 1 foto") : LocalizedStringKey("Plantillas de \(count) fotos (las de collage que no se pisan)"))
                .font(.caption).foregroundStyle(.secondary)
            if templates.isEmpty {
                Text("No hay plantillas con ese número de fotos.")
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, minHeight: 80)
            } else {
                ScrollView {
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: place == .full ? 120 : 70), spacing: 10)], spacing: 10) {
                        ForEach(templates) { template in
                            AlbumNodePreview(node: template.node)
                                .aspectRatio(zone.width / zone.height, contentMode: .fit)
                                .contentShape(Rectangle())
                                .onTapGesture {
                                    album.apply(template, to: place, inSpread: index)
                                    onApply()
                                }
                                .help(template.name)
                        }
                    }
                    .padding(2)
                }
                .frame(height: 300)
            }
        }
        .padding(16)
        .frame(width: 460)
        .onAppear { if let single { place = single == .left ? .left : .right } }
    }
}

/// Dibujo sencillo de un árbol de cortes (las casillas en gris), para elegir plantillas.
struct AlbumNodePreview: View {
    let node: AlbumNode

    var body: some View {
        GeometryReader { geo in
            let rects = node.cellRects(in: CGRect(origin: .zero, size: geo.size), gap: 2)
            ZStack(alignment: .topLeading) {
                Rectangle().fill(Color.white)
                // Gris fijo: el «secundario» del sistema en modo oscuro es casi blanco y no se distinguía.
                ForEach(Array(rects.enumerated()), id: \.offset) { _, entry in
                    Rectangle().fill(Color(white: 0.62))
                        .frame(width: entry.rect.width, height: entry.rect.height)
                        .offset(x: entry.rect.minX, y: entry.rect.minY)
                }
            }
        }
        .overlay(Rectangle().stroke(Color(white: 0.5), lineWidth: 1))
    }
}

// MARK: - Fila de pliegos y tira

/// Abajo: la fila de pliegos (para moverse) y la tira de fotos en el orden del álbum.
private struct AlbumBottomBlock: View {
    @Environment(AppState.self) private var appState
    let document: AlbumDocument
    /// Miniatura sobre la que se está arrastrando una foto (para resaltarla).
    @State private var targeted: Int?

    /// Las miniaturas aceptan fotos: van a ese pliego (a una casilla vacía o una más).
    private func dropTarget(_ index: Int) -> some ViewModifier {
        SpreadDropTarget(index: index, targeted: $targeted) { photo in appState.album.dropOnSpread(photo, index: index) }
    }

    var body: some View {
        let album = appState.album
        // Peor aviso de ampliación de cada pliego, para el punto de color de su miniatura.
        let worst = Dictionary(album.resolutionIssues().map { ($0.spread, $0.level) }, uniquingKeysWith: { a, b in a == .veryLow ? a : b })
        VStack(alignment: .leading, spacing: 8) {
            ScrollViewReader { proxy in
                ScrollView(.horizontal) {
                    LazyHStack(spacing: 10) {
                        if album.hasCover, let cover = document.cover, let coverSpec = document.spec.coverSpec {
                            VStack(spacing: 2) {
                                SpreadCanvas(spec: coverSpec, layout: cover.layout, info: document.info,
                                             folder: appState.sourceFolder, showGuides: false, thumbnailSize: 240)
                                    .frame(width: 150, height: 80)
                                    .padding(3)
                                    .background(RoundedRectangle(cornerRadius: 6)
                                        .stroke(album.selectedSpread == AlbumExport.coverIndex ? Color.accentColor : .clear, lineWidth: 2))
                                Text("Portada").font(.caption2).foregroundStyle(.secondary)
                            }
                            .id(cover.id)
                            .contentShape(Rectangle())
                            .onTapGesture { album.selectedSpread = AlbumExport.coverIndex }
                            .modifier(dropTarget(AlbumExport.coverIndex))
                        }
                        ForEach(Array(document.spreads.enumerated()), id: \.element.id) { index, spread in
                            VStack(spacing: 2) {
                                SpreadCanvas(spec: document.spec, layout: spread.layout, info: document.info,
                                             folder: appState.sourceFolder, showGuides: false, thumbnailSize: 240,
                                             glued: document.singleSide(ofSpread: index).map { $0 == .left ? AlbumPageSide.right : .left })
                                    .frame(width: 150, height: 80)
                                    .overlay(alignment: .topTrailing) {
                                        if spread.locked {
                                            Image(systemName: "lock.fill").font(.caption2)
                                                .padding(3).background(.ultraThinMaterial, in: Circle())
                                        }
                                    }
                                    .overlay(alignment: .bottomLeading) {
                                        if let level = worst[index] {
                                            Circle().fill(level == .veryLow ? Color.red : Color.orange)
                                                .frame(width: 9, height: 9)
                                                .overlay(Circle().stroke(.white, lineWidth: 1))
                                                .padding(4)
                                                .help("Alguna foto se amplía demasiado en este pliego")
                                        }
                                    }
                                    .padding(3)
                                    .background(RoundedRectangle(cornerRadius: 6)
                                        .stroke(index == album.selectedSpread ? Color.accentColor : .clear, lineWidth: 2))
                                Text("\(index + 1)").font(.caption2).foregroundStyle(.secondary)
                            }
                            .id(spread.id)
                            .contentShape(Rectangle())
                            .onTapGesture { album.selectedSpread = index }
                            .modifier(dropTarget(index))
                        }
                    }
                    .padding(.vertical, 2)
                }
                .frame(height: 104)
                .overlay {
                    if document.spreads.isEmpty && !album.hasCover {
                        Text("Aquí saldrán los pliegos en cuanto marques fotos.")
                            .font(.callout).foregroundStyle(.secondary)
                    }
                }
                .onChange(of: album.selectedSpread) {
                    if document.spreads.indices.contains(album.selectedSpread) {
                        withAnimation { proxy.scrollTo(document.spreads[album.selectedSpread].id, anchor: .center) }
                    }
                }
            }
            HStack {
                Text("Tira del álbum").font(.headline)
                Text("Suelta una foto entre dos para cambiar el orden, o encima de otra para intercambiarlas. También puedes soltarla en una casilla del pliego.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            AlbumStrip(document: document)
                .overlay {
                    if document.photos.isEmpty {
                        Text("Las fotos que marques irán apareciendo aquí, por fecha de disparo.")
                            .font(.callout).foregroundStyle(.secondary)
                    }
                }
        }
    }
}

/// Una miniatura de la fila de pliegos donde se pueden soltar fotos (se resalta al pasar por encima).
private struct SpreadDropTarget: ViewModifier {
    let index: Int
    @Binding var targeted: Int?
    let onDrop: (String) -> Void

    func body(content: Content) -> some View {
        content
            .overlay {
                if targeted == index {
                    RoundedRectangle(cornerRadius: 6).strokeBorder(Color.accentColor, lineWidth: 3)
                }
            }
            .dropDestination(for: String.self) { items, _ in
                guard let photo = SpreadEditorCanvas.photo(from: items) else { return false }
                onDrop(photo)
                return true
            } isTargeted: { inside in
                if inside { targeted = index } else if targeted == index { targeted = nil }
            }
    }
}

/// Las fotos del álbum en orden. Se reordenan arrastrando; pulsando una se va a su pliego.
private struct AlbumStrip: View {
    @Environment(AppState.self) private var appState
    let document: AlbumDocument
    /// Lo que se ilumina mientras se arrastra: una franja entre fotos (reordenar) o una foto (intercambiar).
    @State private var targetGap: Int?
    @State private var targetPhoto: String?

    /// Las fotos que se arrastran (solo las del álbum).
    private func dragged(_ items: [String]) -> [String] {
        items.compactMap { $0.hasPrefix("album:") ? String($0.dropFirst(6)) : nil }
    }

    /// Franja fina entre dos fotos: soltar aquí cambia el orden.
    private func gap(_ index: Int) -> some View {
        ZStack {
            Color.clear
            Capsule().fill(targetGap == index ? Color.accentColor : .clear).frame(width: 3, height: 52)
        }
        .frame(width: 10, height: 60)
        .contentShape(Rectangle())
        .dropDestination(for: String.self) { items, _ in
            let offsets = IndexSet(dragged(items).compactMap { document.photos.firstIndex(of: $0) })
            guard !offsets.isEmpty else { return false }
            appState.album.movePhotos(from: offsets, to: index)
            return true
        } isTargeted: { inside in
            if inside { targetGap = index } else if targetGap == index { targetGap = nil }
        }
    }

    var body: some View {
        let album = appState.album
        let spreadOf = spreadIndexByPhoto
        let fixed = album.fixedPhotos
        let unplaced = document.unplacedPhotos
        ScrollView(.horizontal) {
            LazyHStack(spacing: 0) {
                ForEach(Array(document.photos.enumerated()), id: \.element) { index, name in
                    gap(index)
                    let inSelected = spreadOf[name] == album.selectedSpread
                    ThumbnailView(url: folderURL(name), maxPixelSize: 160, displaySize: 56)
                        .overlay(alignment: .bottomTrailing) {
                            // Fijada (o en un pliego con candado): no se mueve al arrastrar en la tira.
                            if fixed.contains(name) {
                                Image(systemName: "lock.fill").font(.system(size: 9))
                                    .padding(2).background(.ultraThinMaterial, in: Circle())
                            }
                        }
                        .overlay(alignment: .topLeading) {
                            // Sin colocar (a mano, hasta el siguiente reparto).
                            if unplaced.contains(name) {
                                Image(systemName: "questionmark.circle.fill").font(.system(size: 11))
                                    .foregroundStyle(.white, .orange)
                                    .padding(2)
                            }
                        }
                        .padding(2)
                        .background(RoundedRectangle(cornerRadius: 5)
                            .fill(inSelected ? Color.accentColor.opacity(0.35) : .clear))
                        .overlay {
                            if unplaced.contains(name) {
                                RoundedRectangle(cornerRadius: 5).strokeBorder(Color.orange, style: StrokeStyle(lineWidth: 1.5, dash: [4, 3]))
                            }
                        }
                        .contentShape(Rectangle())
                        .onTapGesture { if let spread = spreadOf[name] { album.selectedSpread = spread } }
                        .contextMenu {
                            Button("Quitar del álbum") { album.toggle(name) }
                        }
                        .overlay {
                            if targetPhoto == name {
                                RoundedRectangle(cornerRadius: 5).strokeBorder(Color.accentColor, lineWidth: 3)
                            }
                        }
                        .draggable("album:" + name)
                        // Encima de otra foto: se intercambian (también su casilla en los pliegos).
                        .dropDestination(for: String.self) { items, _ in
                            guard let moving = dragged(items).first, moving != name else { return false }
                            album.swapPhotos(moving, name)
                            return true
                        } isTargeted: { inside in
                            if inside { targetPhoto = name } else if targetPhoto == name { targetPhoto = nil }
                        }
                        .help(unplaced.contains(name) ? L("\(name) · sin colocar: suéltala en una casilla o pulsa «Repartir»") : name)
                }
                gap(document.photos.count)
            }
            .padding(.vertical, 2)
        }
        .frame(height: 66)
    }

    private func folderURL(_ name: String) -> URL {
        (appState.sourceFolder ?? URL(fileURLWithPath: "/")).appendingPathComponent(name)
    }

    /// En qué pliego está cada foto, para resaltar las del pliego que se ve.
    private var spreadIndexByPhoto: [String: Int] {
        var result: [String: Int] = [:]
        for (i, spread) in document.spreads.enumerated() {
            for photo in spread.photos { result[photo] = i }
        }
        return result
    }
}

// MARK: - Exportación

/// Al pie del módulo: dónde se exporta, cuánto mide cada pliego y los dos botones. Antes de
/// exportar, si alguna foto se amplía demasiado, sale la lista para decidir.
private struct AlbumExportBar: View {
    @Environment(AppState.self) private var appState
    let document: AlbumDocument

    /// Lo que se iba a exportar cuando salió el aviso (`nil` = el álbum entero).
    @State private var pending: PendingExport?

    struct PendingExport: Identifiable {
        let only: Int?
        let issues: [AlbumExport.Issue]
        let id = UUID()
    }

    var body: some View {
        let album = appState.album
        let isCover = album.selectedSpread == AlbumExport.coverIndex && album.hasCover
        // Medida del fichero de lo que se ve: la portada, una página sola o un pliego.
        let size = isCover ? (document.spec.coverSpec?.exportPixelSize ?? document.spec.exportPixelSize)
            : (document.spec.singlePageExport == .pageOnly && document.singleSide(ofSpread: album.selectedSpread) != nil
               ? document.spec.pagePixelSize : document.spec.exportPixelSize)
        HStack(spacing: 10) {
            Image(systemName: "folder").foregroundStyle(.secondary)
            Text(folderText)
                .lineLimit(1).truncationMode(.middle)
            Text(L("\(size.width) × \(size.height) px a \(document.spec.ppi) ppp · JPEG sRGB"))
                .font(.caption).foregroundStyle(.secondary)
                .lineLimit(1)
            Spacer()
            Button(isCover ? LocalizedStringKey("Exportar la portada") : LocalizedStringKey("Exportar este pliego")) { start(only: album.selectedSpread) }
                .disabled(!canExport)
            Button("Exportar álbum") { start(only: nil) }
                .buttonStyle(.borderedProminent)
                .disabled(!canExport)
        }
        .caobaPanel(padding: 8)
        .sheet(item: $pending) { export in
            AlbumResolutionSheet(issues: export.issues, onExport: {
                pending = nil
                album.export(only: export.only)
            }, onCancel: { pending = nil })
        }
    }

    private var canExport: Bool {
        !document.spreads.isEmpty && !appState.album.isRelayouting && !appState.jobRunner.isBusy && appState.album.exportFolder != nil
    }

    /// «Álbum/Novios» (o la ruta entera si no hay sesión).
    private var folderText: String {
        guard let folder = appState.album.exportFolder else { return "" }
        let parent = folder.deletingLastPathComponent().lastPathComponent
        return "\(parent)/\(folder.lastPathComponent)"
    }

    private func start(only: Int?) {
        let album = appState.album
        let issues = album.resolutionIssues(spreads: only.map { [$0] })
        if issues.isEmpty {
            album.export(only: only)
        } else {
            pending = PendingExport(only: only, issues: issues)
        }
    }
}

/// Lista de fotos que se amplían demasiado, antes de exportar.
private struct AlbumResolutionSheet: View {
    let issues: [AlbumExport.Issue]
    let onExport: () -> Void
    let onCancel: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("Hay fotos que se amplían demasiado", systemImage: "exclamationmark.triangle.fill")
                .font(.headline)
                .foregroundStyle(issues.contains { $0.level == .veryLow } ? Color.red : Color.orange)
            Text("Sus píxeles no llegan para imprimirlas a ese tamaño y pueden verse blandas. Por debajo de 200 ppp efectivos, en naranja; por debajo de 150, en rojo. Puedes hacer su casilla más pequeña, quitar la ampliación del encuadre o exportar igualmente.")
                .font(.callout).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            List(issues, id: \.photo) { issue in
                HStack {
                    Circle().fill(issue.level == .veryLow ? Color.red : Color.orange).frame(width: 9, height: 9)
                    Group {
                        if issue.spread == AlbumExport.coverIndex { Text("Portada") } else { Text("Pliego \(issue.spread + 1)") }
                    }
                    .monospacedDigit().frame(width: 80, alignment: .leading)
                    Text(issue.photo).lineLimit(1).truncationMode(.middle)
                    Spacer()
                    Text("\(Int(issue.ppi.rounded())) ppp").monospacedDigit()
                        .foregroundStyle(issue.level == .veryLow ? Color.red : Color.orange)
                }
            }
            .frame(height: min(260, CGFloat(issues.count) * 28 + 20))
            HStack {
                Spacer()
                Button("Volver", role: .cancel) { onCancel() }
                    .keyboardShortcut(.cancelAction)
                Button("Exportar igualmente") { onExport() }
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(20)
        .frame(width: 520)
    }
}
