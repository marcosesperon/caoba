import AppKit

/// Dónde se abren los diálogos de elegir carpeta o fichero.
///
/// - El primero de cada apertura de la app, en la sesión activa o, sin sesión, en la carpeta
///   raíz de sesiones de Ajustes.
/// - Después, donde se eligió la última vez en cualquier diálogo: la carpeta que contiene a la
///   carpeta elegida (para ver las de al lado) o la del fichero elegido.
/// - No se guarda al cerrar la app: cada día se vuelve a empezar en la sesión o la raíz.
@MainActor
enum DialogFolders {
    /// Última carpeta elegida en un diálogo durante esta apertura de la app.
    private static var lastChosen: URL?
    /// Carpeta de la sesión activa y raíz de sesiones; las pone `StudioSessions` al cambiar.
    static var sessionFolder: URL?
    static var rootFolder: URL?

    /// Dónde debería abrirse un diálogo ahora mismo (solo carpetas que existan).
    static var startFolder: URL? {
        [lastChosen, sessionFolder, rootFolder].compactMap { $0 }.first { isFolder($0) }
    }

    /// Apunta lo elegido para que el siguiente diálogo se abra ahí.
    static func remember(_ picked: URL?) {
        guard let picked else { return }
        lastChosen = picked.deletingLastPathComponent()
    }

    private static func isFolder(_ url: URL) -> Bool {
        var isDir: ObjCBool = false
        return FileManager.default.fileExists(atPath: url.path, isDirectory: &isDir) && isDir.boolValue
    }
}

extension NSSavePanel {
    /// Abre el diálogo en la carpeta que toca (ver `DialogFolders`) y recuerda lo elegido.
    /// Si no hay ninguna carpeta que sirva, se abre donde decida macOS.
    func runFromStartFolder() -> NSApplication.ModalResponse {
        if let start = DialogFolders.startFolder { directoryURL = start }
        return runKeepingFolder()
    }

    /// Para los diálogos que ya se abren en una carpeta relacionada (la del fichero actual,
    /// el destino…): no se toca dónde se abren, pero lo elegido cuenta para los siguientes.
    func runKeepingFolder() -> NSApplication.ModalResponse {
        let response = runModal()
        if response == .OK {
            DialogFolders.remember((self as? NSOpenPanel)?.urls.first ?? url)
        }
        return response
    }
}
