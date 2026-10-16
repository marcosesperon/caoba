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
            .navigationTitle("CAOBA")
            .navigationSubtitle(appState.currentModule.title)
        }
        .jobPresentation(appState.jobRunner)
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
                appState.openExternal(URL(string: "https://caobafoto.com/")!)
            } label: {
                Text("caobafoto.com").font(.caption)
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

/// Preferencias: idioma y apariencia.
struct SettingsView: View {
    @AppStorage(Preferences.appearanceKey) private var appearance: Appearance = .system
    @AppStorage(Preferences.languageKey) private var language: AppLanguage = .system

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
        }
        .padding(20)
        .frame(width: 360)
    }
}
