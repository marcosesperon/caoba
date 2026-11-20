import SwiftUI
import AppKit

/// Raíz de cada ventana: crea su `AppState` (su sesión, su carpeta, su trabajo), lo apunta en
/// el `AppModel` y lo pone en el entorno. La primera ventana, además, hace lo de arrancar:
/// vuelve a abrir las ventanas que había, aplica los argumentos de las capturas y lanza los
/// avisos de toda la app (novedades, donativo, versión nueva).
struct WindowRoot: View {
    let app: AppModel
    /// Con qué arranca la ventana; `nil` en la primera y en las que abre macOS (p. ej. el Dock).
    let seed: WindowSeed?
    @State private var appState: AppState
    /// Enlace con la `NSWindow`: saber cuándo pasa al frente, cuándo se cierra y pedir permiso para cerrarla.
    @State private var link = WindowLink()
    @Environment(\.openWindow) private var openWindow

    init(app: AppModel, seed: WindowSeed?) {
        self.app = app
        self.seed = seed
        _appState = State(initialValue: AppState(app: app))
    }

    var body: some View {
        ContentView()
            .environment(appState)
            .environment(app)
            // Para los menús (⌘O): actúan sobre la ventana de delante.
            .focusedSceneValue(\.windowState, appState)
            .background(WindowObserver { window in link.attach(window, state: appState, app: app) })
            .task { await start() }
    }

    private func start() async {
        app.register(appState)
        guard !app.didLaunch else {
            if let seed { await appState.restore(seed) }
            return
        }
        // La primera ventana: las demás que había al cerrar la app se abren aparte.
        for other in await appState.startAsFirstWindow() { openWindow(value: other) }
        await appState.captureIfRequested()
        // Si hay novedades que enseñar, el donativo espera al siguiente arranque.
        if !app.checkWhatsNew() { await app.scheduleDonationPrompt() }
        await app.checkForUpdates()
    }
}

/// Lo que une una vista de SwiftUI con su `NSWindow`: pasa al frente, se cierra y, con un
/// trabajo en marcha, pide confirmación antes de cerrarla.
@MainActor
final class WindowLink {
    private weak var window: NSWindow?
    private var observers: [NSObjectProtocol] = []
    /// Delegado que envuelve al de SwiftUI; la ventana lo guarda débil, así que lo guardamos aquí.
    private var closeGuard: WindowCloseGuard?

    func attach(_ window: NSWindow, state: AppState, app: AppModel) {
        guard self.window !== window else { return }
        self.window = window
        observers.forEach(NotificationCenter.default.removeObserver)
        let center = NotificationCenter.default
        observers = [
            center.addObserver(forName: NSWindow.didBecomeKeyNotification, object: window, queue: .main) { [weak state, weak app] _ in
                MainActor.assumeIsolated { if let state { app?.bringToFront(state) } }
            },
            center.addObserver(forName: NSWindow.willCloseNotification, object: window, queue: .main) { [weak state, weak app] _ in
                MainActor.assumeIsolated {
                    guard let state else { return }
                    // Si se cerró con un trabajo en marcha (ya confirmado), se corta.
                    state.jobRunner.cancel()
                    app?.unregister(state)
                }
            },
        ]
        if window.isKeyWindow { app.bringToFront(state) }
        let guardDelegate = WindowCloseGuard(original: window.delegate) { [weak state] in
            guard let state, state.jobRunner.isRunning else { return true }
            return WindowCloseGuard.confirmClosingWithJob()
        }
        closeGuard = guardDelegate
        window.delegate = guardDelegate
    }
}

/// Delegado de la ventana que pregunta antes de cerrarla y pasa todo lo demás al de SwiftUI.
final class WindowCloseGuard: NSObject, NSWindowDelegate {
    private weak var original: NSWindowDelegate?
    private let shouldClose: @MainActor () -> Bool

    init(original: NSWindowDelegate?, shouldClose: @escaping @MainActor () -> Bool) {
        self.original = original
        self.shouldClose = shouldClose
    }

    func windowShouldClose(_ sender: NSWindow) -> Bool {
        let allowed = MainActor.assumeIsolated { shouldClose() }
        guard allowed else { return false }
        return original?.windowShouldClose?(sender) ?? true
    }

    // Lo que no es nuestro, al delegado de SwiftUI.
    override func responds(to aSelector: Selector!) -> Bool {
        super.responds(to: aSelector) || (original?.responds(to: aSelector) ?? false)
    }

    override func forwardingTarget(for aSelector: Selector!) -> Any? {
        if !super.responds(to: aSelector), original?.responds(to: aSelector) == true { return original }
        return super.forwardingTarget(for: aSelector)
    }

    /// «Hay un trabajo en marcha en esta ventana»: cerrar y cancelarlo, o seguir.
    @MainActor
    static func confirmClosingWithJob() -> Bool {
        let alert = NSAlert()
        alert.messageText = L("Hay un trabajo en marcha en esta ventana")
        alert.informativeText = L("Si cierras la ventana, el trabajo se cancela y lo que estuviera a medias no se guarda.")
        alert.alertStyle = .warning
        alert.addButton(withTitle: L("Seguir trabajando"))
        alert.addButton(withTitle: L("Cerrar y cancelar"))
        return alert.runModal() == .alertSecondButtonReturn
    }
}

/// Vista vacía que avisa en cuanto está dentro de su `NSWindow`.
struct WindowObserver: NSViewRepresentable {
    let onWindow: (NSWindow) -> Void

    func makeNSView(context: Context) -> NSView {
        let view = ObserverView()
        view.onWindow = onWindow
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {}

    private final class ObserverView: NSView {
        var onWindow: ((NSWindow) -> Void)?
        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            if let window { onWindow?(window) }
        }
    }
}

/// El `AppState` de la ventana de delante, para los menús.
struct WindowStateKey: FocusedValueKey {
    typealias Value = AppState
}

extension FocusedValues {
    var windowState: AppState? {
        get { self[WindowStateKey.self] }
        set { self[WindowStateKey.self] = newValue }
    }
}
