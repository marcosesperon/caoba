# CAOBA

Utilidades de fotografía para macOS (y, más adelante, iOS) del estudio [CAOBA](https://caobafoto.com/).
Reescritura nativa en Swift de [caoba-foto-utils](https://github.com/marcosesperon/caoba-foto-utils) (Electron).

## Estructura

- `CaobaCore/`: paquete Swift con el motor (imagen, metadatos, renombrado, QR...). Sin interfaz. Se prueba con `swift test`.
- `CaobaApp/`: app SwiftUI de macOS.
- `project.yml`: definición del proyecto Xcode para [XcodeGen](https://github.com/yonaskolb/XcodeGen).
- `docs/`: análisis, decisiones y documentación.

## Desarrollo

```bash
brew install xcodegen
Tools/fetch-exiftool.sh      # descarga exiftool para Shutter Count (opcional)
xcodegen generate            # crea CAOBA.xcodeproj (no se versiona)
open CAOBA.xcodeproj
cd CaobaCore && swift test   # tests del motor sin abrir Xcode
```

Requisitos: Xcode 16 o superior, macOS 14 como mínimo para ejecutar la app.

## Estado

Migración por fases. Hechas: (a) Procesador, Marca de agua, Renombrador, Código QR y Metadatos; (b) Collage y Contact Sheet; (c) Slideshow con Ken Burns, música y modo collage. (d) Shutter Count con exiftool empaquetado. Pendiente: (e) iOS. Ver `docs/decisiones.md`.
