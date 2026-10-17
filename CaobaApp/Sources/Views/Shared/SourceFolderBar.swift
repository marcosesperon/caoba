import SwiftUI
import UniformTypeIdentifiers
import CaobaCore

/// Barra superior compartida: carpeta de origen, recientes, contador y
/// arrastrar y soltar. Es la misma para todos los módulos que usan carpeta.
struct SourceFolderBar: View {
    @Environment(AppState.self) private var appState
    @State private var isTargeted = false

    var body: some View {
        @Bindable var state = appState
        HStack(spacing: 10) {
            Image(systemName: "folder").foregroundStyle(.secondary)
            Text(appState.sourceFolder?.path ?? String(localized: "Elige o arrastra una carpeta de fotos"))
                .lineLimit(1)
                .truncationMode(.middle)
                .foregroundStyle(appState.sourceFolder == nil ? .secondary : .primary)
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
                Button("Reiniciar") { appState.resetFolderConfig() }
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
            }

            Button("Elegir carpeta…") { appState.chooseSourceFolder() }
        }
        .caobaDropPanel(isTargeted: isTargeted)
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
