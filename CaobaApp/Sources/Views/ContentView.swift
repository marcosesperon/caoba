import SwiftUI
import CaobaCore

/// Ventana principal: barra lateral con los módulos y, a la derecha, la barra
/// de carpeta, el módulo activo y la barra de destino.
struct ContentView: View {
    @Environment(AppState.self) private var appState

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
            }
            .navigationSplitViewColumnWidth(min: 190, ideal: 210)
            .safeAreaInset(edge: .bottom) { sidebarFooter }
        } detail: {
            VStack(spacing: 12) {
                if appState.showUpdateBanner, let update = appState.availableUpdate {
                    UpdateBanner(update: update)
                        .transition(.move(edge: .top).combined(with: .opacity))
                }
                if appState.currentModule.usesSourceFolder {
                    SourceFolderBar()
                }
                Group {
                    if appState.currentModule.isAvailable {
                        moduleView(appState.currentModule)
                    } else {
                        ComingSoonView(module: appState.currentModule)
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                DestinationBar(kind: appState.currentModule.destinationKind)
            }
            .padding(12)
            .animation(.default, value: appState.showUpdateBanner)
            .navigationTitle("CAOBA")
            .navigationSubtitle(appState.currentModule.title)
        }
        .jobPresentation(appState.jobRunner)
        .sheet(isPresented: $state.showDonationPrompt) { DonationSheet() }
        .sheet(isPresented: Binding(get: { appState.whatsNewSections != nil }, set: { if !$0 { appState.whatsNewSections = nil } })) {
            WhatsNewSheet(sections: appState.whatsNewSections ?? [], title: appState.whatsNewTitle)
        }
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
        case .contactSheet: ContactSheetView()
        case .processor: ProcessorView()
        case .watermark: WatermarkView()
        case .metadata: MetadataView()
        case .renamer: RenamerView()
        case .qr: QRView()
        case .shutterCount: ShutterCountView()
        }
    }

    private var sidebarFooter: some View {
        VStack(alignment: .leading, spacing: 6) {
            Divider()
            if let update = appState.availableUpdate {
                Button {
                    appState.openExternal(update.url)
                } label: {
                    Label("Nueva versión \(update.version)", systemImage: "arrow.down.circle")
                }
                .buttonStyle(.link)
            }
            HStack {
                Text("CAOBA").font(.caobaTitle(14))
                Spacer()
                Text("v\(CaobaCoreInfo.version)").font(.caption).foregroundStyle(.secondary)
            }
            Button {
                appState.openExternal(AppState.websiteURL)
            } label: {
                Text("caobafoto.com").font(.caption)
            }
            .buttonStyle(.link)
            Button {
                appState.openExternal(AppState.donationURL)
            } label: {
                Label("Hacer donación", systemImage: "cup.and.saucer").font(.caption)
            }
            .buttonStyle(.link)
        }
        .padding(10)
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

/// Preferencias: idioma, apariencia, autor y presets.
struct SettingsView: View {
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
                    TextField("Tu nombre o el de tu estudio", text: $author)
                    Text("Se guarda en los vídeos del Slideshow y se propone como Artista en Metadatos.")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
            Divider().padding(.vertical, 4)
            LabeledRow("Presets") {
                VStack(alignment: .leading, spacing: 6) {
                    Text("\(store.totalCount) presets guardados (Procesador, Marca de agua y Collage)").font(.caption).foregroundStyle(.secondary)
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
        guard panel.runModal() == .OK, let url = panel.url else { return }
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
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            let count = try store.importData(Data(contentsOf: url))
            presetMessage = L("Importados ") + "\(count)" + L(" presets.")
        } catch {
            presetMessage = L("El fichero no es una exportación de presets de CAOBA.")
        }
    }
}
