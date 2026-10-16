import SwiftUI
import CaobaCore

/// Cómo se reparten las fotos al componer una secuencia de collages.
enum ComposeMode: String, CaseIterable, Identifiable {
    case random, content
    var id: String { rawValue }
}

/// Avance del análisis de fotos: cuántas van y cuántas hay.
struct ComposeProgress: Equatable {
    var done: Int
    var total: Int
}

/// Análisis de fotos y reparto por contenido, compartido por Collage y Slideshow.
enum ContentComposition {
    /// Perfil de cada foto (proporción, sujeto, caras) usando el detector con su
    /// caché. Va en paralelo (el detector limita la concurrencia) y se puede
    /// cancelar; `progress` recibe cuántas van.
    static func profiles(for files: [URL], detector: FocusDetector,
                         progress: @escaping @MainActor (Int) -> Void) async throws -> [PhotoProfile] {
        var results = Array<PhotoProfile?>(repeating: nil, count: files.count)
        try await withThrowingTaskGroup(of: (Int, PhotoProfile).self) { group in
            for (index, url) in files.enumerated() {
                group.addTask {
                    try Task.checkCancellation()
                    let size = ImageIOHelpers.displaySize(of: url)
                    let aspect = size.map { Double($0.width) / Double(max(1, $0.height)) } ?? 1
                    let focus = await detector.focus(for: url, mode: .faces)
                    return (index, PhotoProfile(aspectRatio: aspect, subject: focus.subject, faceCount: focus.faceCount))
                }
            }
            var done = 0
            for try await (index, profile) in group {
                results[index] = profile
                done += 1
                let count = done
                await progress(count)
            }
        }
        return results.map { $0 ?? PhotoProfile(aspectRatio: 1) }
    }

    /// Resultado listo para la app: el nuevo orden de ficheros y la secuencia.
    struct Result {
        var order: [URL]
        var sequence: [SequenceItem]
    }

    /// Analiza y reparte. El orden devuelto incluye las fotos sobrantes al final,
    /// para que la lista de la app siga siendo la fuente de verdad.
    static func compose(files: [URL], templates: [CollageTemplate], allowReorder: Bool, detector: FocusDetector,
                        progress: @escaping @MainActor (Int) -> Void) async throws -> Result {
        let profiles = try await profiles(for: files, detector: detector, progress: progress)
        try Task.checkCancellation()
        let (rows, leftover) = ContentComposer.compose(profiles: profiles, templates: templates, allowReorder: allowReorder)
        let order = (rows.flatMap(\.photoIndices) + leftover).map { files[$0] }
        let sequence = rows.map { SequenceItem(templateID: $0.template.id, focusPoints: $0.focusPoints) }
        return Result(order: order, sequence: sequence)
    }
}

/// Selector «Reparto» y casilla de reordenar, iguales en las dos hojas de Componer.
struct ComposeModeControls: View {
    @Binding var mode: ComposeMode
    @Binding var allowReorder: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            LabeledRow("Reparto") {
                Picker("", selection: $mode) {
                    Text("Aleatorio").tag(ComposeMode.random)
                    Text("Según el contenido").tag(ComposeMode.content)
                }
                .pickerStyle(.segmented).fixedSize()
                .labelsHidden()
            }
            if mode == .content {
                Toggle("Permitir reordenar fotos", isOn: $allowReorder).toggleStyle(.checkbox)
                    .padding(.leading, 130 + 8)
            }
        }
    }
}

/// Línea de progreso del análisis con su botón de cancelar.
struct ComposeProgressView: View {
    let progress: ComposeProgress
    let cancel: () -> Void

    var body: some View {
        HStack(spacing: 8) {
            ProgressView().controlSize(.small)
            Text("Analizando \(progress.done) de \(progress.total) fotos…").font(.caption).foregroundStyle(.secondary)
            Button("Cancelar") { cancel() }.controlSize(.small)
        }
    }
}
