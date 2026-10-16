import SwiftUI
import CaobaCore

/// Hoja modal con el progreso del trabajo en curso y botón de cancelar.
struct ProgressSheet: View {
    let runner: JobRunner

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(runner.progress?.phase.label ?? String(localized: "Preparando…"))
                .font(.headline)
            if let fraction = runner.progress?.fraction {
                ProgressView(value: fraction)
                Text("\(Int((fraction * 100).rounded())) %").font(.caption.monospacedDigit()).foregroundStyle(.secondary)
            } else {
                ProgressView()
            }
            Text(runner.progress?.currentFile ?? " ")
                .font(.callout).foregroundStyle(.secondary).lineLimit(1).truncationMode(.middle)
            HStack {
                Spacer()
                Button("Cancelar") { runner.cancel() }.keyboardShortcut(.cancelAction)
            }
        }
        .padding(20)
        .frame(width: 420)
    }
}

/// Resultado del trabajo como alerta con botón "Abrir" cuando hay algo que abrir.
struct JobOutcomeAlert: ViewModifier {
    @Environment(AppState.self) private var appState
    let runner: JobRunner

    func body(content: Content) -> some View {
        content.alert(
            titleFor(runner.outcome),
            isPresented: Binding(get: { runner.outcome != nil }, set: { if !$0 { runner.outcome = nil } }),
            presenting: runner.outcome
        ) { outcome in
            if let url = outcome.openURL {
                Button("Mostrar en Finder") { appState.revealInFinder(url) }
            }
            Button("OK", role: .cancel) {}
        } message: { outcome in
            Text(outcome.message)
        }
    }

    private func titleFor(_ outcome: JobOutcome?) -> String {
        switch outcome?.kind {
        case .success: return L("Completado")
        case .warning: return L("Completado con avisos")
        case .error: return L("Error")
        case .cancelled: return L("Cancelado")
        case nil: return ""
        }
    }
}

extension View {
    /// Muestra la hoja de progreso mientras el runner trabaja y la alerta al terminar.
    func jobPresentation(_ runner: JobRunner) -> some View {
        self
            .sheet(isPresented: Binding(get: { runner.isRunning }, set: { _ in })) { ProgressSheet(runner: runner) }
            .modifier(JobOutcomeAlert(runner: runner))
    }
}
