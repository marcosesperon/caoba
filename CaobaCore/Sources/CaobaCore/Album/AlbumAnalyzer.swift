import Foundation
import CoreGraphics

/// Analiza una foto para el álbum: caras (cada una por separado) y punto de encuadre. Trabaja
/// sobre una miniatura de 1024 px, como el resto de detecciones de CAOBA.
public enum AlbumAnalyzer {
    /// Completa la información de una foto con sus caras y su foco. Si no se puede leer la foto,
    /// la deja sin caras y centrada, para no volver a intentarlo en cada vuelta.
    public static func analyze(_ url: URL, info: AlbumPhotoInfo) -> AlbumPhotoInfo {
        var result = info
        guard let image = ThumbnailProvider.makeThumbnail(url: url, maxPixelSize: 1024) else {
            result.faces = []
            result.focus = CGPoint(x: 0.5, y: 0.5)
            return result
        }
        let focus = FocusDetector.detect(image: image, mode: .faces)
        result.faces = focus.faces
        result.focus = focus.point
        return result
    }
}
