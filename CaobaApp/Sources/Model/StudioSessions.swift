import Foundation
import Observation
import CaobaCore

/// Las sesiones del estudio: la estructura de Ajustes y la lista de la carpeta raíz, comunes
/// a toda la app. La sesión activa es de cada ventana (`AppState.activeSession`).
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

    init() {
        layout = UserDefaults.standard.data(forKey: Self.layoutKey)
            .flatMap { try? JSONDecoder().decode(SessionLayout.self, from: $0) } ?? SessionLayout()
        refresh()
    }

    /// Vuelve a leer la carpeta raíz (al abrir el selector, por si se han creado sesiones por fuera).
    func refresh() {
        list = layout.sessions()
        DialogFolders.rootFolder = layout.root
    }

    /// Guarda la sesión con la que se trabaja (o ninguna), para volver a ella al abrir la app.
    static func remember(_ session: StudioSession?) {
        if let session {
            UserDefaults.standard.set(session.folder.path, forKey: activeKey)
        } else {
            UserDefaults.standard.removeObject(forKey: activeKey)
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
}
