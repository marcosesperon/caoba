import SwiftUI

/// Claves de preferencias guardadas en UserDefaults.
enum Preferences {
    static let appearanceKey = "caoba.appearance"
    static let languageKey = "caoba.language"
    static let recentFoldersKey = "caoba.recentFolders"
    static let donationLastShownKey = "caoba.donation.lastShown"
    static let lastSeenVersionKey = "caoba.lastSeenVersion"
    static let authorKey = "caoba.author"

    /// Autor de Ajustes sin espacios sobrantes; nil si no se ha puesto.
    static var author: String? {
        let text = UserDefaults.standard.string(forKey: authorKey)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return text.isEmpty ? nil : text
    }
}

/// Tema claro / oscuro / el del sistema.
enum Appearance: String, CaseIterable, Identifiable {
    case system, light, dark

    var id: String { rawValue }

    var colorScheme: ColorScheme? {
        switch self {
        case .system: return nil
        case .light: return .light
        case .dark: return .dark
        }
    }

    var title: LocalizedStringKey {
        switch self {
        case .system: return "Sistema"
        case .light: return "Claro"
        case .dark: return "Oscuro"
        }
    }
}

/// Idioma de la interfaz. "Sistema" sigue al Mac; los otros fuerzan uno.
enum AppLanguage: String, CaseIterable, Identifiable {
    case system, spanish = "es", english = "en"

    var id: String { rawValue }

    var locale: Locale {
        switch self {
        case .system: return .autoupdatingCurrent
        case .spanish: return Locale(identifier: "es")
        case .english: return Locale(identifier: "en")
        }
    }

    var title: LocalizedStringKey {
        switch self {
        case .system: return "Sistema"
        case .spanish: return "Español"
        case .english: return "English"
        }
    }
}

/// Texto localizado para usar fuera de las vistas (mensajes, errores), con el
/// idioma elegido en preferencias.
func L(_ key: String.LocalizationValue) -> String {
    let raw = UserDefaults.standard.string(forKey: Preferences.languageKey) ?? AppLanguage.system.rawValue
    let language = AppLanguage(rawValue: raw) ?? .system
    return String(localized: key, locale: language.locale)
}
