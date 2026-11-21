import Foundation
@preconcurrency import UserNotifications

/// Notificaciones de macOS (fin de una descarga, de un vídeo…). La primera vez macOS pide
/// permiso; si no se da, no pasa nada.
enum SystemNotifier {
    /// Clave de `userInfo` con el id de la ventana del trabajo: al pulsar la notificación se trae al frente.
    static let windowKey = "window"

    static func post(title: String, subtitle: String? = nil, body: String, window: UUID? = nil) {
        let content = UNMutableNotificationContent()
        content.title = title
        if let subtitle { content.subtitle = subtitle }
        content.body = body
        content.sound = .default
        if let window { content.userInfo = [windowKey: window.uuidString] }
        let request = UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil)
        let center = UNUserNotificationCenter.current()
        center.requestAuthorization(options: [.alert, .sound]) { granted, _ in
            guard granted else { return }
            center.add(request)
        }
    }
}
