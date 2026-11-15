import SwiftUI
import UniformTypeIdentifiers
import CaobaCore

/// Barra superior compartida: carpeta de origen, recientes, contador y
/// arrastrar y soltar. Es la misma para todos los módulos que usan carpeta.
struct SourceFolderBar: View {
    @Environment(AppState.self) private var appState
    @State private var isTargeted = false
    @State private var confirmReset = false
    /// Lista de sesiones y hoja «Nueva sesión» de «Elegir sesión…».
    @State private var showSessions = false
    @State private var showNewSession = false

    var body: some View {
        @Bindable var state = appState
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 10) {
                Image(systemName: "folder").foregroundStyle(.secondary)
                // Sin origen, lo normal es trabajar con una sesión; si no, una carpeta suelta.
                Text(appState.sourceFolder?.path ?? String(localized: "Elige la sesión con la que vas a trabajar o una carpeta de fotos"))
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .foregroundStyle(appState.sourceFolder == nil ? Color.accentColor : .primary)
                    .frame(maxWidth: .infinity, alignment: .leading)

                if appState.isScanning {
                    ProgressView().controlSize(.small)
                } else if appState.sourceFolder != nil {
                    Text("\(appState.files.count) fotos")
                        .font(.callout).foregroundStyle(.secondary)
                }
                // Para cuando se han tocado fotos por fuera (Finder, Lightroom…) después de abrir la carpeta.
                if appState.sourceFolder != nil {
                    Button("Recargar") { Task { await appState.reload() } }
                        .controlSize(.small)
                        .disabled(appState.isScanning)
                        .help("Vuelve a leer la carpeta: para cuando se han borrado, renombrado o añadido fotos por fuera.")
                }

                if appState.hasFolderConfig {
                    Label("Configuración restaurada", systemImage: "checkmark.circle")
                        .font(.callout).foregroundStyle(.secondary)
                    // Borra lo guardado de la carpeta y no se puede deshacer: se pide confirmación.
                    Button("Reiniciar") { confirmReset = true }
                        .controlSize(.small)
                        .help("Borra la configuración guardada en esta carpeta. El historial de renombrados se conserva.")
                }

                // Solo sin sesión: con sesión, el origen ya lo pone ella.
                if appState.sessions.active == nil && !appState.recentFolders.isEmpty {
                    Menu {
                        ForEach(appState.recentFolders, id: \.self) { url in
                            // Con la sesión o la carpeta de encima delante: muchas se llaman igual (JPG).
                            Button(appState.sessions.layout.displayName(of: url)) { Task { await appState.selectSourceFolder(url) } }
                                .help(url.path)
                        }
                    } label: {
                        Label("Recientes", systemImage: "clock")
                    }
                    .menuStyle(.borderlessButton)
                    .fixedSize()
                    // Sin foco de teclado: al abrir la ventana se quedaba con él (y su marco) por ser
                    // el primer control que puede tenerlo. Se usa con el ratón, como «Elegir carpeta…».
                    .focusable(false)
                }

                if appState.sourceFolder == nil {
                    Button("Elegir sesión…") {
                        appState.sessions.refresh()
                        showSessions = true
                    }
                    .buttonStyle(.borderedProminent)
                    .popover(isPresented: $showSessions, arrowEdge: .bottom) {
                        SessionList(showNew: $showNewSession, dismiss: { showSessions = false })
                            .environment(appState)
                    }
                }
                Button("Elegir carpeta…") { appState.chooseSourceFolder() }
            }
            // La sesión activa no tiene carpeta de fotos finales: el origen hay que elegirlo aquí.
            if appState.sessionLacksFinals {
                Label("Esta sesión no tiene carpeta \(appState.sessions.layout.finalsFolder): elige el origen a mano.", systemImage: "exclamationmark.triangle")
                    .font(.callout).foregroundStyle(.orange)
            }
        }
        .caobaDropPanel(isTargeted: isTargeted, highlighted: appState.sourceFolder == nil)
        .sheet(isPresented: $showNewSession) { NewSessionSheet().environment(appState) }
        .confirmationDialog("¿Reiniciar la configuración de esta carpeta?", isPresented: $confirmReset) {
            Button("Reiniciar", role: .destructive) { appState.resetFolderConfig() }
        } message: {
            Text("Se borra lo guardado para esta carpeta: todo el montaje del Slideshow (orden y selección de fotos, collages, encuadres, textos, pies, portada y créditos, música, marca de agua y ajustes del vídeo), los ajustes de «Componer» del Collage y el orden manual de las fotos.\n\nNo se tocan las fotos, los presets guardados ni el historial del Renombrador, que se puede seguir deshaciendo. Esto no se puede deshacer.")
        }
        .onDrop(of: [.fileURL], isTargeted: $isTargeted) { providers in
            guard let provider = providers.first else { return false }
            _ = provider.loadObject(ofClass: URL.self) { url, _ in
                guard let url else { return }
                Task { @MainActor in await appState.selectSourceFolder(url) }
            }
            return true
        }
    }
}
