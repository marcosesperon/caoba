import Foundation
import Observation
import CaobaCore

/// Las sesiones del estudio: la estructura de Ajustes, la lista de la carpeta raíz y la
/// sesión activa (común a toda la app y recordada al cerrarla).
@MainActor
@Observable
final class StudioSessions {
    static let layoutKey = "caoba.sessions.layout"
    static let activeKey = "caoba.sessions.active"

    /// Cómo organiza el estudio sus carpetas. Al cambiarla se guarda y se vuelve a leer la lista.
    var layout: SessionLayout {
        didSet {
            guard layout != oldValue else { return }
            if let data = try? JSONEncoder().encode(layout) { UserDefaults.standard.set(data, forKey: Self.layoutKey) }
            refresh()
        }
    }
    /// Sesiones encontradas en la raíz, de la más reciente a la más antigua.
    private(set) var list: [StudioSession] = []
    private(set) var active: StudioSession?

    init() {
        layout = UserDefaults.standard.data(forKey: Self.layoutKey)
            .flatMap { try? JSONDecoder().decode(SessionLayout.self, from: $0) } ?? SessionLayout()
        // La sesión activa se recuerda por su carpeta; si ya no existe, se empieza sin sesión.
        if let path = UserDefaults.standard.string(forKey: Self.activeKey), FileManager.default.fileExists(atPath: path) {
            active = layout.session(containing: URL(fileURLWithPath: path, isDirectory: true))
        }
        refresh()
    }

    /// Vuelve a leer la carpeta raíz (al abrir el selector, por si se han creado sesiones por fuera).
    func refresh() {
        list = layout.sessions()
        // Con otra estructura (otro formato de fecha…) la activa puede dejar de reconocerse.
        if let current = active { active = layout.session(containing: current.folder) }
        updateDialogFolders()
    }

    /// Cambia la sesión activa (o la quita con `nil`). Con `remember: false` (capturas y
    /// pruebas) no se guarda, para no cambiar la sesión del usuario.
    func activate(_ session: StudioSession?, remember: Bool = true) {
        active = session
        updateDialogFolders()
        guard remember else { return }
        if let session {
            UserDefaults.standard.set(session.folder.path, forKey: Self.activeKey)
        } else {
            UserDefaults.standard.removeObject(forKey: Self.activeKey)
        }
    }

    /// Crea una sesión con sus carpetas y la añade a la lista.
    func create(date: Date, name: String) throws -> StudioSession {
        let session = try layout.createSession(date: date, name: name)
        refresh()
        return list.first { $0.id == session.id } ?? session
    }

    /// Si una sesión no tiene la carpeta de fotos finales (`JPG`).
    func lacksFinals(_ session: StudioSession) -> Bool {
        var isDir: ObjCBool = false
        return !(FileManager.default.fileExists(atPath: layout.finals(of: session).path, isDirectory: &isDir) && isDir.boolValue)
    }

    /// Crea la carpeta de fotos finales (`JPG`) de una sesión que no la tiene.
    func createFinals(for session: StudioSession) throws {
        try FileManager.default.createDirectory(at: layout.finals(of: session), withIntermediateDirectories: true)
    }

    private func updateDialogFolders() {
        DialogFolders.sessionFolder = active?.folder
        DialogFolders.rootFolder = layout.root
    }
}
