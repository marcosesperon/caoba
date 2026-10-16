import SwiftUI
import CaobaCore

/// Collage renderizado con el motor y las opciones reales de salida, a
/// resolución de pantalla. Se vuelve a calcular solo cuando cambia la fila
/// (encuadres, plantilla, fotos) o las opciones.
struct CollageResultView: View {
    let row: CollageRow
    let options: CollageOptions

    /// Lado mayor del render de pantalla: suficiente para juzgar el resultado sin esperar al tamaño final.
    static let previewSide = 1600

    @State private var image: CGImage?
    @State private var errorText: String?

    private struct RenderKey: Equatable {
        var row: CollageRow
        var options: CollageOptions
    }

    var body: some View {
        ZStack {
            if let image {
                Image(decorative: image, scale: 1).resizable().scaledToFit()
                    .shadow(color: .black.opacity(0.25), radius: 8, y: 3)
                    .padding(12)
            } else if let errorText {
                ContentUnavailableView("No se pudo renderizar", systemImage: "exclamationmark.triangle", description: Text(errorText))
            } else {
                ProgressView("Renderizando…").controlSize(.small)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .task(id: RenderKey(row: row, options: options)) { await render() }
    }

    private func render() async {
        var scaled = options
        scaled.longestSide = min(options.longestSide, Self.previewSide)
        let row = row
        // Mientras se calcula el nuevo se deja el anterior a la vista; si cambia la clave, la tarea se cancela.
        let result = await Task.detached(priority: .userInitiated) { () -> Result<CGImage, Error> in
            do { return .success(try CollageRenderer.render(row, options: scaled)) } catch { return .failure(error) }
        }.value
        guard !Task.isCancelled else { return }
        switch result {
        case .success(let cg): image = cg; errorText = nil
        case .failure(let error): image = nil; errorText = JobRunner.describe(error)
        }
    }
}

/// Conmutador «Encuadre / Resultado» de los editores de collage.
struct CollageViewModePicker: View {
    @Binding var showResult: Bool
    var body: some View {
        Picker("", selection: $showResult) {
            Text("Encuadre").tag(false)
            Text("Resultado").tag(true)
        }
        .pickerStyle(.segmented).fixedSize()
        .labelsHidden()
    }
}
