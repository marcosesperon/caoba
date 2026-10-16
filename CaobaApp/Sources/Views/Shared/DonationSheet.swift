import SwiftUI

/// Hoja que pide apoyo al proyecto. La enseña `AppState.scheduleDonationPrompt`
/// al arrancar, como mucho una vez cada 7 días.
struct DonationSheet: View {
    @Environment(AppState.self) private var appState
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 18) {
            Image(nsImage: NSApp.applicationIconImage)
                .resizable()
                .frame(width: 72, height: 72)
            Text("CAOBA es gratuito")
                .font(.caobaTitle(20))
            VStack(spacing: 10) {
                Text("CAOBA es un proyecto completamente gratuito que se mantiene gracias a la dedicación y el trabajo continuo.")
                Text("Si te ha resultado útil y quieres apoyar el desarrollo de nuevas funcionalidades, considera hacer una pequeña donación.")
            }
            .multilineTextAlignment(.center)
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
            VStack(spacing: 2) {
                Text("¡Gracias!").fontWeight(.semibold)
                Text("— Marcos Esperón").font(.caption).foregroundStyle(.secondary)
                Button("caobafoto.com") { appState.openExternal(AppState.websiteURL) }
                    .buttonStyle(.link)
                    .font(.caption)
                    .focusable(false) // que el foco inicial de la hoja no caiga en el enlace
            }
            HStack(spacing: 10) {
                Button("Ahora no") { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button {
                    appState.openExternal(AppState.donationURL)
                    dismiss()
                } label: {
                    Label("Hacer donación", systemImage: "cup.and.saucer")
                }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.defaultAction)
            }
            .padding(.top, 4)
        }
        .padding(28)
        .frame(width: 400)
    }
}

/// Banda fina sobre el contenido cuando hay una versión más nueva publicada.
struct UpdateBanner: View {
    @Environment(AppState.self) private var appState
    let update: VersionCheck.Release

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "arrow.down.circle.fill")
                .foregroundStyle(Color.accentColor)
            Text("Nueva versión \(update.version) disponible")
                .font(.callout)
            Spacer()
            Button("Descargar") { appState.openExternal(update.url) }
                .controlSize(.small)
            Button { appState.dismissUpdateBanner() } label: {
                Image(systemName: "xmark")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
            .help("Cerrar aviso")
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 8))
    }
}
