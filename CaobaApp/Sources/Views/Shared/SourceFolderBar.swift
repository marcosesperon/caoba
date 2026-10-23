import SwiftUI
import UniformTypeIdentifiers
import CaobaCore

/// Barra superior compartida: carpeta de origen, recientes, contador y
/// arrastrar y soltar. Es la misma para todos los módulos que usan carpeta.
struct SourceFolderBar: View {
    @Environment(AppState.self) private var appState
    @State private var isTargeted = false
    @State private var confirmReset = false

    var body: some View {
        @Bindable var state = appState
        HStack(spacing: 10) {
            Image(systemName: "folder").foregroundStyle(.secondary)
            Text(appState.sourceFolder?.path ?? String(localized: "Empieza eligiendo o arrastrando una carpeta de fotos"))
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

            if appState.hasFolderConfig {
                Label("Configuración restaurada", systemImage: "checkmark.circle")
                    .font(.callout).foregroundStyle(.secondary)
                // Borra lo guardado de la carpeta y no se puede deshacer: se pide confirmación.
                Button("Reiniciar") { confirmReset = true }
                    .controlSize(.small)
                    .help("Borra la configuración guardada en esta carpeta. El historial de renombrados se conserva.")
            }

            if !appState.recentFolders.isEmpty {
                Menu {
                    ForEach(appState.recentFolders, id: \.self) { url in
                        Button(url.lastPathComponent) { Task { await appState.selectSourceFolder(url) } }
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

            Button("Elegir carpeta…") { appState.chooseSourceFolder() }
        }
        .caobaDropPanel(isTargeted: isTargeted, highlighted: appState.sourceFolder == nil)
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
