import SwiftUI
import CaobaCore

/// Ajustes › Álbumes: los tipos de álbum (nombre, medidas, márgenes, pliegos…). Son la plantilla
/// de la que sale cada álbum; cambiarlos no toca los álbumes ya creados.
struct AlbumTypesSettingsView: View {
    @State private var store = AlbumTypeStore.shared
    @State private var selection: UUID?
    @State private var confirmDelete: AlbumType?

    var body: some View {
        HStack(alignment: .top, spacing: 0) {
            VStack(spacing: 0) {
                List(selection: $selection) {
                    ForEach(store.types) { type in
                        VStack(alignment: .leading, spacing: 2) {
                            Text(type.name)
                            Text("\(AlbumSpecPreview.cm(type.spec.pageWidthMM)) × \(AlbumSpecPreview.cm(type.spec.pageHeightMM)) cm")
                                .font(.caption).foregroundStyle(.secondary)
                        }
                        .tag(type.id)
                    }
                }
                .listStyle(.bordered)
                HStack(spacing: 4) {
                    Button { selection = store.add().id } label: { Image(systemName: "plus") }
                        .help("Tipo nuevo")
                    Button {
                        if let type = store.type(id: selection) { selection = store.duplicate(type).id }
                    } label: { Image(systemName: "plus.square.on.square") }
                        .help("Duplicar")
                        .disabled(selection == nil)
                    Button { confirmDelete = store.type(id: selection) } label: { Image(systemName: "minus") }
                        .help("Borrar")
                        .disabled(selection == nil)
                    Spacer()
                }
                .buttonStyle(.borderless)
                .padding(.top, 6)
            }
            .frame(width: 170)
            .padding(.trailing, 16)

            if let type = store.type(id: selection) {
                ScrollView {
                    AlbumTypeEditor(type: type) { store.update($0) }
                        .id(type.id)
                        .padding(.trailing, 8)
                }
            } else {
                ContentUnavailableView {
                    Label("Sin tipos de álbum", systemImage: "book")
                } description: {
                    Text(store.types.isEmpty
                         ? "Crea el primero con +: nombre, medidas de la página y márgenes del laboratorio."
                         : "Elige un tipo de la lista para ver sus medidas.")
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .padding(20)
        .onAppear { if selection == nil { selection = store.types.first?.id } }
        .confirmationDialog(Text("¿Borrar el tipo «\(confirmDelete?.name ?? "")»?"),
                            isPresented: Binding(get: { confirmDelete != nil }, set: { if !$0 { confirmDelete = nil } })) {
            Button("Borrar", role: .destructive) {
                if let type = confirmDelete { store.delete(type) }
                selection = store.types.first?.id
            }
        } message: {
            Text("Los álbumes ya creados con este tipo no cambian.")
        }
    }
}

/// Ficha de un tipo. Trabaja sobre una copia y la guarda en cuanto cambia algo.
private struct AlbumTypeEditor: View {
    @State var type: AlbumType
    let onChange: (AlbumType) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            LabeledRow("Nombre") {
                TextField("", text: $type.name, prompt: Text("Por ejemplo, Laboratorio 30 × 30"))
                    .labelsHidden()
                    .frame(width: 240)
            }
            Divider()
            AlbumSpecForm(spec: $type.spec)
        }
        .onChange(of: type) {
            var cleaned = type
            cleaned.name = type.name.trimmingCharacters(in: .whitespaces)
            if !cleaned.name.isEmpty { onChange(cleaned) }
        }
    }
}
