import SwiftUI

/// Barra inferior compartida de destino. Para módulos de carpeta ofrece
/// copia nueva / sobrescribir y la carpeta de salida.
struct DestinationBar: View {
    @Environment(AppState.self) private var appState
    let kind: DestinationKind

    var body: some View {
        @Bindable var state = appState
        switch kind {
        case .none:
            EmptyView()
        case .folder:
            HStack(spacing: 12) {
                LabeledRow("Guardar") {
                    Picker("", selection: $state.destinationMode) {
                        Text("Copias nuevas").tag(DestinationModeChoice.newCopy)
                        Text("Sobrescribir originales").tag(DestinationModeChoice.overwrite)
                    }
                    .pickerStyle(.segmented)
                    .fixedSize()
                    .labelsHidden()
                }

                if appState.destinationMode == .newCopy {
                    Image(systemName: "arrow.right").foregroundStyle(.secondary)
                    Text(appState.destinationFolder?.path ?? String(localized: "Misma carpeta (con sufijo)"))
                        .lineLimit(1).truncationMode(.middle)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    Button("Elegir…") { appState.chooseDestinationFolder() }
                } else {
                    // El Renombrador deja historial y se puede deshacer; el resto recomprime y no.
                    if appState.currentModule == .renamer {
                        Label("Los archivos se renombran en su sitio. Podrás deshacerlo desde el historial.", systemImage: "arrow.uturn.backward.circle")
                            .font(.callout).foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    } else {
                        Label("Los archivos originales se reemplazan. Esta acción no se puede deshacer.", systemImage: "exclamationmark.triangle")
                            .font(.callout).foregroundStyle(.orange)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
            }
            .padding(10)
            .background(Color(nsColor: .controlBackgroundColor))
            .clipShape(RoundedRectangle(cornerRadius: 8))
        case .outputFolder:
            HStack(spacing: 12) {
                Image(systemName: "folder.badge.plus").foregroundStyle(.secondary)
                Text("Carpeta de salida").foregroundStyle(.secondary)
                Text(appState.destinationFolder?.path ?? String(localized: "Elige una carpeta"))
                    .lineLimit(1).truncationMode(.middle)
                    .frame(maxWidth: .infinity, alignment: .leading)
                Button("Elegir…") { appState.chooseDestinationFolder() }
            }
            .padding(10)
            .background(Color(nsColor: .controlBackgroundColor))
            .clipShape(RoundedRectangle(cornerRadius: 8))
        case .file:
            HStack {
                Image(systemName: "arrow.down.doc").foregroundStyle(.secondary)
                Text(appState.destinationFile?.path ?? String(localized: "Elige dónde guardar el resultado"))
                    .lineLimit(1).truncationMode(.middle)
                    .frame(maxWidth: .infinity, alignment: .leading)
                Button("Elegir…") { appState.chooseDestinationFile(contentTypes: appState.destinationFileTypes) }
            }
            .padding(10)
            .background(Color(nsColor: .controlBackgroundColor))
            .clipShape(RoundedRectangle(cornerRadius: 8))
        }
    }
}
