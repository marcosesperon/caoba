import SwiftUI
import CaobaCore

/// Punto de entrada de la app de macOS.
@main
struct CaobaApp: App {
    /// Lo de toda la app; cada ventana crea su propio `AppState` en `WindowRoot`.
    @State private var app = AppModel()
    @NSApplicationDelegateAdaptor(CaobaAppDelegate.self) private var appDelegate
    @AppStorage(Preferences.appearanceKey) private var appearance: Appearance = .system
    @AppStorage(Preferences.languageKey) private var language: AppLanguage = .system

    var body: some Scene {
        // Varias ventanas, cada una con su sesión. El valor es con qué arranca cada una.
        WindowGroup(for: WindowSeed.self) { $seed in
            WindowRoot(app: app, seed: seed)
                .environment(\.locale, language.locale)
                .preferredColorScheme(appearance.colorScheme)
                .frame(minWidth: 960, minHeight: 640)
        }
        .defaultSize(width: 1200, height: 780)
        .commands { CaobaCommands(app: app) }

        Settings {
            SettingsView()
                .environment(app)
                .environment(\.locale, language.locale)
        }
    }
}

/// Sin la restauración de ventanas de macOS: CAOBA vuelve a abrir las suyas, cada una con su
/// sesión (`AppState.startAsFirstWindow`), y con la de macOS saldrían repetidas.
final class CaobaAppDelegate: NSObject, NSApplicationDelegate {
    func application(_ app: NSApplication, shouldSaveSecureApplicationState coder: NSCoder) -> Bool { false }
    func application(_ app: NSApplication, shouldRestoreSecureApplicationState coder: NSCoder) -> Bool { false }
    func applicationSupportsSecureRestorableState(_ app: NSApplication) -> Bool { true }
}

/// Menús de la app: «Nueva ventana» (⌘N), «Abrir carpeta…» (⌘O) en la ventana de delante y
/// «Novedades de CAOBA».
struct CaobaCommands: Commands {
    let app: AppModel
    @FocusedValue(\.windowState) private var window
    @Environment(\.openWindow) private var openWindow

    var body: some Commands {
        CommandGroup(replacing: .newItem) {
            // Sin sesión y con la lista de sesiones desplegada para elegir una.
            Button("Nueva ventana") { openWindow(value: WindowSeed(showSessionList: true)) }
                .keyboardShortcut("n")
        }
        CommandGroup(after: .newItem) {
            Button("Abrir carpeta…") { window?.chooseSourceFolder() }
                .keyboardShortcut("o")
                // Con sesión, el origen es el suyo: no se puede abrir otra carpeta.
                .disabled(!(window?.canChangeSource ?? false))
        }
        CommandGroup(after: .help) {
            Button("Novedades de CAOBA") { app.showAllWhatsNew() }
        }
    }
}
