import SwiftUI

/// Barra inferior compartida. Para módulos de carpeta ofrece copia nueva /
/// sobrescribir y la carpeta de salida; para los de fichero, dónde guardarlo.
/// Al final, separadas por una línea, van las acciones del módulo (su botón
/// principal y lo que lo acompaña), igual que en la barra del Slideshow.
/// Cada módulo la pone debajo de su vista, porque es él quien sabe qué hacen sus botones.
struct DestinationBar<Actions: View>: View {
    @Environment(AppState.self) private var appState
    let kind: DestinationKind
    let actions: Actions

    init(kind: DestinationKind, @ViewBuilder actions: () -> Actions) {
        self.kind = kind
        self.actions = actions()
    }

    var body: some View {
        HStack(spacing: 12) {
            destination
            // Sin destino (Metadatos, QR) no hay nada que separar: los botones se pegan a la derecha.
            if kind == .none {
                Spacer()
            } else {
                Divider().frame(height: 18)
            }
            // Los botones nunca se recortan: si falta sitio, cede la ruta.
            HStack(spacing: 12) { actions }
                .fixedSize()
        }
        .caobaPanel()
    }

    /// Parte izquierda de la barra: qué se guarda y dónde.
    @ViewBuilder
    private var destination: some View {
        @Bindable var state = appState
        switch kind {
        case .none:
            EmptyView()
        case .folder:
            // Etiqueta pegada al selector (sin la columna ancha de `LabeledRow`): con los
            // botones del módulo al final, a 1000 pt de ventana no cabía todo.
            Text("Guardar").fixedSize()
            Picker("", selection: $state.destinationMode) {
                Text("Copias nuevas").tag(DestinationModeChoice.newCopy)
                Text("Sobrescribir originales").tag(DestinationModeChoice.overwrite)
            }
            .pickerStyle(.segmented)
            .fixedSize()
            .labelsHidden()

            if appState.destinationMode == .newCopy {
                Image(systemName: "arrow.right").foregroundStyle(.secondary)
                // La ruta es lo que cede cuando falta sitio: se acorta por el medio.
                Text(appState.destinationFolder?.path ?? String(localized: "Misma carpeta (con sufijo)"))
                    .lineLimit(1).truncationMode(.middle)
                    .frame(minWidth: 0, maxWidth: .infinity, alignment: .leading)
                Button("Elegir…") { appState.chooseDestinationFolder() }.fixedSize()
            } else {
                // El Renombrador deja historial y se puede deshacer; el resto recomprime y no.
                if appState.currentModule == .renamer {
                    Label("Los archivos se renombran en su sitio. Podrás deshacerlo desde el historial.", systemImage: "arrow.uturn.backward.circle")
                        .font(.callout).foregroundStyle(.secondary)
                        .frame(minWidth: 0, maxWidth: .infinity, alignment: .leading)
                } else {
                    Label("Los archivos originales se reemplazan. Esta acción no se puede deshacer.", systemImage: "exclamationmark.triangle")
                        .font(.callout).foregroundStyle(.orange)
                        .frame(minWidth: 0, maxWidth: .infinity, alignment: .leading)
                }
            }
        case .outputFolder:
            Image(systemName: "folder.badge.plus").foregroundStyle(.secondary)
            Text("Carpeta de salida").foregroundStyle(.secondary)
            Text(appState.destinationFolder?.path ?? String(localized: "Elige una carpeta"))
                .lineLimit(1).truncationMode(.middle)
                .frame(minWidth: 0, maxWidth: .infinity, alignment: .leading)
            Button("Elegir…") { appState.chooseDestinationFolder() }.fixedSize()
        case .file:
            Image(systemName: "arrow.down.doc").foregroundStyle(.secondary)
            Text(appState.destinationFile?.path ?? String(localized: "Elige dónde guardar el resultado"))
                .lineLimit(1).truncationMode(.middle)
                .frame(minWidth: 0, maxWidth: .infinity, alignment: .leading)
            Button("Elegir…") { appState.chooseDestinationFile(contentTypes: appState.destinationFileTypes) }.fixedSize()
        }
    }
}
