import SwiftUI
import CaobaCore

/// Ventana principal: barra lateral con los módulos y, a la derecha, la barra
/// de carpeta, el módulo activo y la barra de destino.
struct ContentView: View {
    @Environment(AppState.self) private var appState
    /// Lo de toda la app: aviso de versión, novedades y donativo.
    @Environment(AppModel.self) private var app

    var body: some View {
        @Bindable var state = appState
        NavigationSplitView {
            List(selection: $state.currentModule) {
                Section("Creadores") {
                    ForEach(Module.creators) { module in sidebarRow(module) }
                }
                Section("Utilidades") {
                    ForEach(Module.utilities) { module in sidebarRow(module) }
                }
                Section("Otras herramientas") {
                    ForEach(Module.otherTools) { module in sidebarRow(module) }
                }
            }
            .navigationSplitViewColumnWidth(min: 190, ideal: 210)
            .safeAreaInset(edge: .bottom) { sidebarFooter }
        } detail: {
            VStack(spacing: 12) {
                if app.showUpdateBanner, let update = app.availableUpdate {
                    UpdateBanner(update: update)
                        .transition(.move(edge: .top).combined(with: .opacity))
                }
                if appState.currentModule.usesSourceFolder {
                    SourceFolderBar()
                }
                // Sin carpeta de origen, el módulo (con su barra de destino) se apaga: lo primero es elegirla arriba.
                // La barra de abajo la pone cada módulo, porque lleva su botón principal.
                let needsFolder = appState.currentModule.usesSourceFolder && appState.sourceFolder == nil
                Group {
                    if appState.currentModule.isAvailable {
                        moduleView(appState.currentModule)
                    } else {
                        ComingSoonView(module: appState.currentModule)
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .disabled(needsFolder)
                .opacity(needsFolder ? 0.45 : 1)
            }
            .padding(12)
            .animation(.default, value: app.showUpdateBanner)
            // En el sitio del título va la sesión activa. El módulo ya sale dentro, con la letra de CAOBA.
            .hidingWindowTitle(appState.activeSession?.title ?? "CAOBA")
            .toolbar {
                // En macOS 26, sin la cápsula de cristal: que se vea como un título, no como un botón.
                if #available(macOS 26.0, *) {
                    ToolbarItem(placement: .navigation) { sessionPicker }
                        .sharedBackgroundVisibility(.hidden)
                } else {
                    ToolbarItem(placement: .navigation) { sessionPicker }
                }
            }
        }
        .jobPresentation(appState.jobRunner)
        // Aviso común a todos los módulos: la carpeta ha cambiado desde que se leyó.
        .alert("La carpeta ha cambiado", isPresented: Binding(get: { appState.pendingFolderChanges != nil },
                                                              set: { if !$0 { appState.pendingFolderChanges = nil } })) {
            Button("Recargar") { Task { await appState.reload() } }
            Button("Cancelar", role: .cancel) { appState.pendingFolderChanges = nil }
        } message: {
            Text(folderChangesMessage(appState.pendingFolderChanges))
        }
        // Novedades y donativo, una sola vez: en la ventana de delante, no en todas.
        .sheet(isPresented: Binding(get: { isFront && app.showDonationPrompt }, set: { app.showDonationPrompt = $0 })) { DonationSheet() }
        .sheet(isPresented: Binding(get: { isFront && app.whatsNewSections != nil }, set: { if !$0 { app.whatsNewSections = nil } })) {
            WhatsNewSheet(sections: app.whatsNewSections ?? [], title: app.whatsNewTitle)
        }
        // Con otra estructura de sesiones en Ajustes, la sesión de la ventana se vuelve a buscar.
        .onChange(of: app.sessions.layout) { appState.sessionLayoutChanged() }
    }

    private var isFront: Bool { app.frontWindow === appState }

    /// La barra de herramientas mide el selector la primera vez y no lo agranda: al pasar de
    /// «CAOBA» a una sesión de nombre más largo, este salía cortado («Prue…»). Con otra sesión se
    /// crea de nuevo y se vuelve a medir.
    private var sessionPicker: some View {
        SessionPicker().id(appState.activeSession?.id)
    }

    /// «Faltan 2 fotos: a.jpg, b.jpg. Hay 1 nueva: c.jpg.» con hasta 5 nombres de cada.
    private func folderChangesMessage(_ changes: FolderChanges?) -> String {
        guard let changes else { return "" }
        func names(_ list: [String]) -> String {
            list.prefix(5).joined(separator: ", ") + (list.count > 5 ? "…" : "")
        }
        var parts: [String] = []
        if !changes.missing.isEmpty {
            parts.append(String(localized: "Faltan \(changes.missing.count) fotos de la lista: \(names(changes.missing))."))
        }
        if !changes.added.isEmpty {
            parts.append(String(localized: "Hay \(changes.added.count) fotos nuevas: \(names(changes.added))."))
        }
        parts.append(String(localized: "Recarga la carpeta y revisa la lista antes de seguir."))
        return parts.joined(separator: "\n\n")
    }

    private func sidebarRow(_ module: Module) -> some View {
        Label(module.title, systemImage: module.systemImage)
            .foregroundStyle(module.isAvailable ? .primary : .secondary)
            .tag(module)
    }

    @ViewBuilder
    private func moduleView(_ module: Module) -> some View {
        switch module {
        case .slideshow: SlideshowView()
        case .collage: CollageView()
        case .album: AlbumView()
        case .contactSheet: ContactSheetView()
        case .processor: ProcessorView()
        case .watermark: WatermarkView()
        case .metadata: MetadataView()
        case .renamer: RenamerView()
        case .qr: QRView()
        case .shutterCount: ShutterCountView()
        case .cardImport: CardImportView()
        case .recovery: RecoveryView()
        }
    }

    private var sidebarFooter: some View {
        VStack(alignment: .leading, spacing: 6) {
            Divider()
            HStack {
                Text("CAOBA").font(.caobaTitle(14))
                Spacer()
                Text("v\(CaobaCoreInfo.version)").font(.caption).foregroundStyle(.secondary)
            }
            // Web a la izquierda y donativo a la derecha, los dos en el rojo de la app.
            HStack {
                Button {
                    appState.openExternal(AppModel.websiteURL)
                } label: {
                    Text("caobafoto.com")
                }
                Spacer()
                Button {
                    appState.openExternal(AppModel.donationURL)
                } label: {
                    Label("Donación", systemImage: "cup.and.saucer")
                }
            }
            .font(.caption)
            .buttonStyle(.plain)
            .foregroundStyle(Color.accentColor)
        }
        .padding(10)
    }
}

private extension View {
    /// Quita el título de la barra de la ventana para dejar sitio a la sesión. Desde macOS 15 el
    /// título sigue existiendo (menú Ventana, Mission Control) aunque no se vea; en macOS 14
    /// no se puede ocultar y se deja vacío. `title` (la sesión) no se ve arriba, pero es el que
    /// enseñan las pestañas y el menú Ventana.
    @ViewBuilder
    func hidingWindowTitle(_ title: String) -> some View {
        if #available(macOS 15.0, *) {
            navigationTitle(title).toolbar(removing: .title)
        } else {
            navigationTitle("")
        }
    }
}

/// Módulo todavía no migrado.
struct ComingSoonView: View {
    let module: Module
    var body: some View {
        ContentUnavailableView {
            Label(module.title, systemImage: module.systemImage)
        } description: {
            Text("Este módulo llegará en una fase posterior de la migración.")
        }
    }
}

/// Preferencias en tres pestañas: «General» (idioma, apariencia, autor y presets), «Sesiones» y
/// «Álbumes» (los tipos de álbum).
struct SettingsView: View {
    /// Ajustes son de toda la app, no de una ventana.
    @Environment(AppModel.self) private var app
    /// Se recuerda la última pestaña; el módulo Álbum abre Ajustes directamente en «Álbumes».
    @AppStorage(Preferences.settingsTabKey) private var tab = "general"

    var body: some View {
        TabView(selection: $tab) {
            GeneralSettingsView()
                .tabItem { Label("General", systemImage: "gearshape") }
                .tag("general")
            SessionSettingsView()
                .frame(width: 520, height: 560)
                .tabItem { Label("Sesiones", systemImage: "person.2.crop.square.stack") }
                .tag("sessions")
            AlbumTypesSettingsView()
                .frame(width: 720, height: 640)
                .tabItem { Label("Álbumes", systemImage: "book") }
                .tag("albums")
        }
        // Para capturas: `--state settings.tab=sessions`.
        .onAppear { if let initial = app.launchState["settings.tab"] { tab = initial } }
    }
}

/// Ajustes › General: idioma, apariencia, autor y presets.
struct GeneralSettingsView: View {
    @AppStorage(Preferences.appearanceKey) private var appearance: Appearance = .system
    @AppStorage(Preferences.languageKey) private var language: AppLanguage = .system
    @AppStorage(Preferences.authorKey) private var author = ""
    @State private var store = PresetStore.shared
    @State private var presetMessage: String?

    var body: some View {
        Form {
            LabeledRow("Idioma") {
                Picker("", selection: $language) {
                    ForEach(AppLanguage.allCases) { Text($0.title).tag($0) }
                }
                .labelsHidden()
            }
            LabeledRow("Apariencia") {
                Picker("", selection: $appearance) {
                    ForEach(Appearance.allCases) { Text($0.title).tag($0) }
                }
                .labelsHidden()
            }
            LabeledRow("Autor") {
                VStack(alignment: .leading, spacing: 4) {
                    // Sin etiqueta propia: dentro del Form, el título del TextField se va a la
                    // columna de etiquetas, la ensancha y descoloca todas las filas.
                    TextField("", text: $author, prompt: Text("Tu nombre o el de tu estudio"))
                        .labelsHidden()
                        .frame(width: 220)
                    Text("Se guarda en los vídeos del Slideshow y se propone como Artista en Metadatos.")
                        .font(.caption).foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true) // que baje de línea en vez de cortarse
                }
            }
            Divider().padding(.vertical, 4)
            LabeledRow("Presets") {
                VStack(alignment: .leading, spacing: 6) {
                    Text("\(store.totalCount) presets guardados (Procesador, Marca de agua, Collage, Renombrador, Contact Sheet y plantillas del Slideshow)").font(.caption).foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                    HStack {
                        Button("Exportar…") { exportPresets() }.disabled(store.totalCount == 0)
                        Button("Importar…") { importPresets() }
                    }
                    if let presetMessage {
                        Text(presetMessage).font(.caption).foregroundStyle(.secondary)
                    }
                }
            }
        }
        .padding(20)
        .frame(width: 420)
    }

    /// Todos los presets a un fichero JSON, para llevarlos a otro Mac o compartirlos.
    private func exportPresets() {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.json]
        panel.nameFieldStringValue = "CAOBA-presets.json"
        guard panel.runFromStartFolder() == .OK, let url = panel.url else { return }
        do {
            try store.exportData().write(to: url)
            presetMessage = L("Exportados ") + "\(store.totalCount)" + L(" presets.")
        } catch {
            presetMessage = JobRunner.describe(error)
        }
    }

    private func importPresets() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.json]
        guard panel.runFromStartFolder() == .OK, let url = panel.url else { return }
        do {
            let count = try store.importData(Data(contentsOf: url))
            presetMessage = L("Importados ") + "\(count)" + L(" presets.")
        } catch {
            presetMessage = L("El fichero no es una exportación de presets de CAOBA.")
        }
    }
}
