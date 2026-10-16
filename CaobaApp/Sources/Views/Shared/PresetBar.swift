import SwiftUI

/// Menú «Preset» de la cabecera de un módulo: aplica, guarda, actualiza y
/// elimina presets con nombre, y vuelve a los valores por defecto. El nombre
/// que muestra es el del preset cuyos ajustes coinciden con los actuales.
struct PresetBar<S: Codable & Equatable>: View {
    let module: PresetModule
    let current: S
    let defaults: S
    let apply: (S) -> Void

    @State private var store = PresetStore.shared
    /// Último preset aplicado o guardado en esta sesión (para «Actualizar» y «Eliminar»).
    @State private var lastUsed: String?
    @State private var askName = false
    @State private var newName = ""

    private var presets: [NamedPreset<S>] { store.presets(module, as: S.self) }
    private var active: NamedPreset<S>? { presets.first { $0.settings == current } }

    var body: some View {
        Menu {
            if presets.isEmpty {
                Text("Sin presets guardados")
            }
            ForEach(presets) { preset in
                Button {
                    apply(preset.settings)
                    lastUsed = preset.name
                } label: {
                    if preset.settings == current { Label(preset.name, systemImage: "checkmark") } else { Text(preset.name) }
                }
            }
            Divider()
            Button("Guardar como…") { newName = lastUsed ?? ""; askName = true }
            if let name = lastUsed, let preset = presets.first(where: { $0.name == name }), preset.settings != current {
                Button("Actualizar «\(name)» con los ajustes actuales") { store.save(current, named: name, module: module) }
            }
            if let name = lastUsed, presets.contains(where: { $0.name == name }) {
                Button("Eliminar «\(name)»", role: .destructive) {
                    store.delete(named: name, module: module, as: S.self)
                    lastUsed = nil
                }
            }
            Divider()
            Button("Valores por defecto") { apply(defaults); lastUsed = nil }
        } label: {
            Label(active?.name ?? String(localized: "Sin preset"), systemImage: "slider.horizontal.3")
        }
        .fixedSize()
        .alert("Nombre del preset", isPresented: $askName) {
            TextField("Nombre", text: $newName)
            Button("Guardar") {
                let name = newName.trimmingCharacters(in: .whitespaces)
                guard !name.isEmpty else { return }
                store.save(current, named: name, module: module)
                lastUsed = name
            }
            Button("Cancelar", role: .cancel) {}
        } message: {
            Text("Si ya existe un preset con ese nombre, se sustituye.")
        }
    }
}
