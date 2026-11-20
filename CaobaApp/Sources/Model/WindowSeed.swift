import Foundation

/// Con qué arranca una ventana: su sesión o su carpeta suelta, su módulo y si sale con la lista
/// de sesiones desplegada. Es el valor de `WindowGroup(for:)` al abrir una ventana nueva y lo que
/// se guarda de cada ventana al cerrar la app para volver a abrirlas todas.
struct WindowSeed: Codable, Hashable {
    /// Distinto en cada ventana: `openWindow(value:)` con un valor igual al de una ventana
    /// abierta la trae al frente en lugar de abrir otra.
    var id = UUID()
    /// Carpeta de la sesión de la ventana.
    var sessionPath: String?
    /// Sin sesión: la carpeta suelta que tenía abierta.
    var folderPath: String?
    /// `Module.rawValue`.
    var module: String?
    /// Ventana nueva de ⌘N: sale con la lista de sesiones abierta para elegir una.
    var showSessionList = false
}
