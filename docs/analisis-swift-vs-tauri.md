# Segundo análisis: app nativa en Swift (macOS + iOS) frente a Tauri + Rust

Objetivo: decidir la tecnología de migración de CAOBA Foto Utils. Este documento parte del inventario de `analisis-app-actual.md` y de las decisiones ya tomadas (prioridad: tamaño y rendimiento, luego mantenibilidad; sidecars aceptables; Windows prescindible si se va a Swift).

Fecha: 15-10-2026. Entorno del usuario: macOS 26.6.2, Swift 6.2.4 con Command Line Tools, **sin Xcode instalado** (necesario para apps SwiftUI, iOS y firma). cargo/rustc 1.94 instalados; sin Tauri CLI.

---

## 1. Resumen ejecutivo

| Criterio | Swift nativo (SwiftUI + frameworks Apple) | Tauri + Rust |
|---|---|---|
| Plataformas | macOS + iOS/iPadOS. **Sin Windows** | macOS + Windows (+ Linux). iOS posible pero débil (sin sidecars, sin ffmpeg) |
| Tamaño del instalable | **5-15 MB** (sin binarios externos; fuentes incluidas) | 80-120 MB con ffmpeg sidecar; 25-30 MB sin él |
| Rendimiento de vídeo | **Codificador hardware (VideoToolbox) + Core Image en GPU**. Ken Burns y transiciones sin escribir frames a disco | libx264 por software vía ffmpeg; Ken Burns por tubería de frames en CPU |
| Procesado de imagen | ImageIO + Core Image + vImage: resize Lanczos, composición, blur, texto, HEIC, RAW, metadatos sin recomprimir. Todo de serie | `image` + crates auxiliares: resize y composición bien; texto, blur, HEIC y metadatos requieren trabajo o librerías nativas |
| Caras y smart crop | **Vision**: detección de caras y mapa de saliencia (equivalente directo de `attention`), 0 MB extra | Más adelante (decidido en P3); `attention` a mano |
| EXIF y shutter count | ImageIO lee EXIF y MakerNotes **Nikon (incluido ShutterCount)**; Canon parcial; Sony/Pentax no. En macOS se puede empaquetar exiftool (Perl del sistema); en iOS **no se pueden lanzar procesos** | exiftool sidecar en macOS y Windows: todas las marcas |
| Reutilización del código actual | **0 %** del HTML/CSS/JS. Reescritura completa de la UI | HTML y CSS reutilizables; JS parcialmente (opción 3 de P2) |
| Coste de distribución | Apple Developer Program **99 USD/año** obligatorio para iOS; para macOS la app actual ya va sin firma (Gatekeeper avisa) y se podría seguir igual, pero lo razonable es firmar y notarizar | Igual que hoy: DMG sin firma funciona con aviso. Firma opcional |
| Toolchain | Xcode (≈ 12-15 GB), solo en macOS. GitHub Actions con runners macOS para CI | cargo + Node + Tauri CLI. CI multiplataforma como ahora |
| Mantenibilidad | Un lenguaje, un framework de UI, APIs estables de Apple, tests con XCTest/Swift Testing | Dos lenguajes (Rust + JS), dos runtimes, pero la UI ya existe |
| Riesgo técnico principal | Normalización de audio EBU R128 no existe en AVFoundation (hay que implementarla); gestión de color sRGB → BT.709 en AVAssetWriter; shutter count no Nikon en iOS | Rasterizar texto y SVG; HEIC; smart crop; ffmpeg como dependencia pesada |

**Conclusión corta**: para los objetivos declarados (tamaño y rendimiento primero, mantenibilidad después, Windows prescindible, interés en iOS), **la opción nativa en Swift es técnicamente superior** en casi todas las filas. Lo que cuesta es una reescritura completa de la interfaz, Xcode y la cuenta de desarrollador. El detalle y las condiciones están en §6.

---

## 2. Cómo se resolvería cada pieza en Swift

Todos los frameworks citados existen tanto en macOS como en iOS, de modo que el "motor" (procesado, vídeo, metadatos) puede ser un paquete Swift compartido y solo la capa SwiftUI tendría diferencias por plataforma.

### 2.1 Transversales

| Pieza | Framework / API | Observaciones |
|---|---|---|
| Escaneo de carpeta, orden por fecha, filtro de orientación | `FileManager`, `CGImageSourceCopyPropertiesAtIndex` (lee cabecera, no decodifica) | Orientación EXIF incluida. Soporta HEIC, RAW, AVIF (macOS 13+), WebP (macOS 11+) |
| Thumbnails | `CGImageSourceCreateThumbnailAtIndex` con `kCGImageSourceCreateThumbnailFromImageIfAbsent` | Usa el thumbnail EXIF embebido si existe: es la misma optimización que hoy hace a mano `exif-parser`, pero de serie. Alternativa `QLThumbnailGenerator` |
| Diálogos | `NSOpenPanel`/`NSSavePanel` (mac), `UIDocumentPickerViewController` / `.fileImporter` SwiftUI (iOS y mac) | En iOS se elige una carpeta del Files (iCloud Drive, "En mi iPhone", discos externos en iPad) |
| Carpetas recientes | `URL.bookmarkData` (security-scoped) | Obligatorio si la app va con sandbox (App Store); si va fuera del App Store en macOS, basta con rutas |
| `.caoba` por carpeta | `Codable` + `JSONEncoder` | Igual que hoy. En iOS funciona dentro de la carpeta elegida |
| i18n | String Catalogs (`.xcstrings`) | Nativo, con plurales |
| Tema oscuro/claro, fuentes Doto / Space Grotesk / Space Mono | SwiftUI `colorScheme`, fuentes empaquetadas (licencia OFL) | Sin descargas de Google Fonts al arrancar |
| Notificaciones de progreso | SwiftUI `ProgressView` + `Task` cancelable | meBlip desaparece; la cancelación es cooperativa (`Task.checkCancellation`) |
| Aviso de versión | `URLSession` a GitHub + comparación semver; o Sparkle (mac) / App Store | |
| Abrir resultado | `NSWorkspace.open` / `UIActivityViewController` o guardar en Fotos con `PHPhotoLibrary` | |

### 2.2 Slideshow

| Pieza | API | Viabilidad |
|---|---|---|
| Composición de vídeo | `AVAssetWriter` + `AVAssetWriterInputPixelBufferAdaptor`, codec H.264 o HEVC por **VideoToolbox (hardware)** | Alta. Se escriben frames directamente, sin límite de 100 entradas ni chunking |
| Escalado y pad a 6 formatos | Core Image (`CILanczosScaleTransform`) o vImage | Alta |
| Fundido entre fotos | `CIDissolveTransition` o mezcla manual por frame | Alta |
| Ken Burns | Core Image: crop + transform por frame renderizado en GPU al `CVPixelBuffer` del writer | Alta. Elimina los 125 JPEG por foto y la carpeta temporal |
| Marca de agua | `CISourceOverCompositing` con alfa | Alta |
| Portada y créditos | Mismo pipeline | Alta |
| Audio multipista con crossfade y fade-out | `AVMutableComposition` + `AVMutableAudioMix` con `setVolumeRamp` | Alta. Loop de pista: insertar el mismo rango varias veces |
| Duración de MP3 | `AVURLAsset.load(.duration)` | Trivial; sustituye a ffprobe |
| **Normalización EBU R128** | **No existe en AVFoundation.** Opciones: implementar BS.1770 (filtro K-weighting + gating) sobre `AVAudioPCMBuffer` (200-300 líneas), o simplificar a normalización por pico/RMS | Media. Es el único hueco real del slideshow |
| Color BT.709 / sRGB | `AVVideoColorPropertiesKey` en el writer + Core Image con espacio de trabajo sRGB | Alta, pero hay que ajustarlo bien (hoy se hace con flags de ffmpeg) |
| Progreso y cancelación | Frames escritos / total; `Task` cancelable, `writer.cancelWriting()` | Alta |
| Vista previa | Mismo motor a media resolución; o `AVPlayer` embebido en la propia ventana | Alta, y mejor que hoy (que está muerta) |
| Collage slideshow (reveal) | Mismo motor: se renderizan los frames acumulativos del collage en memoria y se escriben al writer | Alta. Deja de ser "más adelante" porque ya no hay carpeta de frames ni ffmpeg |

### 2.3 Collage y Contact Sheet

| Pieza | API |
|---|---|
| Plantillas | Mismo JSON de celdas normalizadas |
| Recorte cover / punto de foco | `CGImage.cropping` + `CGContext.draw` con interpolación alta, o Core Image |
| Smart crop `attention` | **`VNGenerateAttentionBasedSaliencyImageRequest`**: devuelve el mapa de saliencia y el rectángulo saliente. Equivalente directo (y mejor) que libvips |
| Caras | `VNDetectFaceRectanglesRequest`. Decenas de ms por foto en Neural Engine |
| Esquinas redondeadas, marco blanco | `CGPath` con `addRoundedRect` + clip |
| Sombra con blur | `CGContext.setShadow` (nativo) o `CIGaussianBlur` |
| Texto (título, etiquetas) | Core Text / `NSAttributedString.draw` |
| Logo con opacidad | `CGContext.setAlpha` + `draw` |
| Salida JPEG con calidad | `CGImageDestination` con `kCGImageDestinationLossyCompressionQuality` |
| Masonry | Lógica propia, igual que hoy |
| Límites de tamaño | En macOS, 15.000 px de lado va bien. **En iOS hay que limitar** (15.000 × 10.000 RGBA son 600 MB; el sistema mata la app). Tope razonable 6.000-8.000 px en iPhone, más en iPad |

### 2.4 Procesador, Conversor y Marca de agua

| Pieza | API |
|---|---|
| Auto-rotar EXIF | `CGImageSource` con `kCGImageSourceShouldCache` + aplicar orientación, o `CIImage(contentsOf:)` con `applyingOrientation` |
| Recorte a ratio con ancla, resize sin ampliar | `CGImage.cropping`, vImage o Core Image |
| Calidad y formato JPEG/PNG/HEIC/TIFF | `CGImageDestination`. WebP: ImageIO solo **lee** WebP, no escribe; AVIF: ni lee en versiones antiguas ni escribe. Si se quiere WebP de salida habría que añadir `libwebp` como dependencia SPM |
| HEIC entrada y salida | Nativo. Deja de ser "más adelante" |
| RAW (NEF, CR2, CR3, ARW, DNG...) | `CIRAWFilter`. Se podrían incluso procesar RAW en el Procesador |
| Preservar EXIF/ICC al reescribir | `CGImageDestinationAddImageFromSource` con las propiedades del origen |
| Marca de agua single/tiled con rotación | `CGContext` con `concatenate(CGAffineTransform)` y patrón; `setAlpha` para opacidad |
| Comparador antes/después | SwiftUI con dos `Image` y `mask` arrastrable |

### 2.5 Metadatos

| Pieza | API |
|---|---|
| Leer EXIF, GPS, objetivo, software | `CGImageSourceCopyPropertiesAtIndex` (diccionarios Exif, TIFF, GPS, ExifAux) |
| **Escribir sin recomprimir** | `CGImageDestinationCopyImageSource` con `kCGImageDestinationMetadata` + `kCGImageDestinationMergeMetadata` (Apple QA1895). Mejora directa sobre la app actual, que recomprime el JPEG. Hay avisos en foros de fallos silenciosos en macOS 12+/iOS 15+: hay que comprobar el resultado y tener test |
| Escribir GPS | Mismo mecanismo (diccionario GPS). Hoy no se puede |
| Borrar todo ("strip") | Reescribir con diccionario vacío, también sin recomprimir |
| Mapa | `MapKit` nativo con marcador, sin iframe ni OpenStreetMap |

### 2.6 Renombrador y QR

- Renombrador: lógica pura en Swift; fecha y cámara desde ImageIO. `FileManager.moveItem` en dos pasadas como hoy. En iOS funciona sobre la carpeta elegida (con `NSFileCoordinator`).
- QR: `CIQRCodeGenerator` con `inputCorrectionLevel` L/M/Q/H, colores con `CIFalseColor`, logo por composición. Los 9 tipos de contenido se construyen en Swift igual que hoy en JS.

### 2.7 Shutter Count: el único punto que empeora

- ImageIO expone `kCGImagePropertyMakerNikonDictionary` con **`kCGImagePropertyMakerNikonShutterCount`**. Para Nikon funciona nativo en macOS e iOS, incluidos NEF.
- Canon: el diccionario Canon de ImageIO no incluye disparos (y Canon no lo guarda en la mayoría de modelos, tampoco lo da exiftool).
- Sony y Pentax: MakerNotes cifrados que solo exiftool descifra. ImageIO no los expone.
- En **macOS** se puede empaquetar exiftool y lanzarlo con `Process` (Perl del sistema sigue en macOS 26), con lo que se iguala la app actual.
- En **iOS no se pueden ejecutar binarios externos**: Shutter Count quedaría solo para Nikon, o habría que portar a Swift el descifrado de Sony/Pentax (viable, el algoritmo de exiftool es público, pero es trabajo específico).

### 2.8 Detección de caras y smart crop

Con Vision, la decisión P3 ("caras más adelante") pierde sentido: `VNDetectFaceRectanglesRequest` y la saliencia por atención vienen con el sistema, sin modelos que empaquetar y corriendo en Neural Engine. Collage, Ken Burns y "Ajustar foco" se migrarían completos.

---

## 3. Lo que cambia respecto a la tabla confirmada en P4

| Funcionalidad | Tauri (P4) | Swift |
|---|---|---|
| Collage slideshow | Más adelante | **Ahora** (mismo motor de vídeo en memoria) |
| HEIC/HEIF | Más adelante | **Ahora**, de serie, y RAW además |
| Detección de caras | Más adelante | **Ahora**, Vision |
| Vista previa de slideshow | No contemplada (muerta) | Recuperable con `AVPlayer` integrado |
| Shutter Count | Ahora, todas las marcas (exiftool sidecar) | Ahora en macOS con exiftool; **en iOS solo Nikon** |
| Normalización EBU R128 | Ahora (loudnorm de ffmpeg) | **Implementación propia** o simplificar a pico/RMS |
| WebP de salida | Ahora (crate `webp`) | Requiere `libwebp` por SPM; ImageIO solo lee |
| Metadatos | exiftool escribe sin recomprimir | ImageIO escribe sin recomprimir, más GPS, más MapKit |
| meBlip | Tal cual | Desaparece (SwiftUI) |
| Windows | Sí | **No** |

---

## 4. iOS: qué implica de verdad

No es "la misma app en el móvil". Cosas a tener en cuenta:

- **Acceso a ficheros**: el usuario elige una carpeta en Files (`UIDocumentPickerViewController` en modo carpeta). Funciona con iCloud Drive, "En mi iPhone/iPad" y unidades externas conectadas al iPad. Alternativa: trabajar sobre la fototeca con `PhotoKit` (selección de fotos, no de carpetas; sin `.caoba`). Habría que elegir uno de los dos modelos o soportar ambos.
- **Música**: MP3 desde Files, sí. Canciones de Apple Music con DRM, no. Biblioteca local sin DRM, vía `MPMediaPickerController` + `AVAssetExportSession`.
- **Memoria**: límites estrictos. Collages y contact sheets grandes hay que renderizarlos por teselas o limitar el tamaño. Vídeo 1080p/4K por `AVAssetWriter` va bien porque es streaming.
- **Primer plano**: un slideshow largo debe terminar con la app visible; en segundo plano el sistema la suspende en segundos. Se avisa al usuario y se mantiene la pantalla encendida (`isIdleTimerDisabled`).
- **UI**: editores de Ken Burns y enfoque se adaptan bien a gestos táctiles (drag, pinch para zoom). Las listas con drag&drop de reordenación son nativas en SwiftUI. La barra lateral de secciones pasa a `TabView` o `NavigationSplitView` en iPad.
- **Distribución**: App Store o TestFlight. Revisión de Apple. Cuenta de desarrollador obligatoria.
- **Shutter Count**: solo Nikon (ver §2.7).

Orden recomendable si se va por Swift: **macOS primero** con el motor en un paquete Swift sin dependencias de AppKit/UIKit, e **iOS después** reutilizando ese paquete y escribiendo solo las vistas específicas.

---

## 5. Esfuerzo comparado

Estimación relativa, no un calendario. "1x" es el trabajo del backend Rust + adaptación JS de la opción Tauri confirmada en P4 (solo macOS + Windows).

| Bloque | Tauri + Rust (P4) | Swift macOS | Swift iOS adicional |
|---|---|---|---|
| Motor de imagen (procesador, marca de agua, collage, contact sheet, QR) | 1,0 | 0,7 (APIs más completas: texto, blur, HEIC, saliencia de serie) | 0,1 (límites de memoria, teselado) |
| Motor de vídeo (slideshow, Ken Burns, audio) | 1,0 | 1,1 (AVFoundation es más código que armar una línea de ffmpeg, pero sin chunking ni temporales; R128 propio) | 0,1 |
| Metadatos, renombrador, shutter count | 1,0 | 0,8 (ImageIO nativo; exiftool opcional en mac) | 0,1 |
| UI | 1,0 (HTML/CSS se reutilizan; JS se reescribe por módulos) | **2,0-2,5** (todo desde cero en SwiftUI, incluidos editores visuales y timelines) | 0,6-0,8 (adaptar a táctil, navegación, Files/Photos) |
| Infraestructura (build, firma, CI, i18n, config) | 1,0 | 0,8 | 0,3 (App Store, TestFlight, provisioning) |
| **Total aproximado** | **1,0** | **≈ 1,3-1,5** | **+ 0,4-0,5** |

Lectura: Swift para macOS cuesta en torno a un 30-50 % más que Tauri porque la UI se rehace entera, pero entrega **más funcionalidad** (caras, HEIC, RAW, collage slideshow, preview, GPS) con **menos peso y más velocidad**. iOS añade algo menos de la mitad otra vez.

---

## 6. Riesgos y condiciones

**Riesgos de Swift**
1. **Xcode no está instalado** y es obligatorio (SwiftUI, simuladores, firma). Son 12-15 GB y actualizaciones grandes.
2. **Normalización de audio R128** requiere implementación propia o aceptar una versión simplificada.
3. **Gestión de color en vídeo**: hay que validar con fotos reales que el resultado iguala al pipeline BT.709 actual (es un punto que ya costó ajustar en ffmpeg según el README).
4. **Calidad del codificador hardware** H.264: a igual bitrate, VideoToolbox rinde algo por debajo de libx264 `medium`. Se compensa subiendo bitrate o usando HEVC. Para slideshows de fotos estáticas la diferencia es poco visible.
5. **Shutter Count** no Nikon en iOS.
6. **Cuenta de desarrollador** (99 USD/año) imprescindible para iOS; recomendable para notarizar macOS.
7. **Curva de aprendizaje** si el equipo no tiene experiencia con AVFoundation y Core Image. El resto (SwiftUI, ImageIO) es asequible.
8. **Pérdida de Windows**, asumida por el usuario.

**Riesgos de Tauri + Rust** (recordatorio)
1. ffmpeg sidecar mantiene el peso en 80-120 MB y el rendimiento de vídeo por software.
2. Texto, SVG, HEIC, smart crop y caras hay que resolverlos uno a uno con crates o librerías nativas.
3. WKWebView no es Chromium: CSS y comportamiento a revisar.
4. Dos lenguajes y dos runtimes para mantener.

**Tercera vía descartable: motor en Rust + UI en Swift (UniFFI)**. Mantiene un núcleo portable a Windows en el futuro, pero duplica la complejidad (dos toolchains, puente FFI) y el vídeo seguiría necesitando AVFoundation o ffmpeg linkado. No aporta nada a los objetivos declarados.

**Cuarta vía descartable: Tauri 2 en iOS**. Reutilizaría la UI web, pero no admite sidecars en móvil, no hay ffmpeg empaquetable sin compilarlo uno mismo (ffmpeg-kit se retiró en 2025) y Vision solo sería accesible escribiendo un plugin en Swift. Se acaba escribiendo lo mismo que la opción nativa, con peor resultado.

---

## 7. Recomendación

Con las prioridades fijadas (tamaño y rendimiento → mantenibilidad; Windows prescindible; iOS deseable), **recomiendo la migración nativa en Swift**, en este orden:

1. **Motor compartido** como paquete Swift sin UI (imagen, vídeo, metadatos, plantillas), con tests.
2. **App macOS** en SwiftUI reproduciendo el diseño Nothing.
3. **App iOS/iPadOS** sobre el mismo motor.

Condiciones para que la recomendación se sostenga:
- Instalar Xcode y aceptar la cuenta de desarrollador de Apple (al menos para iOS).
- Aceptar que la UI se reescribe entera (las decisiones P2 y P3 quedan sin efecto; la tabla de P4 cambia según §3).
- Decidir qué hacer con la normalización R128 (implementar BS.1770 o simplificar) y con Shutter Count en iOS (solo Nikon, o portar el descifrado de Sony/Pentax).

Si alguna de esas condiciones no se acepta, Tauri + Rust con la tabla de P4 sigue siendo un plan válido y más barato, pero más pesado y lento, y sin iOS.

---

## 8. Fuentes consultadas
- Apple ImageIO, claves del diccionario Nikon (incluye `kCGImagePropertyMakerNikonShutterCount`): https://developer.apple.com/documentation/imageio/nikon-camera-dictionary-keys
- Apple QA1895, modificar metadatos sin recomprimir (`CGImageDestinationCopyImageSource`): https://developer.apple.com/library/archive/qa/qa1895/_index.html
- Aviso de fallos silenciosos al actualizar metadatos en macOS 12+: https://developer.apple.com/forums/thread/689913
- Tauri 2, sidecars (sin soporte en iOS/Android): https://v2.tauri.app/develop/sidecar
- ffmpeg-kit retirado, binarios hasta abril de 2025: https://cdn.jsdelivr.net/gh/arthenica/ffmpeg-kit@main/README.md
