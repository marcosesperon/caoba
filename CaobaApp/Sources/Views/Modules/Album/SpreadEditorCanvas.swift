import SwiftUI
import AppKit
import CaobaCore

/// El pliego grande, para retocarlo a mano:
/// - las guías entre casillas se arrastran (con imán y la medida de las dos casillas en mm);
/// - clic elige una casilla y doble clic entra en el encuadre (arrastrar mueve la foto, la
///   rueda o el pellizco la amplían; Esc o clic fuera para salir);
/// - las fotos se arrastran de una casilla a otra, o desde la tira o la carpeta.
/// Cada retoque pone el candado del pliego (lo hace `AlbumWorkspace.setLayout`).
struct SpreadEditorCanvas: View {
    @Environment(AppState.self) private var appState
    let spreadIndex: Int
    let spread: AlbumSpread
    let document: AlbumDocument
    /// Medidas de esta pieza (la portada tiene las suyas).
    let spec: AlbumSpec
    /// En un pliego de una página, la que va pegada a la tapa (no admite fotos).
    var glued: AlbumPageSide? = nil
    @Binding var selectedCell: UUID?
    @Binding var croppingCell: UUID?

    /// Lo que se ve mientras se arrastra algo (guía o encuadre), antes de guardarlo.
    @State private var draft: AlbumSpreadLayout?
    /// Guía que se está arrastrando y el pliego tal como estaba al empezar.
    @State private var activeGuide: AlbumGuide?
    @State private var dragBase: AlbumSpreadLayout?
    @State private var dragInfo: AlbumGuideMove?
    @State private var dragSnapped = false
    @State private var hoveredGuide: String?
    /// Foto soltada sobre una casilla ocupada, a la espera de elegir qué hacer.
    @State private var pendingDrop: PendingDrop?
    /// Se está arrastrando una foto por encima de una zona libre del pliego.
    @State private var isTargeted = false
    /// Dónde está el pliego en la ventana y sus casillas (en puntos de la vista), para elegir la
    /// casilla del clic derecho.
    @State private var canvasFrame: CGRect = .zero
    @State private var cellFrames: [(id: UUID, rect: CGRect)] = []
    @State private var rightClickMonitor: Any?

    private var album: AlbumWorkspace { appState.album }
    private var isCover: Bool { spreadIndex == AlbumExport.coverIndex }
    private var layout: AlbumSpreadLayout { draft ?? spread.layout }

    struct PendingDrop: Identifiable {
        let photo: String
        let cell: UUID
        let fromAlbum: Bool
        var id: String { photo + cell.uuidString }
    }

    var body: some View {
        GeometryReader { geo in
            let g = SpreadGeometry(spec: spec, size: geo.size)
            let frames = layout.drawRects(spec).map { (id: $0.cell.id, rect: g.rect($0.rect)) }
            ZStack(alignment: .topLeading) {
                SpreadBackground(geometry: g)
                    .contentShape(Rectangle())
                    .onTapGesture { selectedCell = nil }
                    // Soltar en una zona libre del pliego: a la primera casilla vacía o una foto más.
                    .dropDestination(for: String.self) { items, _ in
                        guard let photo = Self.photo(from: items) else { return false }
                        album.dropOnSpread(photo, index: spreadIndex)
                        return true
                    } isTargeted: { isTargeted = $0 }
                if isTargeted {
                    RoundedRectangle(cornerRadius: 4).strokeBorder(Color.accentColor, lineWidth: 3)
                        .frame(width: g.trim.width, height: g.trim.height)
                        .offset(x: g.trim.minX, y: g.trim.minY)
                        .allowsHitTesting(false)
                }
                // Lo que se dibuja (con «a sangre» llega hasta el sangrado), igual que al exportar.
                ForEach(layout.drawRects(spec), id: \.cell.id) { entry in
                    cellView(entry.cell, rect: g.rect(entry.rect), ppi: ppi(of: entry.cell, rect: entry.rect))
                }
                SpreadGuidesOverlay(geometry: g)
                SpineLine(geometry: g)
                if let glued { GluedPageOverlay(geometry: g, side: glued) }
                // En la portada no se mueven guías ni el lomo: es una foto en la tapa.
                if croppingCell == nil && !isCover {
                    guidesLayer(g)
                }
                if let id = croppingCell, let entry = layout.drawRects(spec).first(where: { $0.cell.id == id }) {
                    AlbumCropOverlay(cell: entry.cell, rect: g.rect(entry.rect), canvas: geo.size,
                                     photoAspect: entry.cell.photo.flatMap { document.info[$0]?.aspect } ?? 1.5,
                                     focus: SpreadCanvas.focus(of: entry.cell, info: document.info),
                                     folder: appState.sourceFolder,
                                     onChange: { focus, zoom in
                                         draft = layout.updatingCell(id) { $0.focus = focus; $0.zoom = zoom }
                                     },
                                     onFinish: finishCrop)
                }
                if let info = dragInfo, let guide = activeGuide {
                    measureLabel(info, guide: guide, geometry: g)
                }
                // Pliego sin casillas: cómo empezar a maquetarlo.
                if layout.cells.isEmpty && !isCover {
                    emptyHint
                        .frame(width: geo.size.width, height: geo.size.height)
                }
            }
            // La foto entera del encuadre no se sale del sitio del pliego.
            .clipped()
            .onAppear { canvasFrame = geo.frame(in: .global); cellFrames = frames }
            .onChange(of: geo.frame(in: .global)) { canvasFrame = geo.frame(in: .global) }
            .onChange(of: frames.map(\.rect)) { cellFrames = frames }
        }
        .onAppear(perform: installRightClickMonitor)
        .onDisappear(perform: removeRightClickMonitor)
        .confirmationDialog(Text("¿Qué hacemos con la foto que había?"), isPresented: Binding(get: { pendingDrop != nil }, set: { if !$0 { pendingDrop = nil } }),
                            presenting: pendingDrop) { drop in
            if drop.fromAlbum {
                Button("Intercambiarlas") { album.drop(drop.photo, onCell: drop.cell, inSpread: spreadIndex, action: .swap) }
            }
            Button("Sustituirla y que corra a los siguientes") { album.drop(drop.photo, onCell: drop.cell, inSpread: spreadIndex, action: .replaceAndFlow) }
            Button("Sustituirla y sacarla del álbum") { album.drop(drop.photo, onCell: drop.cell, inSpread: spreadIndex, action: .replaceAndRemove) }
            Button("Cancelar", role: .cancel) {}
        } message: { _ in
            Text("Intercambiar no mueve nada más. Sustituir rehace los pliegos siguientes sin candado.")
        }
        .onChange(of: spread.id) { draft = nil; croppingCell = nil; selectedCell = nil }
        .onChange(of: spread.layout) { if activeGuide == nil && croppingCell == nil { draft = nil } }
    }

    // MARK: - Casillas

    /// Ppp efectivos de la foto de una casilla (con su tamaño real, de la lista de la carpeta).
    private func ppi(of cell: AlbumCell, rect: CGRect) -> Double? {
        guard let photo = cell.photo, let size = appState.files.first(where: { $0.name == photo })?.size else { return nil }
        return AlbumExport.effectivePPI(pixels: size, cell: cell, rect: rect, focus: SpreadCanvas.focus(of: cell, info: document.info))
    }

    private func cellView(_ cell: AlbumCell, rect: CGRect, ppi: Double?) -> some View {
        let selected = selectedCell == cell.id
        let level = ppi.map(AlbumExport.level(for:)) ?? .ok
        return AlbumCellImage(url: cell.photo.flatMap { appState.sourceFolder?.appendingPathComponent($0) },
                              focus: SpreadCanvas.focus(of: cell, info: document.info), zoom: cell.scale,
                              size: rect.size)
            .frame(width: rect.width, height: rect.height)
            .overlay {
                Rectangle().stroke(Color.accentColor, lineWidth: selected ? 3 : 0)
            }
            .overlay(alignment: .bottomLeading) {
                // Se amplía demasiado para imprimirla a este tamaño.
                if level != .ok, let ppi {
                    Label("\(Int(ppi.rounded())) ppp", systemImage: "exclamationmark.triangle.fill")
                        .font(.caption2.weight(.semibold))
                        .padding(.horizontal, 5).padding(.vertical, 2)
                        .background(level == .veryLow ? Color.red : Color.orange, in: Capsule())
                        .foregroundStyle(.white)
                        .padding(4)
                        .help(level == .veryLow ? LocalizedStringKey("Por debajo de 150 ppp: se verá blanda al imprimirla a este tamaño")
                                                : LocalizedStringKey("Por debajo de 200 ppp: puede verse algo blanda impresa a este tamaño"))
                }
            }
            .overlay(alignment: .topTrailing) {
                if cell.locked {
                    Image(systemName: "lock.fill")
                        .font(.caption)
                        .padding(4)
                        .background(.ultraThinMaterial, in: Circle())
                        .padding(4)
                        .help("Foto fijada en esta casilla")
                }
            }
            .help(isCover ? LocalizedStringKey("Doble clic para encuadrar · suelta otra foto encima para cambiarla")
                          : LocalizedStringKey("Doble clic para encuadrar · clic derecho para dividir, fusionar o quitar la casilla"))
            .contentShape(Rectangle())
            .onTapGesture(count: 2) {
                guard cell.photo != nil, !album.isRelayouting else { return }
                selectedCell = cell.id
                croppingCell = cell.id
            }
            .onTapGesture { selectedCell = cell.id }
            .draggable("album:" + (cell.photo ?? "")) {
                AlbumCellImage(url: cell.photo.flatMap { appState.sourceFolder?.appendingPathComponent($0) },
                               focus: SpreadCanvas.focus(of: cell, info: document.info), size: CGSize(width: 90, height: 90 * rect.height / max(rect.width, 1)))
                    .frame(width: 90, height: 90 * rect.height / max(rect.width, 1))
            }
            .dropDestination(for: String.self) { items, _ in
                handleDrop(items, on: cell)
            }
            .contextMenu {
                // Como las celdas de una tabla: dividir, fusionar con una vecina o quitar.
                if !isCover {
                    AlbumCellMenuItems(cell: cell.id, spreadIndex: spreadIndex)
                    Divider()
                }
                if cell.photo != nil {
                    if !isCover {
                        Button(cell.locked ? LocalizedStringKey("Soltar la foto de esta casilla") : LocalizedStringKey("Fijar la foto en esta casilla")) {
                            album.togglePhotoLock(cell: cell.id, inSpread: spreadIndex)
                        }
                    }
                    Button("Encuadrar…") { selectedCell = cell.id; croppingCell = cell.id }
                    if spread.layout.touchesMargin(cell.id, spec: spec) {
                        Toggle("A sangre", isOn: Binding(get: { cell.bleed }, set: { value in
                            album.setLayout(spread.layout.updatingCell(cell.id) { $0.bleed = value }, forSpread: spreadIndex, action: L("A sangre"))
                        }))
                    }
                    Button("Encuadre automático") {
                        album.setLayout(spread.layout.updatingCell(cell.id) { $0.focus = nil; $0.zoom = nil }, forSpread: spreadIndex, action: L("Encuadre automático"))
                    }
                    Divider()
                    if isCover {
                        Button("Quitar de la portada") { album.setCoverPhoto(nil, inCell: cell.id) }
                    } else {
                        Button("Quitar del álbum") { if let photo = cell.photo { album.toggle(photo) } }
                    }
                }
            }
            .offset(x: rect.minX, y: rect.minY)
    }

    /// Un pliego vacío: se elige cuántas casillas tendrá (con el número de fotos o aquí mismo, si
    /// ya pedía un número) o se le sueltan fotos.
    private var emptyHint: some View {
        VStack(spacing: 8) {
            Text("Pliego vacío").font(.headline)
            Text("Elige con el número de fotos cuántas casillas tendrá para maquetarlo, o suelta aquí fotos de la tira.")
                .font(.callout).foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 360)
            if let wanted = spread.manualCount {
                Button(L("Crear \(wanted) casillas")) { album.setPhotoCount(wanted, forSpread: spreadIndex) }
                    .buttonStyle(.borderedProminent)
            }
        }
        .padding(16)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 10))
    }

    /// Nombre de la foto de lo que se suelta («album:<foto>» o «folder:<foto>»).
    static func photo(from items: [String]) -> String? {
        guard let item = items.first else { return nil }
        let photo = String(item.drop(while: { $0 != ":" }).dropFirst())
        return photo.isEmpty ? nil : photo
    }

    /// Lo que llega al soltar: «album:<foto>» (de la tira o de otra casilla) o «folder:<foto>».
    private func handleDrop(_ items: [String], on cell: AlbumCell) -> Bool {
        guard let item = items.first, !album.isRelayouting else { return false }
        let fromAlbum = item.hasPrefix("album:")
        let photo = String(item.drop(while: { $0 != ":" }).dropFirst())
        guard !photo.isEmpty, photo != cell.photo, !cell.locked else { return false }
        // En la portada las fotos son libres: entra sin preguntar y no toca la tira.
        if isCover {
            album.setCoverPhoto(photo, inCell: cell.id)
            return true
        }
        let inAlbum = album.contains(photo)
        // Casilla vacía: entra sin preguntar. Del mismo pliego: se intercambian.
        if cell.photo == nil {
            album.drop(photo, onCell: cell.id, inSpread: spreadIndex, action: .replaceAndFlow)
        } else if inAlbum, album.location(of: photo)?.spread == spreadIndex {
            album.drop(photo, onCell: cell.id, inSpread: spreadIndex, action: .swap)
        } else {
            pendingDrop = PendingDrop(photo: photo, cell: cell.id, fromAlbum: fromAlbum && inAlbum)
        }
        return true
    }

    // MARK: - Clic derecho

    /// El clic derecho, además de abrir el menú de la casilla, la deja elegida (así el menú
    /// «Casilla» de la barra actúa sobre ella). SwiftUI no avisa al abrir un menú contextual, así
    /// que se mira dónde cae el clic.
    private func installRightClickMonitor() {
        rightClickMonitor = NSEvent.addLocalMonitorForEvents(matching: .rightMouseDown) { event in
            // Solo en la ventana de este pliego (con varias ventanas, cada una tiene el suyo).
            guard let window = event.window, window === appState.window, let content = window.contentView else { return event }
            // De la ventana (origen abajo) a puntos de SwiftUI (origen arriba).
            let point = CGPoint(x: event.locationInWindow.x, y: content.bounds.height - event.locationInWindow.y)
            guard canvasFrame.contains(point) else { return event }
            let local = CGPoint(x: point.x - canvasFrame.minX, y: point.y - canvasFrame.minY)
            if let hit = cellFrames.first(where: { $0.rect.contains(local) }) { selectedCell = hit.id }
            return event
        }
    }

    private func removeRightClickMonitor() {
        if let rightClickMonitor { NSEvent.removeMonitor(rightClickMonitor) }
        rightClickMonitor = nil
    }

    // MARK: - Encuadre

    private func finishCrop() {
        if let draft { album.setLayout(draft, forSpread: spreadIndex, action: L("Encuadrar")) }
        draft = nil
        croppingCell = nil
    }

    // MARK: - Guías

    @ViewBuilder
    private func guidesLayer(_ g: SpreadGeometry) -> some View {
        // Mientras se arrastra, las zonas sensibles son las del pliego de antes: así la guía no
        // desaparece debajo del ratón (el lomo, por ejemplo, deja de ser guía al juntar páginas).
        let base = dragBase ?? spread.layout
        ForEach(base.guides(spec)) { guide in
            guideHandle(guide, base: base, geometry: g)
        }
    }

    private func guideHandle(_ guide: AlbumGuide, base: AlbumSpreadLayout, geometry g: SpreadGeometry) -> some View {
        let vertical = guide.axis == .columns
        let isActive = activeGuide?.kind == guide.kind
        let position = isActive ? (dragInfo?.position ?? guide.position) : guide.position
        let lineLength = (guide.span.upperBound - guide.span.lowerBound) * g.scale
        let highlighted = isActive || hoveredGuide == guide.id
        let color: Color = isActive && dragSnapped ? .green : .accentColor
        return ZStack {
            Rectangle().fill(highlighted ? color : .clear)
                .frame(width: vertical ? 2 : lineLength, height: vertical ? lineLength : 2)
        }
        .frame(width: vertical ? 10 : lineLength, height: vertical ? lineLength : 10)
        .contentShape(Rectangle())
        .onHover { inside in
            hoveredGuide = inside ? guide.id : (hoveredGuide == guide.id ? nil : hoveredGuide)
            if inside { (vertical ? NSCursor.resizeLeftRight : NSCursor.resizeUpDown).push() } else { NSCursor.pop() }
        }
        .gesture(
            DragGesture(minimumDistance: 1, coordinateSpace: .global)
                .onChanged { value in
                    guard !album.isRelayouting else { return }
                    if activeGuide == nil {
                        activeGuide = guide
                        dragBase = base
                    }
                    let delta = g.mm(vertical ? value.translation.width : value.translation.height)
                    let snapped = base.snapped(guide.position + delta, for: guide, spec: spec)
                    let move = base.moving(guide, to: snapped.position, spec: spec)
                    dragSnapped = snapped.snapped
                    dragInfo = move
                    draft = move.layout
                }
                .onEnded { _ in
                    if let draft { album.setLayout(draft, forSpread: spreadIndex, action: L("Mover una guía")) }
                    activeGuide = nil
                    dragBase = nil
                    dragInfo = nil
                    draft = nil
                }
        )
        .position(x: vertical ? g.x(position) : g.x((guide.span.lowerBound + guide.span.upperBound) / 2),
                  y: vertical ? g.y((guide.span.lowerBound + guide.span.upperBound) / 2) : g.y(position))
        .help(guide.kind == .spine ? LocalizedStringKey("Arrastra el lomo para que las fotos crucen de una página a otra") : LocalizedStringKey("Arrastra para cambiar el tamaño de las casillas"))
    }

    /// «142 mm | 136 mm» junto a la guía que se arrastra (en verde si se ha pegado a algo).
    private func measureLabel(_ info: AlbumGuideMove, guide: AlbumGuide, geometry g: SpreadGeometry) -> some View {
        let vertical = guide.axis == .columns
        let text = "\(Int(info.before.rounded())) mm  |  \(Int(info.after.rounded())) mm"
        return Text(text)
            .font(.caption.monospacedDigit().weight(.semibold))
            .padding(.horizontal, 6).padding(.vertical, 3)
            .background(dragSnapped ? Color.green : Color.accentColor, in: Capsule())
            .foregroundStyle(.white)
            .fixedSize()
            .position(x: vertical ? g.x(info.position) : g.x(guide.span.lowerBound) + 70,
                      y: vertical ? g.y(guide.span.lowerBound) + 14 : g.y(info.position) - 14)
            .allowsHitTesting(false)
    }
}

/// Encuadre de una casilla: la foto entera en tenue alrededor y la parte que entra, nítida.
/// Arrastrar mueve la foto; la rueda o el pellizco la amplían. Esc o clic fuera para acabar.
struct AlbumCropOverlay: View {
    @Environment(AppState.self) private var appState
    let cell: AlbumCell
    let rect: CGRect
    let canvas: CGSize
    let photoAspect: Double
    let focus: CGPoint
    let folder: URL?
    let onChange: (CGPoint, Double) -> Void
    let onFinish: () -> Void

    @State private var image: CGImage?
    @State private var current: (focus: CGPoint, zoom: Double)?
    @State private var dragStart: CGPoint?
    @State private var zoomStart: Double?
    @State private var monitor: Any?

    private var state: (focus: CGPoint, zoom: Double) { current ?? (focus, cell.scale) }

    var body: some View {
        let region = AlbumAutoLayout.visibleRegion(photoAspect: photoAspect, cellAspect: rect.width / max(rect.height, 1),
                                                   focus: state.focus, zoom: state.zoom)
        // Dónde queda la foto entera si la parte visible ocupa justo la casilla.
        let fullFrame = CGRect(x: rect.minX - region.minX / region.width * rect.width,
                               y: rect.minY - region.minY / region.height * rect.height,
                               width: rect.width / region.width, height: rect.height / region.height)
        ZStack(alignment: .topLeading) {
            // Todo el lienzo recoge el clic de fuera para acabar.
            Color.black.opacity(0.25)
                .frame(width: canvas.width, height: canvas.height)
                .contentShape(Rectangle())
                .onTapGesture { onFinish() }
            if let image {
                Image(decorative: image, scale: 1).resizable()
                    .frame(width: fullFrame.width, height: fullFrame.height)
                    .opacity(0.35)
                    .offset(x: fullFrame.minX, y: fullFrame.minY)
                    .allowsHitTesting(false)
                Image(decorative: image, scale: 1).resizable()
                    .frame(width: fullFrame.width, height: fullFrame.height)
                    .offset(x: fullFrame.minX - rect.minX, y: fullFrame.minY - rect.minY)
                    .frame(width: rect.width, height: rect.height, alignment: .topLeading)
                    .clipped()
                    .offset(x: rect.minX, y: rect.minY)
                    .allowsHitTesting(false)
            }
            Rectangle()
                .stroke(Color.accentColor, lineWidth: 2)
                .frame(width: rect.width, height: rect.height)
                .contentShape(Rectangle())
                .offset(x: rect.minX, y: rect.minY)
                .gesture(
                    DragGesture(minimumDistance: 0)
                        .onChanged { value in
                            let start = dragStart ?? state.focus
                            if dragStart == nil { dragStart = start }
                            // Arrastrar la foto a la derecha enseña lo que había a la izquierda.
                            let fx = start.x - value.translation.width / fullFrame.width
                            let fy = start.y - value.translation.height / fullFrame.height
                            update(focus: CGPoint(x: fx, y: fy), zoom: state.zoom)
                        }
                        .onEnded { _ in dragStart = nil }
                )
                .simultaneousGesture(
                    MagnifyGesture()
                        .onChanged { value in
                            let start = zoomStart ?? state.zoom
                            if zoomStart == nil { zoomStart = start }
                            update(focus: state.focus, zoom: start * value.magnification)
                        }
                        .onEnded { _ in zoomStart = nil }
                )
            Text("Arrastra para mover · rueda o pellizco para ampliar · Esc para acabar")
                .font(.caption)
                .padding(.horizontal, 8).padding(.vertical, 4)
                .background(.ultraThinMaterial, in: Capsule())
                .fixedSize()
                .position(x: canvas.width / 2, y: canvas.height - 14)
                .allowsHitTesting(false)
        }
        .task(id: cell.photo) {
            guard let name = cell.photo, let url = folder?.appendingPathComponent(name) else { return }
            image = await appState.thumbnails.thumbnail(for: url, maxPixelSize: 1600)
        }
        .onAppear(perform: installMonitor)
        .onDisappear(perform: removeMonitor)
    }

    /// Guarda el encuadre sin salirse de la foto (el centro se ajusta para que la parte visible quepa).
    private func update(focus: CGPoint, zoom: Double) {
        let z = min(max(zoom, 1), AlbumCell.maxZoom)
        let region = AlbumAutoLayout.visibleRegion(photoAspect: photoAspect, cellAspect: rect.width / max(rect.height, 1), focus: focus, zoom: z)
        let clamped = CGPoint(x: region.midX, y: region.midY)
        current = (clamped, z)
        onChange(clamped, z)
    }

    /// La rueda amplía y Esc acaba, mientras dura el encuadre.
    private func installMonitor() {
        monitor = NSEvent.addLocalMonitorForEvents(matching: [.scrollWheel, .keyDown]) { event in
            if event.type == .keyDown, event.keyCode == 53 {
                onFinish()
                return nil
            }
            if event.type == .scrollWheel {
                let delta = event.hasPreciseScrollingDeltas ? event.scrollingDeltaY * 0.01 : event.scrollingDeltaY * 0.1
                update(focus: state.focus, zoom: state.zoom * (1 + delta))
                return nil
            }
            return event
        }
    }

    private func removeMonitor() {
        if let monitor { NSEvent.removeMonitor(monitor) }
        monitor = nil
    }
}
