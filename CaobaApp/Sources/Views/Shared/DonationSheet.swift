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

/// Banda roja sobre el contenido cuando hay una versión más nueva publicada.
/// Va en el color de acento con texto blanco para que no pase desapercibida.
struct UpdateBanner: View {
    @Environment(AppState.self) private var appState
    let update: VersionCheck.Release
    @State private var updater = Updater.shared

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "arrow.down.circle.fill")
            switch updater.phase {
            case .downloading(let fraction):
                Text("Descargando CAOBA \(update.version)…").font(.callout)
                ProgressView(value: fraction).frame(width: 140).tint(.white)
                Button("Cancelar") { updater.cancel() }.buttonStyle(BannerButtonStyle())
            case .verifying:
                Text("Comprobando la descarga…").font(.callout)
                ProgressView().controlSize(.small).tint(.white)
            case .installing:
                Text("Instalando…").font(.callout)
                ProgressView().controlSize(.small).tint(.white)
            case .relaunching:
                Text("Reiniciando CAOBA…").font(.callout)
            case .manual(let message), .failed(let message):
                Text(message).font(.callout).lineLimit(2)
                Button("Abrir en el navegador") { appState.openExternal(update.url) }.buttonStyle(BannerButtonStyle())
            case .idle:
                Text("Nueva versión \(update.version) disponible").font(.callout.weight(.semibold))
            }
            Spacer()
            if case .idle = updater.phase {
                Button(update.dmg != nil ? "Actualizar ahora" : "Descargar") {
                    if update.dmg != nil { updater.update(to: update) } else { appState.openExternal(update.url) }
                }
                .buttonStyle(BannerButtonStyle())
            }
            Button { appState.dismissUpdateBanner() } label: {
                Image(systemName: "xmark")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.white.opacity(0.85))
            }
            .buttonStyle(.plain)
            .help("Cerrar aviso")
        }
        .foregroundStyle(.white)
        .environment(\.colorScheme, .dark) // controles del sistema (spinner) en claro sobre el rojo
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(Color.accentColor, in: RoundedRectangle(cornerRadius: 8))
    }
}

/// Botón de la banda de versión: blanco con el texto en rojo, para que
/// resalte sobre el fondo rojo.
private struct BannerButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.callout.weight(.semibold))
            .foregroundStyle(Color.accentColor)
            .padding(.horizontal, 10)
            .padding(.vertical, 3)
            .background(.white.opacity(configuration.isPressed ? 0.8 : 1), in: RoundedRectangle(cornerRadius: 5))
    }
}
