import SwiftUI
import CaobaCore

/// Punto de entrada de la app de macOS.
@main
struct CaobaApp: App {
    @State private var appState = AppState()
    @AppStorage(Preferences.appearanceKey) private var appearance: Appearance = .system
    @AppStorage(Preferences.languageKey) private var language: AppLanguage = .system

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(appState)
                .environment(\.locale, language.locale)
                .preferredColorScheme(appearance.colorScheme)
                .frame(minWidth: 960, minHeight: 640)
                .task {
                    await appState.applyLaunchArguments()
                    // Si hay novedades que enseñar, el donativo espera al siguiente arranque.
                    if !appState.checkWhatsNew() { await appState.scheduleDonationPrompt() }
                    await appState.checkForUpdates()
                }
        }
        .defaultSize(width: 1200, height: 780)
        .commands {
            CommandGroup(replacing: .newItem) {}
            CommandGroup(after: .newItem) {
                Button("Abrir carpeta…") { appState.chooseSourceFolder() }
                    .keyboardShortcut("o")
            }
            CommandGroup(after: .help) {
                Button("Novedades de CAOBA") { appState.showAllWhatsNew() }
            }
        }

        Settings {
            SettingsView()
                .environment(appState)
                .environment(\.locale, language.locale)
        }
    }
}
