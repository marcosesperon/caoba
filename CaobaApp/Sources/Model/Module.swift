import SwiftUI

/// Secciones de la barra lateral. Las que no están implementadas todavía
/// muestran un aviso de "próximamente".
enum Module: String, CaseIterable, Identifiable {
    case slideshow, collage, contactSheet
    case processor, watermark, metadata, renamer, qr, shutterCount, cardImport, recovery

    var id: String { rawValue }

    static let creators: [Module] = [.slideshow, .collage, .contactSheet]
    /// Lo que se hace con las fotos de una sesión, en el orden de trabajo: primero descargar la tarjeta.
    static let utilities: [Module] = [.cardImport, .processor, .watermark, .metadata, .renamer]
    /// Lo que no va con una sesión concreta.
    static let otherTools: [Module] = [.qr, .shutterCount, .recovery]

    /// Trabaja con la sesión activa. Las de «Otras herramientas» no: en ellas el título dice solo «CAOBA».
    var usesSession: Bool { !Module.otherTools.contains(self) }

    var title: LocalizedStringKey {
        switch self {
        case .slideshow: return "Slideshow"
        case .collage: return "Collage"
        case .contactSheet: return "Contact Sheet"
        case .processor: return "Procesador"
        case .watermark: return "Marca de agua"
        case .metadata: return "Metadatos"
        case .renamer: return "Renombrador"
        case .qr: return "Código QR"
        case .shutterCount: return "Shutter Count"
        case .cardImport: return "Descargar tarjeta"
        case .recovery: return "Recuperar fotos"
        }
    }

    var systemImage: String {
        switch self {
        case .slideshow: return "film"
        case .collage: return "square.grid.2x2"
        case .contactSheet: return "rectangle.grid.3x2"
        case .processor: return "crop.rotate"
        case .watermark: return "drop"
        case .metadata: return "info.circle"
        case .renamer: return "pencil.line"
        case .qr: return "qrcode"
        case .shutterCount: return "camera.aperture"
        case .cardImport: return "square.and.arrow.down"
        case .recovery: return "sdcard"
        }
    }

    /// Qué tipo de destino usa el módulo (o ninguno).
    var destinationKind: DestinationKind {
        switch self {
        case .contactSheet: return .file
        case .slideshow: return .none // el Slideshow tiene su propia barra de acción
        case .collage: return .outputFolder
        case .processor, .watermark, .renamer: return .folder
        case .metadata, .qr, .shutterCount: return .none
        case .cardImport, .recovery: return .none // tienen su propia barra de acción
        }
    }

    /// Si el módulo necesita la carpeta de origen y la lista de ficheros.
    var usesSourceFolder: Bool {
        switch self {
        case .qr, .shutterCount, .cardImport, .recovery: return false
        default: return true
        }
    }

    /// Módulos disponibles. Tras la fase (d) lo están todos; se mantiene por si
    /// alguna fase futura añade módulos a medio hacer.
    var isAvailable: Bool { true }
}

/// Modo de la barra de destino.
enum DestinationKind {
    case none
    /// Un único fichero de salida (diálogo de guardar).
    case file
    /// Carpeta de salida con elección entre copias nuevas y sobrescribir.
    case folder
    /// Solo carpeta de salida (el módulo genera ficheros nuevos siempre).
    case outputFolder
}
