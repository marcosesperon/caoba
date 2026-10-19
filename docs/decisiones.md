# Decisiones del proyecto

Bitácora de peticiones, preguntas, decisiones y alternativas descartadas. Cada petición añade su bloque al final; lo anterior no se toca.

## 2026-10-15 — Migración de CAOBA Foto Utils (Electron) a Tauri + Rust

### 1. La petición tal como se ha entendido
**Confirmada por el usuario el 15-10-2026**, con un cambio: el nombre del producto pasa a ser **"CAOBA"** a secas (ver P13).

**Qué se hace**: reescribir CAOBA Foto Utils (hoy Electron v2.9.0 en `caoba-foto-utils`) como **app nativa en Swift** en este repositorio (`caoba-photo-utils`), primero para **macOS** y después para **iOS/iPadOS**, abandonando Windows. Se conservan las funcionalidades principales y se aprovecha la migración para eliminar las dependencias pesadas (Electron, ffmpeg, exiftool salvo Shutter Count, TensorFlow) y los fallos conocidos documentados en `analisis-app-actual.md`.

**Prioridades**: tamaño del instalable y rendimiento primero; mantenibilidad después; estética nativa, no réplica del diseño Nothing.

**Arquitectura**:
- Un paquete Swift **`CaobaCore`** sin dependencias de UI (ImageIO, Core Image, vImage, AVFoundation, Vision, Core Text) con el motor: escaneo y orden, thumbnails, plantillas de collage (JSON), composición de collage y contact sheet, procesador, marca de agua, metadatos, renombrador, QR, slideshow (AVAssetWriter + VideoToolbox, Ken Burns en GPU, audio con crossfade, fade-out y normalización BS.1770 propia), shutter count, configuración `.caoba`. Con tests (Swift Testing).
- Una app **macOS** en SwiftUI con los controles del sistema, Doto en títulos, acento rojo, modo claro/oscuro, i18n ES/EN con String Catalogs. Mínimo macOS 14. Distribución fuera del App Store (DMG en GitHub Releases, Developer ID + notarización, sin sandbox). exiftool empaquetado solo para Shutter Count.
- Una app **iOS/iPadOS** posterior sobre el mismo motor (mínimo iOS 17, App Store/TestFlight, security-scoped URLs), que se tratará como petición aparte.

**Alcance funcional en macOS (paridad con la app actual más lo que sale gratis)**:
- Slideshow: fotos, 6 formatos, fundido, marca de agua, portada/créditos, N pistas MP3 (auto/manual, crossfade, fade-out, normalización R128), Ken Burns completo con editor y timeline, collage slideshow, vista previa integrada.
- Collage estático y Contact Sheet con editor de enfoque, smart crop por saliencia (Vision) y detección de caras (Vision).
- Procesador (absorbe el Conversor): rotar, recortar, redimensionar, calidad, formato de salida JPEG/PNG/HEIC/TIFF; entrada incluye HEIC y RAW. EXIF/ICC preservados.
- Marca de agua single/tiled.
- Metadatos: lectura completa, escritura sin recomprimir (ImageIO), GPS editable, mapa con MapKit.
- Renombrador 4 modos. QR 9 tipos con logo.
- Shutter Count: todas las marcas en macOS vía exiftool; Nikon nativo.
- Transversales: carpeta compartida con recientes, checkboxes y orden manual, barra de destino, `.caoba` compatible con el formato v1 actual (al menos lectura), aviso de versión con semver, tema, idioma.

**Entrega por fases**, con app usable en cada una: (a) esqueleto + motor de imagen con Procesador, Marca de agua, Renombrador, QR y Metadatos; (b) Collage y Contact Sheet; (c) Slideshow; (d) Shutter Count y extras; (e) iOS. La app Electron sigue publicada hasta la paridad.

**Supuestos que fijo yo (corregir si no encajan)**:
- Nombre del producto **"CAOBA"** (cambiado en la confirmación), bundle id `com.marcosesperon.caoba`, numeración continúa en 3.0.0.
- Estructura del repo: `Package/CaobaCore` (SPM) + proyecto Xcode `CaobaFotoUtils` con targets macOS e iOS. CI en GitHub Actions con runner macOS.
- Antes de la fase (a) se necesita Xcode instalado y una cuenta de desarrollador de Apple para firmar; sin cuenta se puede desarrollar y probar en local igualmente.
- Temporales siempre en el directorio temporal del sistema, nunca en la carpeta de fotos.
- Comentarios de código en español, nombres de tipos y funciones en inglés (convención Swift).

**Fuera de alcance de esta petición**: Windows, App Store de macOS, WebP/AVIF de salida, descifrado Sony/Pentax en Swift.

### 2. Preguntas y respuestas
*(Se van añadiendo de una en una conforme se formulan.)*

**P1. ¿Cuál es la motivación principal de la migración?**
R: Tamaño y rendimiento primero, mantenibilidad después. Los sidecars (binarios externos como ffmpeg o exiftool empaquetados con la app) son aceptables.

**P2. ¿Qué hacemos con la interfaz actual?** (1: reutilizar HTML/JS/CSS tal cual; 2: reescribir con framework; 3: intermedio, reutilizar HTML y CSS y reescribir el JS módulo a módulo extrayendo lo común)
R: Opción 3.

**P3. ¿Qué hacemos con la detección de caras y el smart crop?** (1: solo centro + `attention` reimplementado en Rust, caras más adelante; 2: caras ahora con `rustface`; 3: caras ahora con ONNX Runtime; 4: eliminar smart crop)
R: Opción 1. Las caras quedan para una fase posterior; el editor manual de enfoque se mantiene.

**P4. ¿Confirmas la clasificación propuesta por funcionalidad (ahora / simplificar / más adelante)?**
Propuesta: Slideshow básico, Ken Burns (frames por tubería a ffmpeg), Collage estático, Contact Sheet, Procesador absorbiendo el Conversor, Marca de agua, Metadatos con exiftool para leer y escribir, Renombrador, QR, Shutter Count, aviso de versión con semver, `.caoba` solo en Slideshow, transversales y meBlip tal cual → **ahora**. Collage slideshow, HEIC/HEIF y detección de caras → **más adelante**.
R: Confirmada. **Pero antes de bajar a cada funcionalidad el usuario pide un segundo análisis**: viabilidad y conveniencia de una app nativa en Swift para macOS e iOS, aceptando perder Windows. La decisión de la tecnología de migración se tomará en base a ese segundo análisis. Resultado en `docs/analisis-swift-vs-tauri.md`.

**P5. ¿Swift nativo (macOS primero, iOS después) o Tauri + Rust con la tabla de P4?**
R: **Swift nativo.** Consecuencias: P2 (reutilizar HTML/CSS) y P3 (caras más adelante) quedan sin efecto; la tabla de P4 se revisa según §3 del análisis Swift. Windows se abandona.

**P6. ¿Cómo se distribuye la app de macOS?** (1: fuera del App Store, DMG en GitHub con Developer ID + notarización, sin sandbox; 2: App Store con sandbox; 3: ambas)
R: Opción 1. Sin sandbox en macOS; exiftool empaquetable. iOS irá por App Store/TestFlight y el motor compartido soportará security-scoped URLs de todos modos.

**P7. ¿Normalización de volumen?** (1: implementar BS.1770/R128 en Swift; 2: RMS simplificado; 3: quitar)
R: Opción 1. Medición al añadir la pista, ganancia aplicada en el mix; test de equivalencia frente a ffmpeg `loudnorm`.

**P8. ¿Alcance de Shutter Count?** (1: macOS con exiftool empaquetado + iOS solo Nikon; 2: solo Nikon en ambas; 3: portar descifrado Sony/Pentax a Swift)
R: Opción 1. Portar Sony/Pentax (3) queda como posible fase posterior.

**P9. ¿Formatos de salida del Procesador?** (1: JPEG, PNG, HEIC, TIFF nativos de ImageIO; 2: + WebP con libwebp; 3: + AVIF)
R: Opción 1. WebP y AVIF se leen pero no se escriben.

**P10. ¿Aspecto de la app en SwiftUI?** (1: reproducir diseño Nothing; 2: aspecto nativo de macOS/iOS conservando Doto en títulos, acento rojo y modo oscuro/claro; 3: híbrido con capa de tema)
R: Opción 2. Controles del sistema; identidad reducida a tipografía de títulos, acento y temas.

**P11. ¿Versiones mínimas de sistema?** (1: macOS 14 / iOS 17; 2: macOS 15 / iOS 18; 3: macOS 13 / iOS 16)
R: Opción 1. macOS 14 Sonoma e iOS 17, Swift 6 con `@Observable`.

**P12. ¿Cómo se entrega la migración?** (1: por fases con app usable en cada una; 2: un release 3.0 con paridad completa; 3: Slideshow primero)
R: Opción 1. Fases: (a) esqueleto macOS + motor de imagen con Procesador, Marca de agua, Renombrador, QR y Metadatos; (b) Collage y Contact Sheet con editor de enfoque y Vision; (c) Slideshow con Ken Burns, audio y collage slideshow; (d) Shutter Count y extras; (e) iOS como petición aparte en la bitácora. La app Electron sigue viva hasta la paridad.

**P13. ¿Nombre del producto: "CAOBA Foto Utils" o "CAOBA" a secas?** (propuesto por el usuario al confirmar)
R: **"CAOBA"**. Si el nombre está cogido en el App Store cuando llegue iOS, la ficha usará "CAOBA Foto Utils" o similar sin cambiar la app. Bundle id `com.marcosesperon.caoba`.

### 3. Fuentes analizadas
- `/Users/marcosesperon/Documents/GITs/caoba-foto-utils` en commit `51fc210` (v2.9.0, 29-07-2026): `main.js`, `preload.js`, `src/*.js`, `index.html`, `assets/js/*.js`, `assets/css/*`, `locales/*`, `package.json`, `CLAUDE.md`, `README.md`, `CHANGELOG.md`, workflow de release.
- Release v2.9.0 en GitHub (tamaño de instaladores).
- Para el análisis Swift: documentación de Apple (ImageIO claves Nikon, QA1895 metadatos sin recomprimir), documentación de Tauri 2 (sidecars), README de ffmpeg-kit (retirada). Enlaces en `analisis-swift-vs-tauri.md` §8.
- Entorno local: cargo/rustc 1.94, Node 26, exiftool de Homebrew; sin Tauri CLI, ffmpeg ni libvips instalados.

### 4. Decisiones
- **Tecnología**: Swift nativo (SwiftUI + ImageIO/Core Image/AVFoundation/Vision), macOS primero e iOS después. Por qué: elimina todas las dependencias pesadas, da codificación de vídeo por hardware, caras y saliencia de serie, HEIC/RAW nativos y metadatos sin recomprimir. Windows era prescindible.
- **Motor separado de la UI** en un paquete Swift `CaobaCore` con tests. Por qué: se comparte entre macOS e iOS y se puede compilar y probar con `swift test` sin abrir Xcode.
- **Proyecto Xcode generado con XcodeGen** desde `project.yml` versionado. Por qué: evita editar el `.xcodeproj` a mano y los conflictos de merge en ese fichero.
- **Distribución macOS fuera del App Store**, sin sandbox (P6). **Shutter Count** con exiftool empaquetado en Mac (P8). **R128 propio** (P7). **Formatos nativos** de ImageIO (P9). **Aspecto nativo** (P10). **macOS 14 / iOS 17** (P11). **Entrega por fases** (P12). **Nombre "CAOBA"** (P13).
- **Plan de la fase (a) aprobado el 15-10-2026**: estructura del repo, `CaobaCore` con FolderScanner, ThumbnailProvider, ImageProcessor, Watermarker, MetadataService, Renamer, QRGenerator, CaobaConfig y JobRunner; app macOS con barra de carpeta, destino, lista de ficheros, progreso y las vistas de Procesador, Marca de agua, Renombrador, QR y Metadatos; CI en GitHub Actions; documentación.
- **Plan de la fase (b) aprobado el 15-10-2026**: plantillas exportadas del módulo original a `templates.json`; `FocusDetector` con Vision (centro / saliencia / caras); `CollageRenderer` y `ContactSheetRenderer`; vistas de Collage (secuencia, Componer, editor de enfoque, Ajustar foco) y Contact Sheet; barra de destino en modo fichero. Supuestos: Collage guarda siempre en carpeta con nombres automáticos; plantillas overlap excluidas del Collage estático; orden manual por arrastre en la lista.
- **Fase (b), decisiones de implementación (15-10-2026)**: las 570 plantillas van en un JSON exportado con Node desde el módulo original (fidelidad exacta, sin transcribir); el modo de foco automático usa Vision *objectness* con la saliencia por atención de respaldo, porque un experimento con imágenes sintéticas mostró que la atención tiene sesgo al centro y localiza mal el sujeto; el título del collage escala con el ancho del lienzo (5 %, mínimo 50 px) en vez de los 50 px fijos de la app antigua; las fotos se decodifican reducidas al tamaño de celda para ahorrar memoria; el editor de enfoque marca las celdas ajustadas a mano para que "Ajustar foco" no las pise.
- **Plan de la fase (d) aprobado el 16-10-2026**: exiftool descargado por script con versión fijada y suma comprobada a una carpeta ignorada por git que el proyecto copia como recurso (opcional: sin ella la app usa ImageIO); `ShutterCountReader` con exiftool primero (empaquetado o de Homebrew) e ImageIO de respaldo (Nikon nativo); tabla de vida útil portada de la app antigua; vista con ficha de cámara, obturador y foto.
- **Plan de la fase (c) aprobado el 15-10-2026** (el usuario pidió preparar las tres entregas seguidas): (c1) motor de vídeo con AVAssetWriter + Core Image, audio con AVMutableComposition, R128 propio y vista Slideshow con preview en ventana; (c2) Ken Burns completo con timeline y editor; (c3) collage slideshow, persistencia `.caoba` compatible con v1 y documentación. Supuestos: preview dentro de la app; H.264 con bitrate alto fijo por formato; color sRGB etiquetado BT.709, a validar con fotos reales.
- **Fase (c), decisiones de implementación (15-10-2026)**: vídeo con `AVAssetWriter` y composición por fotograma en Core Image (sin fotogramas en disco ni troceado); audio con `AVMutableComposition` y mezcla a AAC con el vídeo en passthrough; R128 propio (BS.1770-4) verificado con el tono de EBU Tech 3341; las rampas de volumen se acortan en pistas cortas para que nunca se solapen (AVFoundation lo prohíbe); la cancelación de AVFoundation (`CancellationError`) se traduce a `CaobaError.cancelled`; efectos y puntos Ken Burns guardados por nombre de fichero (nuevo `byFile`) con lectura del formato v1 por índice; el editor de secuencia de collages se extrajo a un componente compartido por Collage y Slideshow; la preview se reproduce en una ventana con `AVPlayer`.
- Temporales siempre en el directorio temporal del sistema. Salida por defecto `<origen>/caoba`; sufijos `_processed` y `_watermarked` si se guarda en la misma carpeta (como hoy).
- **Escritura de metadatos (fase a)**: se usa `CGImageDestinationCopyImageSource`, que no recomprime la imagen. Cuatro experimentos (15-10-2026) demostraron que ImageIO solo acepta `CGImageMetadata` (XMP): artista = `dc:creator`, descripción = `dc:description`, copyright = `dc:rights`, fecha = `photoshop:DateCreated`, GPS = `exif:GPSLatitude/Longitude` en formato "DD,MM.mmmmN". Los tags EXIF/TIFF clásicos **se actualizan si ya existían pero no se crean**. Decisión: el XMP es la fuente de verdad (es lo que escriben Lightroom y compañía y lo que lee exiftool como `Creator`/`Rights`), la lectura mira EXIF primero y XMP de respaldo, y la escritura va en dos pasadas (sin mezcla para borrar, con mezcla para fijar valores). Alternativa descartada por ahora: escribir el IFD EXIF a mano para JPEG (unas 400 líneas), que se reconsiderará si algún programa relevante no lee el XMP.
- **Carga de imágenes con orientación**: se delega en ImageIO (`CGImageSourceCreateThumbnailAtIndex` a tamaño completo con transformación) en vez de aplicar la orientación a mano; la rotación en memoria propia se mantiene, testeada píxel a píxel para las ocho orientaciones, para imágenes ya cargadas.

### 5. Alternativas descartadas
- **Tauri + Rust** (el plan original, con tabla por funcionalidad confirmada en P4): válido y más barato en UI, pero 80-120 MB con ffmpeg sidecar, vídeo por software, y caras/HEIC/collage slideshow aplazados. Descartado al priorizar tamaño, rendimiento e iOS sobre Windows.
- **Motor Rust + UI Swift (UniFFI)**: núcleo portable, pero dos toolchains y puente FFI; el vídeo seguiría necesitando AVFoundation. No aporta a los objetivos.
- **Tauri 2 en iOS**: sin sidecars en móvil, ffmpeg-kit retirado en 2025, Vision solo vía plugin Swift. Se acabaría escribiendo lo mismo con peor resultado.
- **Reproducir el diseño Nothing en SwiftUI**: demasiado coste de estilizar cada control; mantenibilidad va antes que estética (P10).
- **App Store de macOS** o ambas vías: sandbox y sin exiftool; innecesario para la distribución actual por GitHub (P6).
- **Normalización RMS o quitarla**: menor fidelidad; se prefiere BS.1770 real (P7).
- **WebP/AVIF de salida**: requieren librerías externas por SPM; ImageIO solo los lee (P9).
- **macOS 15 o macOS 13 como mínimo**: 15 deja fuera Macs Intel de 2017-2018; 13 renuncia a `@Observable` (P11).
- **Un único release 3.0 o Slideshow primero**: demasiado tiempo sin nada publicable, o vídeo sin motor de imagen probado debajo (P12).
- **Editar el `.xcodeproj` a mano** o crear la app como paquete SPM ejecutable: lo primero es frágil, lo segundo no genera un bundle `.app` correcto.

### 6. Pendiente de comprobar
- Fallo de la prueba manual de la fase (c) corregido el 16-10-2026: en el editor Ken Burns no respondían los botones ni los selectores porque la imagen escalada de cada celda, aunque recortada visualmente, seguía capturando los clics fuera del recuadro (`clipped` no limita la zona interactiva). Arreglado con `contentShape` y gesto en el contenedor; afectaba también a las celdas del editor de enfoque del collage.
- Mejoras pedidas por el usuario el 16-10-2026 tras la prueba de la fase (c): botón "Enfocar caras" en el editor Ken Burns (foco de inicio y fin en las caras de esa foto, con saliencia de respaldo) y plantillas superpuestas (84, con marco y sombra) disponibles solo en el modo Collages del Slideshow, como en la app antigua; el Collage estático las sigue excluyendo.
- **Recorte por pista (16-10-2026)**: el usuario planteó poder omitir silencios al principio o final de una canción. Decisión: campos **Desde** y **Hasta** por pista en tiempo de la canción (`AudioTrack.trimStart/trimEnd`); el crossfade a la siguiente se hace en el "Hasta" y la última pista repite el tramo recortado hasta el final del vídeo. Descartado indicar el minuto del vídeo en el que salta, porque deja de coincidir al cambiar duraciones o quitar fotos; el inicio por foto ya cubre ese caso. Guardado en `.caoba` (`musicTracks[].trimStart/trimEnd`, nuevo).
- **Repetir la lista de pistas (16-10-2026)**: opción "Repetir la lista si el vídeo es más largo" (`AudioOptions.loopPlaylist`), activada por defecto y visible solo con más de una pista. Al agotarse la lista se vuelve a la primera encadenando en automático con crossfade; las repeticiones ignoran los inicios por foto. Con una sola pista o la opción apagada, la última se repite sola como hasta ahora. El timeline dibuja los carriles con el mismo plan que el motor.
- **Estado de la fase (d) a 16-10-2026**: `ShutterCountReader` (exiftool primero, ImageIO de respaldo), tabla de vida útil, script de descarga de exiftool 13.59 con suma comprobada (exiftool.org solo sirve la última versión; se usa el espejo de SourceForge), carpeta vendor opcional en el proyecto, paso en la CI, vista Shutter Count con arrastre de fichero. 95 tests en verde (incluido uno con el exiftool de Homebrew). App compilando con exiftool dentro (unos 20 MB más). **Pendiente la prueba manual** con un RAW de Nikon, Sony o Pentax reales.
- **Estado de la fase (c) a 15-10-2026**: motor de vídeo, audio, R128, Ken Burns, collage slideshow y preset (`.caoba`) con 83 tests en verde, incluido un render real con audio; vista Slideshow completa (modos fotos y collages, portada/créditos, marca de agua, pistas con inicio automático o por foto, timeline Ken Burns con carriles de audio, editor Ken Burns con previsualización animada, vista previa en ventana, persistencia `.caoba`). App compilando sin avisos y arrancando. **Pendiente la prueba manual** del usuario con fotos y música reales: fidelidad de color frente al pipeline ffmpeg, calidad del H.264 por hardware, sincronía de los fundidos de audio, comportamiento del editor Ken Burns y lectura de un `.caoba` antiguo.
- **Estado de la fase (b) a 15-10-2026**: motor con plantillas, foco (Vision), collage y contact sheet (64 tests en verde); vistas de Collage (secuencia, Componer, Añadir, Ajustar foco, editor de enfoque con cambio de plantilla, modo aleatorio) y Contact Sheet; barra de destino en modo fichero. App compilando y arrancando. **Pendiente la prueba manual** del usuario, en especial el editor de enfoque (arrastre de fotos) y la reordenación de la secuencia por arrastre.
- Fallos de la prueba manual de la fase (b) corregidos el 15-10-2026: falta de botón "Ninguna" en el selector de plantillas; destino del Collage en modo fichero (ahora solo carpeta); fotos con miniatura EXIF embebida (160 px) salían pixeladas en el editor y en el collage generado porque ImageIO devuelve la embebida aunque se pida un tamaño mayor (ahora se fuerza la decodificación real cuando la embebida no llega al tamaño pedido; test añadido).
- Comprobar con fotos reales que el foco automático (objectness) recorta como se espera en retratos y paisajes; si no convence, alternativa: ponderar objectness y atención.
- **Estado de la fase (a) a 15-10-2026**: motor `CaobaCore` completo para los cinco módulos (49 tests en verde con `swift test`), app macOS compilando y arrancando con `xcodebuild` (Xcode 27 vía `DEVELOPER_DIR`), CI definida, documentación escrita. Prueba manual inicial del usuario (15-10-2026): "de momento todo bien". Queda pendiente una prueba más a fondo con carpetas grandes.
- Verificar en la app real: que la fuente Doto se carga en los títulos, que el cambio de idioma en Preferencias se aplica a todas las vistas, que arrastrar una carpeta al selector funciona, y que la lista de ficheros rinde bien con cientos de fotos (miniaturas).
- La CI usa `macos-15` y un Xcode 16; el proyecto se ha compilado localmente con Xcode 27. Ajustar el runner si GitHub ofrece una imagen con Xcode más reciente.
- Firma y notarización (Developer ID) y generación del DMG: pendientes de la cuenta de desarrollador.
- Confirmar con el usuario si la preview de vídeo del slideshow (muerta en v2.9.0) se quiere recuperar.
- Confirmar si el arrastre de carpeta al selector está realmente roto en la build publicada (no se ha ejecutado la app).
- Comprobar con Lightroom, Fotos de Apple y Finder que ven el artista/copyright escritos en XMP cuando la foto no traía tag EXIF previo (exiftool sí los lee).
- Si se elige Swift: validar con fotos reales la gestión de color sRGB → BT.709 en `AVAssetWriter`; comprobar que `CGImageDestinationCopyImageSource` escribe metadatos correctamente en macOS 26 (hay avisos de fallos silenciosos desde macOS 12); decidir R128 propio o simplificado; decidir Shutter Count en iOS (solo Nikon o portar descifrado Sony/Pentax).

## 2026-10-16 — Rediseño de la pantalla de Slideshow

### 1. La petición tal como se ha entendido
**Confirmada por el usuario el 16-10-2026.**

**Qué se hace**: rediseñar la pantalla del módulo Slideshow de la app macOS, sin cambiar el motor, para que el timeline sea el centro de la pantalla y todo lo que afecta a una foto o a una pista se edite sobre ella.

**Disposición**
- **Barra de carpeta** arriba, como hasta ahora.
- **Barra del timeline**: selector Fotos / Collages, botón para abrir el panel de fotos, "Asignar efectos", (en Collages) Componer y Añadir, zoom del timeline y duración total.
- **Timeline a toda la anchura** con regla de tiempo: tarjetas de portada, fotos (o collages) y créditos, con anchura proporcional a su duración; miniatura, duración y etiqueta del efecto. Arrastrar reordena; estirar el borde cambia la duración de esa foto; una casilla al pasar el ratón (o el menú contextual) la excluye; clic la selecciona.
- **Carriles de música** bajo las fotos, en la misma escala: un bloque por pista que se arrastra para fijar el inicio (con imán a los bordes de las fotos y al final de la pista anterior) y se estira por los bordes para el recorte Desde/Hasta. Las repeticiones de la lista se dibujan atenuadas. "Añadir pista" en el carril.
- **Inspector a la derecha**, según la selección:
  - nada seleccionado: formato, segundos por foto (con "Igualar duraciones"), fundido, marca de agua, ajustes globales de Ken Burns con lo avanzado plegado, y los conmutadores de música (repetir lista, fundido de salida, normalizar);
  - foto: efecto, "Enfocar caras", duración propia, encuadre de inicio y fin editable en el propio inspector con previsualización animada y **botón de ampliar** que abre el mismo contenido a pantalla grande;
  - pista: nombre y duración, inicio (`m:ss` del vídeo), Desde / Hasta, quitar;
  - collage (modo Collages): editor de enfoque y cambio de plantilla, aparición y mantenimiento.
- **Panel de fotos plegable** a la izquierda, cerrado por defecto: orden por nombre o fecha, filtro de orientación, Todas / Ninguna y casillas.
- **Barra de acción al pie**: destino del vídeo con Elegir, duración estimada, Vista previa y Generar vídeo.

**Modelo de datos (cambios)**
- El inicio de una pista pasa a guardarse como **tiempo del vídeo** (`startTime`); desaparece el modo "en la foto X". Al añadir una pista se coloca tras la anterior (crossfade incluido). Los `.caoba` que traigan `startPhoto` se convierten a tiempo al cargarlos.
- Cada foto puede tener **duración propia** (`durations` por nombre de fichero en el preset); si no la tiene, usa el valor global.
- Todo lo demás (efectos y puntos por fichero, recortes, repetición de lista, collage) se mantiene.

**Supuestos que fijo yo**
- Anchura de las tarjetas: entre 60 y 400 píxeles según zoom, con un control deslizante de zoom del timeline; con muchas fotos se desplaza horizontalmente.
- Teclado: Suprimir excluye la foto seleccionada o quita la pista; flechas cambian la selección.
- La vista previa sigue en ventana propia; el editor de encuadre ampliado reutiliza el componente del inspector.
- Collage y Contact Sheet no cambian en esta petición.

### 2. Preguntas y respuestas
*(Se van añadiendo de una en una.)*

**P1. ¿El inspector sustituye al editor Ken Burns modal o conviven?** (1: sustituye; 2: conviven con botón "Editar encuadre…"; 3: inspector con botón de ampliar a pantalla grande)
R: Opción 3. El encuadre se edita en el inspector y un botón lo abre a tamaño grande cuando se quiere precisión.

**P2. ¿Cómo se fija el inicio de una pista en el timeline?** (1: arrastre libre con imán, inicio como tiempo del vídeo; 2: arrastre que se engancha a una foto; 3: sin arrastre, solo inspector)
R: Opción 1. El usuario señala que así sobra el campo "Inicio en la foto X": desaparece. El inicio se guarda como segundos del vídeo; "tras la anterior" sigue siendo el modo por defecto al añadir una pista. El recorte Desde/Hasta se hace estirando los bordes del bloque y con campos en el inspector. Asumido el riesgo de que al cambiar duraciones la música no se desplace con las fotos.

**P3. ¿Qué hacemos con la lista de ficheros?** (1: panel lateral plegable, cerrado por defecto; 2: hoja modal; 3: fija debajo del timeline)
R: Opción 1. Excluir fotos también desde la tarjeta del timeline; orden manual arrastrando tarjetas.

**P4. ¿Las fotos pueden tener duración propia?** (1: sí, estirando el borde de la tarjeta, con anchura proporcional al tiempo; 2: solo valor global)
R: Opción 1. El valor global ajusta las fotos sin duración propia; botón "Igualar duraciones".

### 3. Fuentes analizadas
- Captura de la pantalla actual del Slideshow (16-10-2026) y el código de `SlideshowView`, `KenBurnsViews`, `CollageSequenceEditor` y `FileListView`.

### 4. Decisiones
- **Plan aprobado el 16-10-2026**: motor con `StartMode.atTime` (y `.atPhoto` solo para leer ficheros antiguos); `SlideshowDocument` como modelo de pantalla; `SlideshowTimelineView` con regla, zoom, tarjetas proporcionales, estirado, exclusión y reordenación; carriles de música con arrastre e imán y asas de recorte; `SlideshowInspector` con contenidos vídeo / foto / pista / collage; `KenBurnsFramingView` compartido entre inspector y modal grande; panel de fotos plegable; barra de acción al pie; modo Collages sobre el mismo timeline; teclado; preset con `startTime` y duraciones por foto.

### 5. Alternativas descartadas
- Inspector que sustituye del todo al modal o que convive con él sin ampliar (P1): se eligió inspector con botón de ampliar.
- Inicio de pista enganchado a una foto o solo desde el inspector (P2): se eligió arrastre libre con imán; el usuario prefirió quitar el "Inicio en la foto X".
- Lista de ficheros como hoja modal o fija bajo el timeline (P3): panel plegable.
- Solo duración global (P4): el timeline pierde la escala real.

### 6. Pendiente de comprobar
- **Ajuste tras la primera prueba (16-10-2026)**: el usuario pidió el timeline a toda la anchura en la parte inferior, las secciones como pestañas arriba (Fotos/Collages, Vídeo, Portada y marca, Música) y que lo seleccionado abra una pestaña contextual; el zoom pasa a la cabecera del timeline. Fallo corregido: con el timeline más ancho que la ventana, el `ScrollView` se quedaba los arrastres de los bloques de música; ahora los gestos de bloques, asas y estirado van con `highPriorityGesture` y el scroll es solo horizontal.
- Segundo ajuste (16-10-2026): el bloque de una pista medía todo el segmento del plan de audio (hasta el final del vídeo en la última pista), con lo que al arrastrarlo parecía anclado por la derecha; ahora el bloque mide la canción recortada y el relleno (vueltas de la misma canción o repetición de la lista) se dibuja atenuado. Las asas de recorte no respondían porque el gesto de mover tenía prioridad alta en el contenedor; ahora va en el cuerpo del bloque y las asas son hermanas por encima.
- Tercer ajuste (16-10-2026): la pestaña contextual con el nombre completo del fichero hacía crecer el control de pestañas más que la ventana y empujaba fuera la barra lateral (título acotado a 18 caracteres). El timeline terminaba en el fin del vídeo y cortaba las pistas más largas: ahora se extiende hasta donde acabe el audio, con una marca "Fin del vídeo" y el tramo de pista que no sonará atenuado.
- Duración propia por collage (16-10-2026): cada collage del slideshow puede tener su propio "mantener" (`CollageRow.hold`, `SequenceItem.hold`), ajustable estirando la tarjeta o con el deslizador de su pestaña, con vuelta al valor global; se guarda en `collage.holdByRow`. Las fotos ya lo tenían (`durations`).
- **Estado a 16-10-2026**: rediseño implementado (modelo `SlideshowDocument`, timeline, inspector, encuadre compartido, panel de fotos, barra de acción, modo Collages, teclado, preset con `startTime` y duraciones por foto). Motor con 87 tests en verde; app compilando sin avisos y arrancando. **Pendiente la prueba manual** del usuario.
- Prueba manual del arrastre de bloques de música y del estirado de tarjetas con muchas fotos (rendimiento del timeline con cientos de tarjetas).
- Cuarto ajuste (16-10-2026): la pestaña contextual ya no va en un `ScrollView`; el collage se encaja a la altura disponible con los controles a la derecha y los paneles de encuadre Ken Burns se dimensionan desde la altura real (ya no hay altura aproximada).

## 2026-10-16 — Deshacer renombrados en sitio

### 1. La petición tal como se ha entendido
Al renombrar sobrescribiendo los originales, la app guarda un registro de cada operación (fecha, modo y lista de nombre viejo → nombre nuevo) para poder volver atrás. En el Renombrador aparece un botón "Deshacer último renombrado" cuando la carpeta tiene historial; deshace la última operación completa, comprobando antes que los ficheros siguen con los nombres nuevos (si alguno falta, se avisa y se deshacen solo los posibles), y permite seguir deshaciendo hacia atrás en orden. Con "copias nuevas" no se registra nada porque los originales se conservan. Confirmada por el usuario al elegir la opción 1 de la única pregunta.

### 2. Preguntas y respuestas
**P1. ¿Dónde se guarda el registro?** (1: fichero oculto `.caoba-renames.json` en la carpeta; 2: sección del `.caoba`; 3: Application Support por carpeta)
R: Opción 1.

### 3. Fuentes analizadas
- `Renamer` (`CaobaCore`) y `RenamerView`.

### 4. Decisiones
- Primera versión: registro en `.caoba-renames.json`. **Cambiado el mismo día a petición del usuario**: el historial pasa a ser la sección `renameHistory` del `.caoba`, declarada como sección protegida; "Reiniciar" borra el resto de secciones y la conserva (`CaobaConfig.resetSettings`), el indicador "Configuración restaurada" no la cuenta (`hasSettings`) y todas las escrituras del `.caoba` pasan por un cerrojo para que el guardado automático del Slideshow y el historial no se pisen. Un solo fichero oculto por carpeta.
- `Renamer.execute` registra la operación automáticamente al sobrescribir (solo las entradas que se renombraron de verdad); `RenameHistory.undoLast` invierte el plan con la misma lógica de dos pasadas y elimina la operación del registro.

### 5. Alternativas descartadas
- Fichero aparte `.caoba-renames.json` (implementado primero y retirado: dos ficheros ocultos por carpeta) y Application Support (se pierde al mover la carpeta).

### 6. Pendiente de comprobar
- Prueba manual: renombrar en sitio, deshacer, y deshacer dos operaciones seguidas.

## 2026-10-16 — README y landing (GitHub Pages)

### 1. La petición tal como se ha entendido
*(modo directo, sin análisis previo: la petición venía con la referencia y el alcance claros)*
Reescribir `README.md` como explicación de la app tomando como referencia el README de CAOBA Foto Utils (Electron) y adaptándolo a la versión Swift, y crear `index.html` en la raíz como landing para GitHub Pages.

### 2. Preguntas y respuestas
Ninguna.

### 3. Fuentes analizadas
- `README.md` de `caoba-foto-utils` (estructura, módulos, enlaces a caobafoto.com y Buy Me a Coffee, logo).

### 4. Decisiones
- README en español con la misma estructura que el antiguo (acerca de, 9 módulos, interfaz, tecnologías, uso) más instalación, diferencias con la versión Electron y nota sobre exiftool.
- Landing en `index.html` en la raíz (GitHub Pages desde `main` / raíz), estática, sin dependencias salvo Google Fonts: estética de la app (OLED negro o papel claro, trama de puntos, Doto en titulares, rojo CAOBA), español e inglés con conmutador, tema claro/oscuro, y botón de descarga que consulta la última release en GitHub para enlazar el DMG directamente.
- Logo e icono copiados a `assets/` para la landing y el README.

### 5. Alternativas descartadas
- Publicar Pages desde `docs/`: expondría la bitácora y la documentación interna como parte del sitio.
- Capturas de pantalla en la landing: no hay capturas limpias todavía; se añadirán cuando haya una release.

### 6. Pendiente de comprobar
- Activar GitHub Pages (rama `main`, carpeta raíz) tras publicar el commit, y revisar la landing en móvil.

## 2026-10-16 — Releases en local

### 1. La petición tal como se ha entendido
*(modo directo)* Revisar si se generaban releases para Apple Silicon e Intel y, al comprobar que no había ninguna, crear un script local que compile el binario universal, cree el DMG y lo publique como release en GitHub. El usuario prefirió el script en local a un workflow de Actions, de momento.

### 2. Preguntas y respuestas
**P1. ¿Script local, o script más workflow?** R: Solo el script en local por ahora.

### 3. Fuentes analizadas
- `ci.yml` (compilaba solo la arquitectura del runner y sin releases) y el `release.yml` de la app Electron (dos DMG, uno por arquitectura).

### 4. Decisiones
- Un único DMG **universal** (`ARCHS="arm64 x86_64"`): en Swift no hay módulos nativos por arquitectura, así que no hacen falta dos instaladores como en Electron.
- Firma ad hoc hasta tener Developer ID; el usuario abre con clic derecho → Abrir la primera vez (documentado en README y landing).
- `Tools/make-release.sh` con `--publish` opcional: etiqueta `v<versión>`, `gh release create` con notas generadas. Verificado en local: 95 tests, binario `x86_64 arm64`, DMG de 12 MB que monta y arranca.

### 5. Alternativas descartadas
- Workflow de Actions para releases: aplazado; cuando se quiera, debe ejecutar este mismo script.
- Dos DMG por arquitectura: innecesario con un binario universal.

### 6. Pendiente de comprobar
- Probar el DMG en un Mac Intel real.
- ~~Publicar la primera release `v3.0.0` cuando el usuario lo indique~~ Publicada el 16-10-2026 (`CAOBA-3.0.0.dmg`, 12 MB, binario universal); la API de GitHub ya la devuelve como última release, así que la landing enlaza el DMG.

## 2026-10-16 — Landing sin referencias a la versión anterior y con capturas de la app

### 1. La petición tal como se ha entendido
*(modo directo, sin análisis previo)* Quitar del README y de `index.html` cualquier referencia a la reescritura en Swift o a la versión anterior (Electron), y usar capturas de pantalla reales de la app en la landing, cargando la carpeta `~/Downloads/A&S` como carpeta de ejemplo.

### 2. Preguntas y respuestas
Ninguna.

### 3. Fuentes analizadas
- `README.md` e `index.html` actuales; `AppState` (arranque de la app) y las vistas de los módulos para dejarlas con contenido.

### 4. Decisiones
- Las capturas las hace **la propia app** con argumentos de arranque (`--folder`, `--module`, `--window`, `--state`, `--screenshot`, `--delay`): `screencapture -l` necesita permiso de grabación de pantalla y fallaba; la app captura su propia ventana con `CGWindowListCreateImage` (resuelto por `dlsym` para no arrastrar el aviso de obsolescencia). Antes de capturar activa la app, pone el foco en una vista invisible (si no, el primer botón salía con el anillo rojo) y fija 1440×900, que en Retina da 2880×1800.
- `--state clave=valor` deja módulos con contenido en pantalla (Collage en «Aleatorias» con plantillas de 3 fotos, QR con una URL, marca de agua con el logo de CAOBA, renombrador con un patrón de fecha). Son enganches de una línea en `onAppear` de cada vista.
- En la landing: captura grande del Slideshow bajo el hero (con enlace a la imagen completa), y una captura al principio de cada tarjeta de módulo. En las tarjetas estrechas la imagen se amplía al 200 % y se desplaza con `--x`/`--y` a la zona interesante (formulario o vista previa). La imagen social (`og:image`) es también la captura del Slideshow.
- Capturas guardadas en `assets/screenshots/` en JPEG a 1600 px (unos 200 KB cada una) para no cargar el repo con PNG de 2880 px.
- Shutter Count no lleva captura: no hay ningún RAW con contador de disparos a mano y la pantalla vacía no aporta nada.

### 5. Alternativas descartadas
- `screencapture` o ScreenCaptureKit: requieren permiso de grabación de pantalla que no se puede conceder desde la terminal.
- `cacheDisplay` de la vista raíz: dejaba la barra lateral en blanco (no pinta los fondos translúcidos); queda solo como respaldo.
- Persistir el contenido de los módulos en `.caoba` para las capturas: solo el Slideshow guarda su estado por carpeta; añadir persistencia a los demás solo para esto era desproporcionado.

### 6. Pendiente de comprobar
- Revisar la landing publicada en Pages (móvil y tema claro) y repetir las capturas cuando cambie la interfaz; conseguir un RAW con contador para la captura de Shutter Count.

## 2026-10-16 — Titular de la landing en degradado

### 1. La petición tal como se ha entendido
*(modo directo, sin análisis previo)* En el titular «CAOBA» de la landing, todas las letras claras y el rojo entrando en degradado desde abajo en todas ellas, en lugar de «CAO» blanco y «BA» rojo.

### 2. Preguntas y respuestas
Ninguna.

### 3. Fuentes analizadas
- `index.html` (CSS del hero).

### 4. Decisiones
- Degradado vertical recortado al texto (`background-clip: text`): rojo CAOBA en el 22 % inferior, fundiendo al color de tinta a partir del 68 %. En tema claro la «tinta» es negra, así que las letras van de negro a rojo; en oscuro, de blanco a rojo.

### 5. Alternativas descartadas
- Mantener el `em` rojo en «BA»: era justo lo que se quería cambiar.

### 6. Pendiente de comprobar
Nada.

## 2026-10-16 — Botón de donativo en la landing

### 1. La petición tal como se ha entendido
*(modo directo, sin análisis previo)* Añadir un botón de donativo en la barra superior y entre los botones principales del hero de `index.html`.

### 2. Preguntas y respuestas
Ninguna.

### 3. Fuentes analizadas
- `index.html` (ya tenía el enlace a Buy Me a Coffee en la sección de descarga).

### 4. Decisiones
- Mismo enlace en los tres sitios (`buymeacoffee.com/marcosesperon`), abre en pestaña nueva. En la barra va como chip junto a idioma y tema; en el hero como tercer botón tras «Descargar» y «Ver el código»; el de la sección de descarga se mantiene.
- Icono de taza en SVG en línea en lugar del emoji: el emoji depende de la fuente del navegador y salía diminuto con la fuente monoespaciada.
- En móvil el chip de la barra se queda solo con la taza para que quepa; la regla necesita más especificidad que las de idioma (`html[data-lang] ...`), si no estas ganan y el texto vuelve a aparecer.

### 5. Alternativas descartadas
- Un botón rojo (primario) para el donativo: el primario debe seguir siendo la descarga.

### 6. Pendiente de comprobar
Nada.

## 2026-10-16 — Donativo en la app y banda de versión nueva

### 1. La petición tal como se ha entendido
Tres cosas en la app de macOS, tomando como referencia la versión anterior:

1. **Botón de donativo en el pie de la barra lateral**, bajo «caobafoto.com», que abre `buymeacoffee.com/marcosesperon` en el navegador. Texto «Hacer donación» con icono de taza, estilo nativo (enlace o botón discreto, no el amarillo de Buy Me a Coffee).
2. **Diálogo de donativo al arrancar**, un segundo después de abrir la app, con la misma cadencia que la versión anterior: se muestra en el primer arranque y después como máximo **cada 7 días**. Textos adaptados de los antiguos («CAOBA es gratuito», «si te ha resultado útil… considera una pequeña donación», firma y enlace a caobafoto.com) en español e inglés; botones «Hacer donación» y «Ahora no». La fecha del último aviso se guarda en la preferencia ya reservada (`caoba.donation.lastShown`). No se muestra cuando la app arranca en modo captura (`--screenshot`).
3. **Banda de versión nueva al arrancar**: la comprobación contra las releases de GitHub ya existe y deja un enlace en el pie de la barra lateral. Se añade además una banda fina sobre el contenido, «Nueva versión X.Y.Z disponible», con botón «Descargar» (abre la página de la release) y botón de cerrar. Una vez cerrada no vuelve a aparecer para esa misma versión (se guarda la versión descartada); el enlace del pie se mantiene siempre.

*Confirmación: «confirmo, adelante con el plan pero aprovecha para quitar el botón principal de ver el código y poner el de donativo con fondo amarillo» (16-10-2026). Se añade por tanto, en la landing: quitar «Ver el código» del hero y poner el botón de donativo en amarillo Buy Me a Coffee.*

### 2. Preguntas y respuestas
**P1. ¿Cadencia del diálogo de donativo?** R: «manten» (la de la versión anterior: primer arranque y luego cada 7 días).
**P2. ¿Basta el enlace del pie para la versión nueva o también aviso al arrancar?** R: también, con la banda al arrancar.

### 3. Fuentes analizadas
- App anterior: `assets/js/caoba.js` (diálogo cada 7 días guardando la fecha en `localStorage`, aviso flotante de versión durante 15 s) e `index.html` (botón en el pie de la barra lateral y textos del diálogo).
- App nueva: `AppState` (ya existía `VersionCheck` con comparación semver y el enlace del pie), `Preferences` (clave del donativo ya reservada), `ContentView`.

### 4. Decisiones
- **Pie de la barra lateral**: botón enlace «Hacer donación» con icono de taza bajo «caobafoto.com», mismo estilo que ese enlace. Las URL de la web y del donativo son constantes de `AppState` para que pie y hoja compartan enlace.
- **Hoja de donativo** (`DonationSheet`): hoja nativa con icono de la app, título en Doto, los dos párrafos adaptados de la antigua, firma, enlace a caobafoto.com y botones «Ahora no» / «Hacer donación» (principal, abre el navegador y cierra). La fecha se guarda **al mostrarla**, igual que antes, así «Ahora no» y cerrar cuentan igual. El enlace no es enfocable para que el foco inicial de la hoja no caiga en él con un anillo rojo.
- **Banda de versión** (`UpdateBanner`): fila fina encima de la barra de carpeta con icono, «Nueva versión X disponible», «Descargar» y cierre; entra y sale con animación. Al cerrar se guarda la versión en `caoba.update.dismissedVersion`; la banda solo vuelve con una versión distinta. El enlace del pie se mantiene siempre.
- Orden de arranque: argumentos de línea de comandos → hoja de donativo (espera 1 s) → comprobación de versión. En modo captura (`--screenshot`) no se enseña nada salvo que se pida con `demo.donation` / `demo.update`, que sirven para revisar las pantallas.
- Para capturar la hoja hubo que pedir también las ventanas por encima de la principal (`optionOnScreenAboveWindow` dentro del marco de la ventana), porque una hoja es una ventana aparte.
- Traducciones añadidas al final del catálogo sin reordenarlo (Xcode ordena con su propio criterio y regenerar el JSON producía un diff de todo el fichero).
- **Landing**: el hero queda con «Descargar para macOS» (rojo) e «Invítame a un café» (amarillo `#FFDD00`, texto oscuro); «Ver el código» desaparece del hero pero GitHub sigue en la barra superior y en la sección de descarga.

### 5. Alternativas descartadas
- Aviso de versión flotante de 15 s como el antiguo: desaparece solo y se pierde; la banda se queda hasta que el usuario decide, y se recuerda por versión para no molestar.
- Guardar la fecha del donativo solo al pulsar «Hacer donación»: la hoja saldría en cada arranque a quien no quiera donar.
- Botón amarillo de Buy Me a Coffee dentro de la app: en la app se mantiene el aspecto nativo; el amarillo se usa solo en la web.

### 6. Pendiente de comprobar
- Ver la banda con una release real más nueva: publicada `v3.0.1` el 16-10-2026 con estos cambios (`CAOBA-3.0.1.dmg`, 11 MB); un CAOBA 3.0.0 instalado debería mostrarla al arrancar. Nota para el futuro: la compilación en Release reordena `Localizable.xcstrings`, así que conviene compilar y commitear antes de lanzar `--publish`, que exige el árbol limpio.

## 2026-10-16 — Repositorio renombrado a `caoba`

### 1. La petición tal como se ha entendido
*(modo directo, sin análisis previo)* Cambiar el repositorio de `marcosesperon/caoba-photo-utils` a `marcosesperon/caoba`, y que la app actualice sus enlaces y la comprobación de versiones.

### 2. Preguntas y respuestas
**P1. ¿Lo renombro yo con `gh` y cambio las referencias?** R: «dale».

### 3. Fuentes analizadas
- Referencias al nombre antiguo: `AppState` (API de releases y enlace de la banda), `index.html` (enlaces, consulta de la release, `og:image`), `README.md` (insignia y enlace a la release).

### 4. Decisiones
- Renombrado con `gh repo rename caoba`; `gh` actualizó el remoto local. GitHub redirige el nombre antiguo en web, git y API, así que CAOBA 3.0.0 y 3.0.1 siguen encontrando las releases.
- Todas las referencias pasan al nombre nuevo. La landing cambia de URL a `https://marcosesperon.github.io/caoba/` (Pages no redirige); se actualiza también la URL de inicio del repositorio.
- La carpeta local sigue llamándose `caoba-photo-utils`: renombrarla no afecta a nada del proyecto y se puede hacer en cualquier momento desde Finder.
- Las entradas anteriores de esta bitácora conservan el nombre antiguo: es un registro histórico.

### 5. Alternativas descartadas
- Dejar las URL antiguas confiando en la redirección: funciona, pero deja el nombre viejo en la app y la web para siempre.

### 6. Pendiente de comprobar
- Que Pages sirva la landing en la URL nueva tras el push; publicar 3.0.2 cuando convenga para que la app lleve las URL nuevas.

## 2026-10-16 — Texto de uso en las proporciones

### 1. La petición tal como se ha entendido
En todos los sitios donde se presentan proporciones (16:9, 9:16, 4:5, 5:4, 3:2, 2:3…) añadir un texto de ejemplo de uso (TV, Reels, Stories, publicación de Instagram…). Confirmada con la tabla de textos propuesta: «me valen, adelante».

### 2. Preguntas y respuestas
**P1. ¿Valen estos textos? (16:9 TV, YouTube · 9:16 Reels, Shorts, TikTok, Stories · 4:5 Publicación de Instagram · 5:4 Publicación apaisada · 3:2 / 2:3 Foto clásica horizontal/vertical · 1:1 Cuadrado, Instagram · 3:1, 2:1 Panorámica · 1:3 Tira vertical)** R: sí.

### 3. Fuentes analizadas
- `ProcessorView` (recorte), `TemplateViews` (filtro de plantillas y tarjetas), `SlideshowDocument` (formato de vídeo, que ya tenía texto de uso), `templates.json` (proporciones existentes: 16:9, 9:16, 4:5, 5:4, 3:2, 2:3, 1:1, 3:1, 2:1, 1:3).

### 4. Decisiones
- Un único sitio para los textos (`AspectUsage`): `hint(for:)` da el texto y `text(for:)` compone «16:9 · TV, YouTube». Lo usan el recorte del Procesador y el filtro «Proporción» de plantillas (Collage, Slideshow y editor de secuencia).
- En las tarjetas de plantilla se mantiene «3 · 16:9» y el uso va en el tooltip, para no ensanchar la cuadrícula.
- El formato de vídeo del Slideshow ya tenía texto; se unifican los términos con la tabla (Reels, Shorts, TikTok, Stories / Publicación de Instagram / Publicación apaisada).
- Argumento de captura `collage.aspect=<etiqueta>` para ver el filtro con una proporción elegida.

### 5. Alternativas descartadas
- Texto de uso también en las tarjetas de plantilla: no cabe a 90 puntos sin partir en dos líneas.

### 6. Pendiente de comprobar
Nada.

## 2026-10-16 — Composición de collages según el contenido de las fotos

### 1. La petición tal como se ha entendido
Al componer secuencias de collages (en Collage y en los collages del Slideshow, que comparten editor), añadir un reparto **según el contenido** de las fotos, además del aleatorio actual:

- En la hoja de «Componer» aparece un selector «Reparto: Aleatorio / Según el contenido» y, con el segundo, una casilla «Permitir reordenar fotos» (desactivada por defecto). Se respetan las plantillas permitidas marcadas en esa misma hoja.
- Al pulsar Componer con «Según el contenido», la app analiza cada foto marcada (caras y sujeto principal con Vision, sobre miniatura, con progreso y cancelable; el resultado se guarda en memoria para no repetirlo).
- De cada foto se obtiene: orientación, caja del sujeto (unión de caras o, si no hay, de objetos salientes), tamaño del sujeto respecto al encuadre y número de caras.
- Para cada grupo de fotos consecutivas (orden de la lista), el algoritmo elige entre las plantillas permitidas la que mejor puntúa, decidiendo también cuántas fotos van en el grupo (1 a 9, lo que permitan las plantillas) y qué foto va en cada celda. Puntúa: cuánto del sujeto sobrevive al recorte de la celda, si la orientación casa, caras y sujetos grandes en celdas grandes, y penaliza fotos de grupo en celdas pequeñas. Si una foto no tiene nada detectable, cuenta solo la orientación (como ahora).
- Con «Permitir reordenar fotos», el algoritmo puede intercambiar fotos entre collages cercanos para mejorar el encaje.
- El resultado es la misma secuencia editable de siempre, con los puntos de foco ya puestos a partir del análisis (no hace falta «Ajustar foco» después), y se puede retocar celda a celda como hasta ahora.
- El reparto aleatorio sigue igual.

*Confirmación: «dale» (16-10-2026). Plan aprobado: «adelante».*

### 2. Preguntas y respuestas

**P1. ¿Dónde vive la función: selector «Reparto: Aleatorio / Según el contenido» en la hoja de Componer, o botón nuevo?** R: 1, el selector en la hoja de Componer.
**P2. ¿Mantener el orden de las fotos o permitir reordenar?** R: mantener el orden por defecto, con una casilla «Permitir reordenar fotos» en la hoja.
**P3. ¿Decide el algoritmo cuántas fotos van en cada collage o se fija un tamaño?** R: 1, lo decide el algoritmo entre las plantillas permitidas (el filtro «Fotos» acota si hace falta).

### 3. Fuentes analizadas
- `FocusDetector` (caras y saliencia con Vision; solo devolvía un punto), `CropGeometry.rect(in:ratio:focus:)` (el recorte real del render), `CollageRenderer.group` y `assignByAspect` (esta última existía pero no la usaba la app), `CollageSequenceEditor`, `TemplatePickerSheet` y `SlideshowDocument.compose` (los dos sitios donde se compone), `AppState` (orden de ficheros).

### 4. Decisiones
- **Modelo sin cambios**: la secuencia sigue siendo «plantillas en orden, fotos consumidas en orden de la lista». El reparto por contenido decide un **nuevo orden de las fotos marcadas** (dentro de cada grupo, y entre grupos si se permite reordenar) y la app lo aplica a la lista con `reorderCheckedFiles`, dejando las no marcadas donde estaban. Así las tarjetas, el arrastre y el editor de foco funcionan igual que antes.
- **Detector**: `FocusResult` lleva ahora la caja del sujeto (unión de caras o de objetos salientes); el punto sigue igual, así que nada de lo existente cambia. El análisis usa el modo «Caras» (caras y, si no hay, saliencia) y comparte caché con «Ajustar foco».
- **Puntuación foto‑celda** (`ContentComposer.score`): con sujeto, 70 % cuánto sujeto sobrevive al recorte de la celda (mismo cálculo que el render) y 30 % orientación; sin sujeto, solo orientación. Más 0,3 × importancia × tamaño relativo de la celda; −0,4 × (1 − tamaño) si hay 3 o más caras; −0,15 × (1 − importancia) × tamaño para no regalar la celda grande a una foto sin interés. La proporción real de una celda es la de la celda por la del lienzo.
- **Reparto**: programación dinámica sobre la posición en la lista, maximizando la suma de puntuaciones; así el tamaño de cada grupo lo decide el contenido y el óptimo es exacto manteniendo el orden. Asignación foto‑celda exhaustiva hasta 5 fotos y voraz (celdas grandes primero) de 6 a 9. Las fotos que no quepan quedan fuera al final, penalizadas para que solo pase si no hay otra.
- **Reordenar**: búsqueda local de intercambios de una foto entre collages vecinos (siguiente y el de después) mientras suba la puntuación, máximo 6 pasadas, y al final cada grupo vuelve a elegir plantilla de su tamaño.
- **Interfaz**: `ComposeModeControls` (selector «Reparto» y casilla) compartido por las dos hojas; progreso «Analizando X de N fotos…» con Cancelar en la fila de botones del editor; cancelar deja todo como estaba. Las hojas crecen 60 puntos para los controles.
- Ganchos de captura/prueba: `collage.compose=content` abre la hoja en ese modo, `collage.autocompose=content` (+ `collage.reorder=1`) compone con todas las plantillas de 2 a 4 fotos, y `capture.sheets=1` incluye las hojas en la captura.

### 5. Alternativas descartadas
- Guardar el orden de fotos dentro de cada `SequenceItem`: obligaba a cambiar `rows(from:)`, el arrastre de tarjetas y el editor de foco; reordenar la lista es más simple y el usuario ve lo que ha pasado.
- Asignación foto‑celda con el método húngaro: exacto para cualquier tamaño, pero con 5 fotos las permutaciones son 120 y de 6 a 9 el voraz por celdas grandes es suficiente.
- Búsqueda global con reordenación libre entre todas las fotos: coste combinatorio y el usuario pidió respetar el orden por defecto; el intercambio entre vecinos mejora lo que importa sin desordenar el reportaje.
- Usar `assignByAspect` existente: solo mira proporción; se deja como está por si se usa en otro sitio.

### 6. Pendiente de comprobar
- Afinar pesos con reportajes reales (paisajes, detalles) y ver si el análisis sobre RAW resulta lento en carpetas grandes.

## 2026-10-16 — Ajustes de Componer guardados por carpeta y filtro por tipo de plantilla

### 1. La petición tal como se ha entendido
Dos mejoras en la hoja «Componer secuencia» (Collage y Slideshow):

1. **Guardar los ajustes de la hoja por carpeta**, en el `.caoba`, para que al volver a entrar (en la misma sesión o en otra) aparezca como se dejó: reparto (aleatorio / según el contenido), «Permitir reordenar fotos», filtros de fotos, proporción y tipo, y las plantillas marcadas. Un juego para Collage (sección nueva `collage` del `.caoba`) y otro para Slideshow (dentro de su sección `slideshow`, que ya guarda la secuencia). Se guardan al pulsar Componer y también al cambiar la selección, y «Reiniciar» los borra como al resto de ajustes de la carpeta.
2. **Filtro «Tipo»** en los filtros de plantillas del Slideshow (hojas Componer y Añadir): «Todas / Básicas / Superpuestas», para poder marcar «Todas las visibles» de un tipo concreto. En Collage no aparece porque ahí no se ofrecen las superpuestas.

*Confirmación: «si» (16-10-2026). Plan aprobado: «adelante».*

### 2. Preguntas y respuestas
**P1. ¿Ajustes globales de la app o por carpeta en el `.caoba`?** R: 2, por carpeta.

### 3. Fuentes analizadas
- `SlideshowPreset` y `SlideshowDocument.makePreset/loadPresetIfNeeded` (el Slideshow ya guardaba la secuencia por carpeta con autoguardado), `CaobaConfig` (secciones del `.caoba`, `resetSettings` respeta solo `renameHistory`), `CollageView` (no guardaba nada por carpeta), `TemplateFilters` y `TemplatePickerSheet`.

### 4. Decisiones
- Un único tipo `ComposeSettings` (reparto, reordenar, filtros y plantillas marcadas, todo opcional) que el Slideshow guarda dentro de su sección `slideshow.collage.compose` y Collage en una sección nueva `collage.compose` del `.caoba` (`CollageFolderSettings`). Los `.caoba` antiguos siguen leyéndose.
- En la app, el estado de la hoja (`ComposeSheetState`) vive en el padre (Collage: `CollageView`; Slideshow: `SlideshowDocument`) y la hoja lo recibe por binding; así se puede guardar y restaurar. En Collage las plantillas marcadas son las mismas de la pestaña «Aleatorias», como ya ocurría.
- Guardado: Collage escribe la sección en cuanto cambia cualquier ajuste o la selección (con guarda para no escribir mientras se restaura o si la carpeta aún no es la cargada); Slideshow usa su autoguardado de 2 s con `didSet`. Al cambiar de carpeta se restaura lo de esa carpeta; «Reiniciar» (`configResetToken`) vuelve a los valores por defecto en pantalla además de borrar la sección.
- Filtro «Tipo» (`CollageTemplates.TemplateType`: básicas / superpuestas) en `TemplateFilters`, solo donde se ofrecen las superpuestas (las dos hojas del Slideshow). El filtro de la hoja de Añadir del Slideshow tiene su propio estado y no se guarda.
- Ganchos de captura: `collage.compose=open` y `slideshow.compose=open` abren la hoja tal como esté guardada.
- Verificado con BOOK: componer por contenido con reordenar, cerrar la app, volver a abrir la hoja y aparece «Según el contenido», reordenar marcado y las 332 plantillas de 2 a 4 fotos seleccionadas; el `.caoba` tiene las dos secciones.

### 5. Alternativas descartadas
- Guardar en preferencias globales: el usuario prefirió por carpeta (P1).
- Un selector de tipo también en Collage: allí no se ofrecen superpuestas, sería un filtro sin efecto.

### 6. Pendiente de comprobar
Nada.

## 2026-10-16 — Variedad en el reparto según el contenido

### 1. La petición tal como se ha entendido
«El componer según el contenido está funcionando, pero repite mucho»: en el Slideshow, con 16:9, salían «Single» y «60/40» una y otra vez. Plan aprobado («dale»): penalizar repetir plantilla, singles solo para fotos que destaquen y una pasada de variedad.

### 2. Preguntas y respuestas
Ninguna.

### 3. Fuentes analizadas
- `ContentComposer.compose` (reparto por programación dinámica) y la captura del timeline del usuario.

### 4. Decisiones
- **Causa**: el reparto maximizaba la puntuación por grupo y, con fotos parecidas, la plantilla ganadora es siempre la misma; las de una foto salían muy favorecidas (todo el sujeto se conserva y se llevan la bonificación de celda grande). Nada penalizaba repetir.
- **Memoria del grupo anterior**: la programación dinámica pasa a tener como estado (posición, plantilla del grupo anterior). Repetir la misma plantilla resta 0,3 por foto del grupo; repetir solo el número de fotos resta 0,08 por foto, para que varíe también el tamaño.
- **Singles**: una plantilla de una foto resta 0,25 salvo que la foto tenga importancia ≥ 0,85 (grupo de gente o sujeto que llene el encuadre).
- **Pasada de variedad** al final: si la plantilla de un grupo ya salió en los tres anteriores, se prueba la mejor del mismo número de fotos que no haya salido en los tres anteriores ni en los tres siguientes, y se cambia si pierde como mucho 0,12 por foto. Cubre el «single, 60/40, single, 60/40» que la memoria de un solo grupo no ve.
- Las puntuaciones de cada (posición, plantilla) se calculan una sola vez; el estado extra multiplica por el número de plantillas, pero con 300 plantillas y 100 fotos sigue siendo inmediato.
- Tests: con 24 fotos iguales y seis plantillas 16:9, ninguna se repite más de dos veces seguidas, salen al menos tres distintas y los singles no pasan de un tercio; un single sí se elige para una foto que destaca.

### 5. Alternativas descartadas
- Estado con las dos plantillas anteriores en la programación dinámica: exacto, pero el coste crece con el cuadrado del número de plantillas (con 300 permitidas, cientos de millones de operaciones). La pasada de variedad consigue casi lo mismo.
- Quitar las plantillas de una foto del reparto automático: el usuario las permite a propósito; mejor reservarlas a fotos que destacan.

### 6. Pendiente de comprobar
- Si en reportajes reales sigue pareciendo repetitivo, subir `repeatPenalty` o ampliar `varietyWindow`.

## 2026-10-16 — Marca «Fin del vídeo» solo cuando hay vídeo

### 1. La petición tal como se ha entendido
*(modo directo, sin análisis previo)* En el timeline del Slideshow, sin fotos ni collages (duración 0:00) no tiene sentido mostrar la marca «Fin del vídeo» pegada al 0:00.

### 2. Preguntas y respuestas
Ninguna.

### 3. Fuentes analizadas
- `SlideshowTimelineView.videoEndMarker`.

### 4. Decisiones
- La marca solo se dibuja cuando la duración total del vídeo es mayor que cero. Con pistas de música pero sin fotos tampoco aparece: no hay vídeo que termine.

### 5. Alternativas descartadas
- Mostrarla cuando haya pistas aunque no haya fotos: seguiría pegada al 0:00 sin aportar nada.

### 6. Pendiente de comprobar
Nada.

## 2026-10-16 — Proporción por defecto igual al formato del vídeo

### 1. La petición tal como se ha entendido
*(modo directo, sin análisis previo)* En el Slideshow, al abrir «Añadir collage» o «Componer secuencia», el filtro «Proporción» debe partir de la proporción del formato de vídeo elegido (16:9, 9:16…), no de «Todas».

### 2. Preguntas y respuestas
Ninguna.

### 3. Fuentes analizadas
- `SlideshowDocument` (formato, filtros de las hojas, carga del preset y valores por defecto).

### 4. Decisiones
- Al cargar una carpeta sin ajustes de Componer guardados, y al reiniciar, los filtros de las dos hojas parten de la etiqueta del formato (`format.label`). Si hay ajustes guardados por carpeta, mandan ellos.
- Si el usuario cambia el formato de vídeo y el filtro seguía siendo el del formato anterior, pasa al nuevo; si lo había cambiado a mano («Todas» u otra), se respeta.

### 5. Alternativas descartadas
- Forzar la proporción del vídeo cada vez que se abre la hoja: pisaría lo que el usuario eligió y lo guardado por carpeta.

### 6. Pendiente de comprobar
Nada.

## 2026-10-16 — Vista previa en grande de los collages

### 1. La petición tal como se ha entendido
En el editor de foco de los collages (Collage y Slideshow), añadir una vista «Resultado» que muestre el collage **renderizado con las opciones reales de salida** (separación, fondo, esquinas, sombra, título y logo en Collage; las de los collages del vídeo en Slideshow), a tamaño de pantalla, antes de generar nada:

- Un conmutador «Encuadre / Resultado» en la cabecera del editor; las flechas de anterior y siguiente siguen funcionando en los dos modos.
- El resultado se renderiza con el motor real pero a resolución de pantalla (lado mayor en torno a 1600 px), en segundo plano y con indicador mientras tarda; se vuelve a renderizar al cambiar de collage o al volver de «Encuadre» tras mover un encuadre o cambiar la plantilla.
- Al volver a «Encuadre» se puede corregir sin cerrar nada. No hay edición directa sobre el resultado.
- En el Slideshow, el editor recibe las opciones de collage del vídeo (fondo, separación, esquinas, sombra), que son las que se usan al generar.

*Confirmación: «dale» (16-10-2026). Plan aprobado: «si».*

### 2. Preguntas y respuestas

**P1. ¿Dentro del editor de foco (pestaña «Resultado») o en una hoja aparte?** R: 1, dentro del editor de foco.

### 3. Fuentes analizadas
- `FocusEditorSheet` (editor de foco de Collage), `CollageInspector` (el Slideshow no usa la hoja: edita el enfoque en su inspector), `CollageRenderer.render`, `CollageOptions` de cada módulo.

### 4. Decisiones
- Una vista reutilizable `CollageResultView(row:options:)` que renderiza con el motor real, en segundo plano, con el lado mayor limitado a 1600 px; se recalcula sola cuando cambian la fila (encuadres, plantilla, fotos) o las opciones, gracias a `.task(id:)` con esa clave, y mientras llega el nuevo se deja el anterior a la vista.
- Conmutador «Encuadre / Resultado» (`CollageViewModePicker`) en la cabecera del editor de foco de Collage **y** en el inspector de collage del Slideshow, que es donde allí se edita el enfoque. En «Resultado» se ocultan los controles de edición (cambiar plantilla, centrar) y cambia el texto de ayuda.
- Cada sitio pasa sus opciones reales: Collage las de su panel de salida (título y logo incluidos); Slideshow las de collage del vídeo (`collageOptions.collage`), que son las que se usan al generar.
- Gancho de captura `collage.editor=result`: tras componer, abre el editor del primer collage en «Resultado».

### 5. Alternativas descartadas
- Hoja aparte de vista previa: descartada en P1.
- Renderizar al tamaño final: innecesario para juzgar el resultado y mucho más lento con fotos de 6000 px.

### 6. Pendiente de comprobar
Nada.

## 2026-10-16 — Sincronizar los cortes del Slideshow con la música

### 1. La petición tal como se ha entendido
En el Slideshow, sincronizar los cambios de foto o collage con la música:

- **Detección de golpes**: el motor analiza cada pista (sobre el mismo audio que ya decodifica para la sonoridad) y obtiene los golpes y el tempo. Los golpes se sitúan en el tiempo del vídeo teniendo en cuenta el inicio de cada pista, su recorte y el bucle de la lista.
- **Ajuste**: un botón «Ajustar al ritmo» en la pestaña Música. Las fotos se adaptan a la música (P1): cada foto o collage dura hasta el siguiente golpe elegido, dentro de un mínimo y un máximo razonables (1 y 15 s, los límites actuales del control). Las duraciones propias fijadas a mano se respetan (P3) y los cortes siguientes se recalculan a partir de ellas.
- **Densidad** (P2): automática por defecto, eligiendo los golpes por foto que dejen la duración media más cerca de los «segundos por foto» configurados; con un selector visible «Golpes por foto: Auto / 1 / 2 / 4 / 8 / 16» para afinar y volver a aplicar.
- **Timeline**: los golpes se dibujan como marcas finas en la regla cuando hay pistas analizadas, para ver dónde caen.
- **Resultado editable**: las duraciones calculadas se aplican a cada foto y collage y se ven en el timeline como ahora; si luego se cambia una a mano pasa a ser propia y «Ajustar al ritmo» la respeta en adelante. Se guardan con el resto del proyecto en el `.caoba`.
- Sin pistas, o si no se detecta un ritmo claro, el botón avisa y no cambia nada.
- **Es opcional y bajo demanda**: por defecto el Slideshow funciona exactamente como ahora (duración global por foto y duraciones propias). Nada se analiza ni se cambia hasta que el usuario pulsa «Ajustar al ritmo»; las marcas de golpes en la regla solo aparecen después de ese análisis.

*Confirmación: «sí, pero esto es opcional bajo un botón… por defecto tiene que funcionar como ahora» (16-10-2026); incorporado al punto anterior.*

### 2. Preguntas y respuestas

**P1. ¿Las fotos se adaptan a la música (duración hasta el siguiente golpe elegido) o solo se desplazan los cortes cercanos?** R: 1, las fotos se adaptan a la música.
**P2. ¿Densidad de cortes automática, manual (golpes por foto) o las dos?** R: 3, automática por defecto con el selector visible para afinar.
**P3. ¿Qué pasa con las duraciones propias fijadas a mano?** R: 1, se respetan; solo se ajustan las demás.
**P4 (del usuario). ¿Se tiene en cuenta que puede haber varias pistas, cada una con su ritmo, y que el cálculo debe ser según el audio que suene en cada momento?** R: sí; cada pista se analiza por separado, los golpes se pasan al tiempo del vídeo con los segmentos que ya calcula el motor para la mezcla (inicio, recorte, repetición), en el crossfade mandan los golpes de la pista que entra, la densidad automática se decide por tramo y el resumen muestra el tempo de cada pista. Donde no suena nada, duración global. Plan aprobado: «dale».

### 3. Fuentes analizadas
- `LoudnessMeter.measure` (lectura PCM con `AVAssetReader`), `AudioPlan.build` (segmentos de la mezcla: inicio, recorte, crossfade de 3 s, repetición), `SlideshowTimeline` (la foto siguiente empieza a entrar cuando a la actual le queda la transición), `SlideshowDocument` (duraciones por foto, «mantener» por collage, preset), `MusicTab` y la regla del timeline.
- Prueba con las dos canciones reales del proyecto BOOK: 100 ppm y 70 ppm detectados (coinciden con el tempo conocido de ambas), 8 s de análisis por canción de 3 minutos.

### 4. Decisiones
- **`AudioDecoder`** común: el bucle de lectura PCM sale del medidor de sonoridad para que lo use también el detector.
- **`BeatDetector`** sin dependencias: envolvente de ataques por tramos de 512 muestras (subida de energía logarítmica respecto a los 4 tramos anteriores, en banda completa y con más peso en graves por debajo de 150 Hz), tempo por autocorrelación entre 60 y 200 ppm con preferencia suave por 120 ppm para no saltar de octava, afinado del periodo por parábola, fase por máxima energía sobre la rejilla y seguimiento golpe a golpe pegándose al ataque más fuerte (±12 % del periodo) con periodo adaptativo. Confianza = (pico − mediana) de la autocorrelación; fiable a partir de 0,12 (las canciones reales dan 0,15–0,17; el ruido blanco, no).
- **Golpes en tiempo de vídeo** (`RhythmPlanner.videoBeats`): con los mismos segmentos de `AudioPlan`; cada segmento aporta sus golpes solo hasta que empieza el siguiente, así en el crossfade manda la pista que entra y cada tramo lleva su periodo.
- **`RhythmPlanner.plan`**: recorre los elementos; el centro de la transición debe caer en un golpe (`d = golpe − transición/2 − t`). Densidad automática por tramo: la potencia de dos (1–16) que más acerque `golpes × periodo` a los segundos por foto. Si el golpe elegido se sale de 1–15 s, el golpe dentro de límites más cercano a lo pedido; sin golpes (no suena nada), el objetivo. Los fijos se respetan y el siguiente se resincroniza.
- **Aplicación en el documento**: `adjustToRhythm` analiza las pistas que falten (en paralelo, caché por ruta), hace **dos pasadas** (las pistas que empiezan en una foto se mueven con las duraciones nuevas), escribe las duraciones en `photoDurations` y en el «mantener» de los collages (para un collage, objetivo y mínimo cuentan su aparición de fotos), y apunta en `rhythmItems` qué elementos fijó. `setDuration` a mano quita el elemento de esa lista, así pasa a propio. `beatsPerCut` y `rhythmItems` se guardan en el preset.
- **Interfaz**: grupo «Ritmo» en Música (selector Auto/1/2/4/8/16, botón con progreso, aviso en rojo CAOBA si no hay pistas o ritmo claro, texto que deja claro que es opcional), tempo de cada pista en su fila, marcas finas de golpe bajo la regla solo cuando hay análisis.
- Por defecto nada cambia: sin pulsar el botón no se analiza ni se toca ninguna duración.
- Gancho de prueba `--state slideshow.rhythm=1`. El `.caoba` de BOOK se restauró tras la prueba.

### 5. Alternativas descartadas
- FFT y flujo espectral multibanda: más preciso en teoría, pero la envolvente por energía con banda de graves acierta con las canciones probadas y evita dependencias y código.
- Analizar en el arranque o al añadir pistas: el usuario quiere que sea opcional; además son 8 s por canción.
- Mezclar golpes de las dos pistas en el crossfade: los cortes saltarían entre dos ritmos.

### 6. Pendiente de comprobar
- Más canciones (tempos lentos, música sin percusión) para afinar el umbral de confianza y la preferencia por 120 ppm.

## 2026-10-16 — Presets con nombre en Procesador, Marca de agua y Collage

### 1. La petición tal como se ha entendido
En Procesador, Marca de agua y Collage:

- **Presets con nombre, globales de la app** (P1): un control «Preset» en la cabecera del módulo con un menú que lista los guardados, los aplica con un clic y ofrece «Guardar como…» (pide nombre; si ya existe, lo sustituye), «Actualizar con los ajustes actuales» y «Eliminar». Al tocar cualquier ajuste tras aplicar uno, el menú vuelve a mostrar «Sin preset» para dejar claro que lo actual ya no coincide.
- **Qué guarda cada preset**: todos los ajustes del módulo. Procesador: autorrotar, recorte (proporción, personalizada, anclaje), redimensionado (lado mayor), calidad, formato. Marca de agua: ruta del PNG, modo, posición, tamaño, opacidad, espaciado. Collage: lado mayor, separación, fondo, esquinas, sombra, título, calidad y logo (ruta, posición, tamaño, opacidad). Si al aplicar un preset falta el fichero del PNG o del logo, se aplica el resto y se avisa.
- **Última configuración recordada** (P2): cada uno de los tres módulos arranca con los ajustes con los que se cerró la última vez, aunque no sean un preset. Un botón «Valores por defecto» en el mismo menú permite volver a los de fábrica.
- Todo se guarda en las preferencias de la app (globales, no en el `.caoba`).

- **Exportar e importar** (añadido en la confirmación): en la ventana de Ajustes de la app, una sección «Presets» con «Exportar…» (guarda todos los presets de los tres módulos en un fichero JSON) e «Importar…» (lee un fichero y añade sus presets; si un nombre ya existe, se sustituye). Sirve para llevarlos a otro Mac o compartirlos.

*Confirmación: «sí, en ajustes opciones para exportar e importar» (16-10-2026); incorporado. Plan aprobado: «adelante».*

### 2. Preguntas y respuestas

**P1. ¿Presets globales de la app o por carpeta?** R: globales.
**P2. ¿Solo presets con nombre o también recordar la última configuración de cada módulo?** R: 1, las dos cosas.

### 3. Fuentes analizadas
- Estado de `ProcessorView`, `WatermarkView` y `CollageView` (todo en `@State`, sin persistencia), `WatermarkOptions` (no era codificable), `SettingsView` (solo idioma y apariencia).

### 4. Decisiones
- **Ajustes como estructura** (`ProcessorSettings`, `WatermarkSettings`, `CollageSettings`, codificables): cada vista conserva sus `@State` y expone `settings` (calculado) y `apply(_:)`; así no se tocan los controles. Un `onChange(of: settings)` guarda la última configuración y `onAppear` la restaura, lo que también cubre el cambio de módulo (la vista se recrea).
- **`PresetStore`** (`@Observable`, hilo principal): presets por módulo y última configuración en `UserDefaults` como JSON (`caoba.presets.<módulo>`, `caoba.lastSettings.<módulo>`); `version` cambia con cada escritura para que el menú se refresque. `Bundle` con los tres módulos para exportar e importar; al importar, los nombres repetidos se sustituyen.
- **`PresetBar`** genérico: el nombre que muestra es el del preset cuyos ajustes **coinciden** con los actuales (si no coincide ninguno, «Sin preset»); «Actualizar» y «Eliminar» actúan sobre el último preset aplicado o guardado en la sesión. Guardar pide nombre con una alerta.
- Rutas de PNG y logo dentro del preset; si faltan al aplicar, se aplica el resto y se avisa bajo el título en rojo CAOBA.
- `CropPreset` del Procesador pasa a ser codificable; `WatermarkOptions` del motor también (todos sus campos ya lo eran).
- Ajustes de la app: sección «Presets» con recuento, «Exportar…» (JSON ordenado y legible) e «Importar…», con mensaje de resultado. Ganchos de prueba `processor.demo=1`, `presets.export=`, `presets.import=`.
- Probado: crear preset «Web 2048», reabrir la app y el Procesador arranca con él aplicado y marcado; exportar, borrar las preferencias e importar lo recupera.

### 5. Alternativas descartadas
- Reescribir las vistas para que tengan un único `@State` con la estructura: más limpio, pero obligaba a tocar todos los controles de tres módulos.
- Mostrar en el menú el nombre del último aplicado aunque los ajustes hayan cambiado: el usuario pidió que se vea claro cuando ya no coincide.

### 6. Pendiente de comprobar
Nada.

## 2026-10-16 — Transiciones en el Slideshow

### 1. La petición tal como se ha entendido
Transiciones entre fotos en el Slideshow, además del fundido cruzado actual:

- **Juego** (P1): fundido cruzado, fundido a negro, corte seco, deslizar (izquierda, derecha, arriba, abajo), zoom cruzado y barrido (izquierda, derecha). Más «Aleatorio», que elige una distinta en cada cambio, como en los efectos Ken Burns.
- **Por defecto y por foto**: en la pestaña Vídeo se elige la transición y la duración por defecto; en el inspector de cada foto (y de cada collage) se puede fijar otra transición y otra duración para la entrada de ese elemento. El actual interruptor «Fundido entre fotos (1 s)» se sustituye por el selector; «Corte seco» equivale a apagarlo.
- **Duración** (P2): global de 0,25 a 2 s, y por foto. «Corte seco» no tiene duración.
- **Collages** (P3): la transición elegida se aplica entre collages; la aparición de cada foto dentro de un collage sigue siendo un fundido suave.
- La transición se refiere a cómo **entra** cada elemento; la primera foto entra desde negro con su transición (o con corte). La sincronización con la música ya centra el cambio en la mitad de la transición y seguirá haciéndolo con la duración de cada una.
- Todo se guarda en el `.caoba` con el resto del proyecto; los proyectos antiguos siguen igual (fundido 1 s si tenían el interruptor activo, corte seco si no).

*Confirmación: «si» (16-10-2026). Plan aprobado: «adelante».*

### 2. Preguntas y respuestas

**P1. ¿Juego de transiciones: fundido cruzado, fundido a negro, corte seco, deslizar (4 direcciones), zoom cruzado y barrido (2 direcciones)?** R: «me vale».
**P2. ¿Duración de la transición ajustable global, o global y además por foto?** R: 2, global y por foto.
**P3. ¿La transición elegida solo entre collages (aparición de fotos con fundido suave) o también entre los pasos de un collage?** R: 1, solo entre collages.

### 3. Fuentes analizadas
- `VideoWriter.composeFrame` (un `CIDissolveTransition` fijo), `SlideshowTimeline` (transición uniforme), `SlideshowSpec`/`SlideshowPhoto`, `CollageSlideshow.makePhotos` (pasos de aparición como fotos), `RhythmPlanner`, `SlideshowDocument` (interruptor `transition`, `makePhotos`, preset) y los inspectores.

### 4. Decisiones
- **`TransitionKind`** en el motor con diez casos; `SlideshowPhoto` lleva transición y duración de entrada opcionales y `SlideshowSpec` las de por defecto; `resolvedTransition(for:)` las combina. El `transition: Bool` antiguo se mantiene como atajo (false = corte), así los tests y llamadas previas siguen valiendo.
- **Timeline por elemento**: `SlideshowTimeline(durations:transitions:)`; la foto i sigue visible mientras entra la i+1 durante la transición de la i+1; la duración total añade la de la última como antes. `entry(at:)` añade «desde negro» para la primera foto; `frame(at:)` conserva su forma.
- **`Transitions.compose`** con Core Image: disolución; fundido a negro en dos mitades con `CIColorMatrix` sobre negro; deslizar como empuje (la nueva empuja a la anterior) con aceleración suave; zoom cruzado = la que sale crece un 25 % mientras se disuelve; barrido = recorte progresivo de la nueva sobre la anterior.
- **Collages**: el primer paso (lienzo vacío) entra con la transición del collage; los pasos de aparición llevan siempre fundido de `min(1, reveal)` s, igual que antes.
- **Ritmo**: `plan(…entryTransitions:)`: el centro del cambio i→i+1 es la mitad de la transición del i+1.
- **App**: `TransitionChoice` (concreta o «Aleatorio») por defecto y por elemento (`itemTransitions`, `itemTransitionDurations` por nombre de foto, id de collage, «cover», «credits»); el aleatorio se resuelve al generar con el generador del sistema. Pestaña Vídeo: selector «Transición» y «Duración transición» (0,25–2 s, oculta con corte). `TransitionOverrideRow` compartido en los inspectores de foto, collage, portada y créditos. Preset con migración del interruptor antiguo (activo → fundido 1 s, apagado → corte); el encuadre Ken Burns usa la transición de la foto siguiente para su duración de segmento.
- Tests: timeline por elemento, resolución del spec, cada transición en 0 / 0,5 / 1 con comprobación de píxeles, ritmo con entrada por elemento y un vídeo real generado con deslizamiento comprobado fotograma a fotograma con `AVAssetImageGenerator`.

### 5. Alternativas descartadas
- Filtros de transición de Core Image (`CISwipeTransition`, `CIPageCurl`…): menos control del aspecto y algunos requieren máscaras; con transformaciones y disolución se cubren las diez con el mismo aspecto en todas las plataformas.
- Transición entre los pasos de un collage: descartada en P3.

### 6. Pendiente de comprobar
- Ver en un vídeo real largo si el zoom cruzado necesita más o menos crecimiento (25 %).

## 2026-10-16 — Actualización dentro de la app y firma Developer ID

### 1. La petición tal como se ha entendido
Actualización dentro de la app y preparación de la firma:

- **«Actualizar ahora»** en la banda de versión nueva (y en el enlace del pie): descarga el DMG de la release con progreso y cancelable, lo monta, sustituye la app donde está instalada, lo desmonta y relanza la app ya actualizada. Si la carpeta de la app no se puede escribir, o la app corre desde el propio DMG o desde la carpeta de compilación, se descarga el DMG, se abre y se indica que se arrastre a Aplicaciones (respaldo manual, P2).
- **Cuarentena**: como la firma sigue siendo ad hoc (P1), la app quita el atributo de cuarentena del DMG descargado y de la app copiada, para que la versión nueva abra sin el aviso de «no se puede comprobar el desarrollador». Al instalar a mano desde el navegador el aviso seguirá existiendo hasta que haya Developer ID.
- **Comprobación mínima** antes de instalar: el DMG monta, contiene `CAOBA.app`, su versión es la anunciada y la firma del paquete verifica (`codesign --verify`).
- **Script de release preparado para Developer ID**: si existen las variables `CAOBA_SIGN_IDENTITY` (y las de notarización, `CAOBA_NOTARY_PROFILE`), firma con ese certificado, notariza y grapa el DMG; si no, sigue en ad hoc como ahora. Documentado para el día que haya cuenta.
- Nada cambia para quien no pulse el botón: la banda y el enlace siguen igual.

*Confirmación: «si» (16-10-2026). Plan aprobado: «adelante, esta vez al finalizar genera release y publica».*

### 2. Preguntas y respuestas

**P1. ¿Hay cuenta de desarrollador de Apple con Developer ID?** R: 2, no de momento: actualización dentro de la app con firma ad hoc; Developer ID preparado en el script pero desactivado.
**P2. ¿Instalación automática (descargar, sustituir y relanzar) o semiautomática (abrir el DMG)?** R: 1, automática con respaldo manual.

### 3. Fuentes analizadas
- `VersionCheck` (solo leía la página de la release), `UpdateBanner`, `Tools/make-release.sh` (firma ad hoc) y la API de releases de GitHub (`assets[].browser_download_url`).

### 4. Decisiones
- `VersionCheck.Release` incluye la URL del DMG adjunto; `fetchLatest()` separado de la comparación de versiones.
- **`Updater`** (`@Observable`, hilo principal) con fases: descargando (progreso), comprobando, instalando, reiniciando, manual o error. Descarga con `URLSession` y delegado (la lectura byte a byte de `AsyncBytes` resultó demasiado lenta: un 15 % de 12 MB en 20 s), a un temporal al que se quita la cuarentena.
- Montaje con `hdiutil attach` en un punto propio, `-nobrowse`; se desmonta siempre al terminar (con `-force` por si queda algo abierto).
- Comprobación antes de instalar: existe `CAOBA.app`, `CFBundleShortVersionString` coincide con la versión anunciada y `codesign --verify --deep --strict` pasa.
- Sustitución segura: se copia la nueva junto a la actual con nombre oculto, se renombra la actual, se mueve la nueva a su sitio y se borra la antigua; si el movimiento falla, se restaura la antigua. Se quita la cuarentena a la copia.
- Solo se sustituye si la carpeta es escribible, la app no está en `/Volumes/` (DMG montado) ni en `DerivedData`/`build/`; si no, se abre el DMG descargado y se indica arrastrar a Aplicaciones.
- Relanzado con un `sh` que espera a que muera el proceso actual y hace `open -n` de la app.
- Banda: «Actualizar ahora» (o «Descargar» si la release no trae DMG), progreso con «Cancelar», mensajes de fase y, en error o modo manual, «Abrir en el navegador».
- Script: `CAOBA_SIGN_IDENTITY` firma con Developer ID (hardened runtime y timestamp); con `CAOBA_NOTARY_PROFILE` además notariza y grapa el DMG. Sin variables, ad hoc como hasta ahora.
- Ganchos de prueba: `update.force=1` (banda con la última release aunque no sea más nueva), `update.auto=1` (lanza la actualización) y `update.target=/ruta/CAOBA.app` (sustituye esa copia y no relanza). Probado sustituyendo una copia del build de desarrollo (arm64) por la release 3.0.3 (universal), sin cuarentena y con firma verificada, DMG desmontado.

### 5. Alternativas descartadas
- Sparkle: resuelve esto muy bien, pero añade un framework, un feed XML y claves EdDSA; con un solo DMG en GitHub, el instalador propio son 200 líneas.
- Sustituir la app en caliente sin pasos intermedios: si el movimiento fallara a medias, el usuario se quedaría sin app.

### 6. Pendiente de comprobar
- Cuando haya cuenta de desarrollador: crear el certificado Developer ID Application, el perfil de `notarytool` y probar una release firmada y notarizada de principio a fin.

## 2026-10-16 — Changelog y aviso de novedades tras actualizar

### 1. La petición tal como se ha entendido
- **`CHANGELOG.md`** en la raíz del repo, en español (P1), con una sección por versión («## 3.1.0 — 2026-10-16») y viñetas cortas en lenguaje de usuario. Se rellena en cada release (lo escribo yo al preparar cada versión y se revisa antes de publicar) y arranca con las versiones ya publicadas: 3.0.0, 3.0.1, 3.0.2, 3.0.3 y 3.1.0.
- **Notas de la release en GitHub**: el script toma la sección de la versión del changelog como cuerpo de la release, en lugar de las notas generadas; si no hay sección, se niega a publicar.
- **Aviso de novedades en la app**: el changelog va dentro de la app como recurso. Al arrancar, si la versión guardada como «última vista» existe y es menor que la actual, se abre una hoja «Novedades» con las secciones de todas las versiones entre esa y la actual (P2), y se guarda la actual. En una instalación nueva no sale nada: solo se guarda la versión. En el menú Ayuda, «Novedades de CAOBA» abre la misma hoja con todo el historial.
- La hoja no interfiere con la de donativo ni con la banda de versión: si coinciden en el mismo arranque, primero las novedades y el donativo espera al siguiente.

*Confirmación: «dale» (16-10-2026).*

### 2. Preguntas y respuestas

**P1. ¿Changelog solo en español o en español e inglés?** R: 1, solo en español.
**P2. ¿Solo tras actualizar (con las versiones saltadas) y en el menú Ayuda, o también en la primera instalación?** R: 1, solo tras actualizar y en el menú Ayuda.

### 3. Fuentes analizadas
- Historial de commits (para redactar las secciones de 3.0.0 a 3.1.0), `Tools/make-release.sh` (notas generadas por `gh`, que salían vacías), `project.yml` (recursos), arranque de la app (`CaobaApp.swift`).

### 4. Decisiones
- `CHANGELOG.md` en la raíz, formato fijo: `## versión — fecha` y viñetas `- …` con negritas Markdown; cualquier otra línea se ignora al parsear. Incluido en la app como recurso vía `project.yml`.
- `Changelog` (parser) y `WhatsNewSheet` (hoja con icono, título en Doto, secciones y viñetas con negritas). `AppState.checkWhatsNew()` compara `caoba.lastSeenVersion` con la versión actual y enseña las secciones intermedias; en instalación nueva solo guarda la versión. Si hay novedades, el donativo espera al siguiente arranque. «Novedades de CAOBA» en el menú Ayuda enseña todo.
- Script: cuerpo de la release = sección de la versión en el changelog (con `awk`); sin sección no publica. Las notas de la 3.1.0 ya publicada se han sustituido a mano por las del changelog.
- Gancho de prueba `demo.lastSeen=3.0.1`.

### 5. Alternativas descartadas
- Generar el changelog de los commits: los mensajes de commit hablan de código, no de lo que ve el usuario.
- Mostrar las novedades también en la primera instalación: descartado en P2.

### 6. Pendiente de comprobar
Nada. Recordatorio: en cada release, escribir la sección nueva del changelog antes de lanzar el script.

## 2026-10-16 — Landing: más explicación de cada módulo

### 1. La petición tal como se ha entendido
*(modo directo, sin análisis previo)* Ampliar en `index.html` la explicación de cada una de las nueve funcionalidades.

### 2. Preguntas y respuestas
Ninguna.

### 3. Fuentes analizadas
- `index.html` (tarjetas de módulos, solo Slideshow tenía viñetas) y el changelog de la 3.1.0 para no dejar fuera lo nuevo.

### 4. Decisiones
- Cada tarjeta lleva ahora una frase de presentación y entre dos y seis viñetas en español e inglés, con las novedades recientes (transiciones, ajuste al ritmo, composición por contenido, vista «Resultado», presets, deshacer del renombrador, estimación de vida útil…). Mismo CSS: la cuadrícula aguanta porque las tarjetas crecen en alto.

### 5. Alternativas descartadas
- Una página aparte por módulo: más texto que mantener y la landing es de un vistazo.

### 6. Pendiente de comprobar
- Las capturas de la landing son anteriores a la 3.1.0 (en Vídeo aún sale el interruptor de fundido); conviene repetirlas cuando se publique la próxima versión.

## 2026-10-16 — Landing: la historia de CAOBA con enlaces al estudio

### 1. La petición tal como se ha entendido
*(modo directo, sin análisis previo)* Inventar en `index.html` una historia de por qué se desarrolló la app, con muchas referencias y enlaces a los servicios de caobafoto.com.

### 2. Preguntas y respuestas
Ninguna.

### 3. Fuentes analizadas
- `sitemap.xml` de caobafoto.com (la portada bloquea a curl y a Chrome sin ventana con el reto de Cloudflare) y el título y la descripción de cada página de servicio: bodas, comuniones, colección Esencia (familias), colección Raíces (embarazo), colección Nido (recién nacidos en casa), seguimiento del primer año, mini colección Senda (cumpleaños), fotografía corporativa y de producto, inmuebles y alquiler vacacional, sesiones de Navidad, bonos regalo y contacto. Estudio en Biar, Alicante.

### 4. Decisiones
- Sección «La historia» entre el hero y los módulos, enlazada en la barra. Texto editorial a dos columnas en pantallas anchas, capitular en Doto rojo y enlaces subrayados en rojo CAOBA. Español e inglés con las reglas de idioma existentes (`<p lang-es>` / `<p lang-en>`).
- El relato (inventado, como se pidió) ata cada módulo a un servicio real: slideshow a bodas y recién nacidos, collages a las familias de Esencia, hojas de contacto al seguimiento del primer año, Reels a los cumpleaños de Senda, lotes, marca de agua, renombrado y metadatos a corporativa e inmuebles, QR a comuniones, Navidad y bonos regalo, y Shutter Count a las temporadas de bodas. Sin nombres de personas.

### 5. Alternativas descartadas
- Resumir los servicios en una lista: se pidió una historia; la lista ya está en caobafoto.com.

### 6. Pendiente de comprobar
- Que el estudio dé el visto bueno al relato antes de difundirlo.

## 2026-10-16 — Historia de la landing más genérica

### 1. La petición tal como se ha entendido
*(modo directo, sin análisis previo)* «No personalices tanto la historia»: casos que le podrían pasar a cualquier estudio de fotografía, manteniendo los enlaces a los servicios.

### 2. Preguntas y respuestas
Ninguna.

### 3. Fuentes analizadas
- La sección «La historia» recién escrita.

### 4. Decisiones
- Se quitan el lugar (Biar), la «noche de agosto», el «nosotros» y la invitación a visitar el estudio. El relato pasa a escenas en tercera persona que «le pasan a cualquier estudio», cada una enlazada al servicio correspondiente; el estudio aparece solo al final como autor («el que la hizo está en caobafoto.com»).

### 5. Alternativas descartadas
- Mantener la anécdota en primera persona: era justo lo que se pidió suavizar.

### 6. Pendiente de comprobar
Nada.

## 2026-10-16 — Texto sobre las fotos del Slideshow

### 1. La petición tal como se ha entendido
Texto en el vídeo del Slideshow, en dos piezas:

- **Título** (P1, las dos opciones): un título y un subtítulo opcional que pueden ir **como pantalla propia** (tarjeta con fondo de color, duración y transición propias, como la portada de imagen; opcionalmente repetida al final como cierre con su propio texto, p. ej. «Gracias») o **sobre la primera foto o la portada**, superpuestos durante unos segundos y desapareciendo con un fundido. Un selector elige el modo.
- **Pie por foto** (P2): un patrón global con texto libre y variables como las del renombrador (`{nombre}`, `{n}`, `{total}`, `{fecha}`, `{camara}`, `{objetivo}`…), que se aplica a todas las fotos; desde el inspector de cada foto se puede escribir un texto propio que sustituye al patrón, o dejarla sin pie. En modo Collages, el pie se aplica a cada collage con `{n}` y `{total}` de collages.
- **Estilo** (P3, dos estilos): uno para el título y el cierre, otro para los pies. Cada uno con fuente (Doto, la del sistema o cualquiera instalada), tamaño relativo al alto del vídeo, color, posición (nueve posiciones), y sombra o banda semitransparente de fondo para que se lea sobre cualquier foto.
- Los textos se dibujan en el render con Core Text y Core Image, sin ficheros intermedios; el timeline marca las tarjetas de título y cierre como el resto. Todo se guarda en el `.caoba`; los proyectos antiguos siguen igual (sin textos).

*Confirmación: «si» (16-10-2026). Plan aprobado: «adelante».*

### 2. Preguntas y respuestas

**P1. ¿Título como pantalla propia o sobre la primera foto?** R: las dos opciones.
**P2. ¿Pie por foto con patrón y variables más texto propio, o solo texto propio?** R: 1, patrón global con variables y texto propio por foto.
**P3. ¿Dos estilos (título y pies) o uno común?** R: 1, dos estilos.

### 3. Fuentes analizadas
- `VideoWriter` (marca de agua como capa compuesta), `Drawing.drawText` (Core Text en hojas de contacto), `Renamer.expand` y `gatherInfo` (variables y datos de cada foto), `OverlayPosition` (solo cinco posiciones), modelo del timeline y preset.

### 4. Decisiones
- **Motor**: `TextAnchor` (nueve posiciones), `TextBackdrop` (nada, sombra, banda), `TextStyle` (familia o sistema, negrita, tamaño en % del alto, color, posición, fondo) y `TextOverlay` (líneas, estilo, segundos y fundido de 0,6 s). `TextRenderer.layer` dibuja una capa transparente con Core Text (primera línea al tamaño pedido, las demás al 55 %, márgenes del 5 % y 6 %, recorte con puntos suspensivos; banda negra al 45 % con esquinas, o sombra); `TextRenderer.card` la tarjeta con fondo. La fuente se usa solo si la familia existe de verdad (Core Text daría otra a escondidas); si no, la del sistema.
- `SlideshowPhoto.caption` (pie fijo) y `.overlay` (título sobre la foto); `SlideshowSpec.captionStyle`. El escritor compone pie y título **dentro del fotograma de cada foto**, así las transiciones los arrastran; las capas se cachean por foto y se liberan con la foto.
- **App**: título con tres modos; en «pantalla propia» y el cierre se renderizan a JPEG temporal con `TextRenderer.card` y entran como fotos del vídeo (tarjetas «Título» y «Cierre» en el timeline con inspector propio: texto, fondo, duración y transición); en «sobre la primera foto» el título se adjunta como `overlay` al primer elemento. Pies: patrón global con `{nombre} {n} {total} {fecha} {camara} {objetivo}` (reutiliza `Renamer.expand` y añade `{total}` y `{fecha}` en dd/MM/yyyy) y por elemento «Patrón / Propio / Sin pie» (cadena vacía = sin pie). En Collages el pie va en todos los pasos del collage con `{n}` y `{total}` de collages.
- Dos estilos editables en «Portada y texto» (antes «Portada y marca»): fuente entre las instaladas más Doto, negrita, tamaño, color, posición y fondo. `CanvasBackground.fill/text` pasan a públicos para la tarjeta del timeline.
- Preset: sección `text` con todo; proyectos antiguos sin textos. Ganchos de prueba `text.demo=card|overlay` y `slideshow.generate=/ruta.mp4`.
- Tests: posiciones, banda, tarjeta, opacidad del título y un vídeo real con pie comprobado por fotogramas.
- Tras la primera prueba con BOOK (vídeo de collages): el título superpuesto caía solo en el primer paso del collage (el lienzo vacío, 0,5 s). `TextOverlay` gana `offset` y el título se reparte entre todos los pasos del primer collage con su desfase, hasta `titleOverlaySeconds` o lo que dure el collage. Y los pies con variables vacías dejaban separadores colgando («1 de 10 ·»): en collages `{nombre}` es el nombre de la plantilla y se recortan los separadores sueltos.

### 5. Alternativas descartadas
- Dibujar los textos como capa global por encima de las transiciones: el pie saltaría de golpe en lugar de deslizarse o fundirse con su foto.
- Usar `CIFilter` de texto (`CIAttributedTextImageGenerator`): no da control de truncado ni de banda; Core Text sí.

### 6. Pendiente de comprobar
- ~~Una vista previa en vivo del estilo~~ Hecha a continuación (petición del usuario).

## 2026-10-16 — Vista previa de los textos a la derecha

### 1. La petición tal como se ha entendido
*(modo directo, sin análisis previo)* «Necesitaría un previsualizador a la derecha para ir viendo cómo va a quedar»: en la pestaña «Portada y texto», un panel a la derecha que enseñe en vivo cómo quedan título, cierre y pie sobre el vídeo.

### 2. Preguntas y respuestas
Ninguna.

### 3. Fuentes analizadas
- `SlideshowView` (la pestaña iba en un `ScrollView` a toda la anchura), `TextRenderer`, `ThumbnailProvider`.

### 4. Decisiones
- `TextPreviewPanel` a la derecha (380 pt): controles a la izquierda en su scroll y a la derecha hasta tres previsualizaciones: título (pantalla propia renderizada con `TextRenderer.card`, o la primera foto con la capa del título encima), cierre y pie (primera foto con el pie real calculado con el patrón y los datos de esa foto). Se renderiza en segundo plano a 720 px de ancho con el motor de verdad, y se recalcula solo cuando cambia algo que afecte (una clave `Equatable` con todos los campos). Sin nada activo, un texto explica qué activar.
- `CGContext.rgba` del motor pasa a público para componer foto y capa.

### 5. Alternativas descartadas
- Botón «Ver muestra» que renderice un fotograma: el usuario quiere verlo mientras ajusta, no a demanda.

### 6. Pendiente de comprobar
Nada.

## 2026-10-16 — Selector de fuente usable

### 1. La petición tal como se ha entendido
*(modo directo, sin análisis previo)* El selector de fuente no servía para probar: el menú no enseñaba cada nombre con su tipografía, no se podía ir con las flechas viendo la vista previa y la única forma era pulsar el menú y elegir a ciegas.

### 2. Preguntas y respuestas
Ninguna.

### 3. Fuentes analizadas
- `TextStyleEditor` (un `Picker` de menú con ~250 familias) y `TextPreviewPanel`.

### 4. Decisiones
- `FontField`: el nombre de la fuente actual en su propia tipografía, con flechas a los lados para pasar a la anterior o la siguiente (cíclico) mientras la vista previa de la derecha se actualiza. Al pulsarlo, un popover (`FontListPopover`) con buscador y una lista en la que cada familia va con su tipografía; la lista toma el foco, las flechas ↑↓ cambian la selección (y la vista previa) e Intro cierra. «Sistema» es la primera entrada.
- La lista de familias (`NSFontManager` más Doto) se calcula una vez.

### 5. Alternativas descartadas
- `NSFontPanel` del sistema: elige fuente y tamaño a la vez y no se integra con el estilo propio; además no enseña la vista previa de la app.

### 6. Pendiente de comprobar
Nada.

## 2026-10-16 — Animaciones de los textos del vídeo

### 1. La petición tal como se ha entendido
Animación de entrada y salida para los textos del vídeo:

- **Juego** (P1): fundido, deslizar desde abajo, arriba, izquierda o derecha, zoom (crece desde pequeño), máquina de escribir (las letras una a una) y ninguna (de golpe); más «Aleatorio». La salida es la inversa de la entrada (el deslizamiento vuelve por donde vino; la máquina de escribir se borra letra a letra).
- **Dónde se elige**: en cada estilo de texto (título y pies) hay «Animación» y «Duración» (0,25–2 s). El cierre usa la del título.
- **Cuándo**: el pie entra al empezar su foto y sale justo antes de que empiece la transición a la siguiente, así el cambio queda limpio. El título superpuesto entra al empezar y sale al cumplir sus segundos (sustituye al fundido fijo de ahora). En la pantalla propia del título y en el cierre, el texto se anima sobre el fondo de color: entra cuando la tarjeta ya está en pantalla y sale antes de que la tarjeta se vaya.
- La vista previa de la derecha sigue mostrando el texto en su posición final (la animación se ve al generar).
- Se guarda en el `.caoba` con el estilo; los proyectos de hoy quedan con fundido para el título superpuesto y ninguna animación para los pies, que es como se comportan ahora.

*Confirmación: «adelante» (16-10-2026), tomado también como aprobación para hacerlo.*

### 2. Preguntas y respuestas

**P1. ¿Juego: fundido, deslizar (4 direcciones), zoom, máquina de escribir, ninguna, más aleatorio; duración 0,25–2 s por estilo?** R: sí.

### 3. Fuentes analizadas
- `TextRenderer` (capa estática), `VideoWriter` (composición del pie y del título con opacidad fija), `SlideshowDocument.applyText` (las tarjetas llevaban el texto horneado en la imagen).

### 4. Decisiones
- **`TextAnimation`** en el estilo (`animation`, `animationDuration`), con decodificación tolerante a estilos guardados sin esos campos. `TextPhase.at(t:total:animation:duration:)` da el punto de la animación: entrada en los primeros `duration` s, salida en los últimos, acortada a la mitad del total si no cabe.
- **`TextRenderer.render`** devuelve la capa con el rectángulo del bloque y el número de caracteres; con `visibleCharacters` dibuja solo un prefijo manteniendo la posición del bloque completo (así la máquina de escribir no baila). **`TextRenderer.animated`** desplaza (20 % del lienzo), escala sobre el centro del bloque (30 % → 100 %) o atenúa la capa según la animación y el progreso; la salida reutiliza la misma fase al revés.
- Escritor: el pie entra al empezar la foto y sale antes de `photo.duration` (justo antes de la transición al siguiente); el título superpuesto usa `TextOverlay.phase` con desfase (collages) y **retardo** (`delay`). La máquina de escribir se cachea por número de caracteres.
- **Tarjetas** de título y cierre: ahora el fondo es una imagen lisa y el texto va como texto superpuesto con retardo igual a la transición de entrada de la tarjeta y duración hasta el final de la tarjeta; así entra cuando la tarjeta ya está y sale antes de que se vaya.
- «Aleatorio» se resuelve al generar: una animación por tarjeta y por título, y para los pies una distinta por foto (`SlideshowPhoto.captionAnimation`).
- Editor de estilo: «Animación» y «Duración animación» (0,25–2 s). La vista previa de la derecha sigue en reposo.
- Gancho de prueba `text.animation=<tipo>` junto a `text.demo`.
- Tras la prueba con BOOK (collages): el pie volvía a animarse en cada paso de aparición del collage. `SlideshowPhoto.captionEntry/captionExit` y `TextPhase.at(entry:exit:)`: en los pasos de un collage el pie entra solo en el primero y sale solo en el último; con «Aleatorio», todos los pasos de un collage comparten la animación.

### 5. Alternativas descartadas
- Animación distinta para entrada y salida: dobla los controles; la inversa queda natural y es lo habitual.
- Hornear la animación en imágenes por fotograma: inviable en tiempo y memoria; se compone con Core Image al vuelo como las transiciones.

### 6. Pendiente de comprobar
- Ver si la máquina de escribir conviene que sea por palabras en títulos largos.

## 2026-10-16 — Entrada, tiempo mostrándose y salida de los textos por separado

### 1. La petición tal como se ha entendido
*(modo directo, sin análisis previo)* La animación del texto debe poder indicarse en varios tiempos (lo que tarda en entrar, lo que se muestra y lo que tarda en salir), y la salida ha de poder ser distinta de la entrada: que la máquina de escribir se quede escrita (sin salida) o se vaya difuminada.

### 2. Preguntas y respuestas
Ninguna.

### 3. Fuentes analizadas
- `TextStyle`, `TextPhase`, `VideoWriter` y `TextStyleEditor` tal como quedaron en la petición anterior.

### 4. Decisiones
- `TextStyle` gana `exitAnimation` (`mirror` = la inversa de la entrada, por defecto; `none` = el texto se queda; o cualquiera de las demás, incluida «Aleatorio») y `exitDuration`, y `holdSeconds` (`nil` = hasta el final de la foto o tarjeta). Decodificación tolerante: estilos guardados sin estos campos quedan como antes (salida inversa con la misma duración).
- `TextPhase.at(_:total:style:entry:exit:)` calcula entrada y salida con sus duraciones propias; si no caben en el total se acortan a partes iguales. `TextPhase.totalDuration(style:hold:)` = entrada + muestra + salida.
- Escritor: en la salida se usa `resolvedExit`; la máquina de escribir como salida borra letra a letra. El pie con «Unos segundos» se va antes de que acabe la foto; con «Toda la foto», al final como hasta ahora. El título superpuesto: «Segundos mostrándose» es el tiempo entre entrada y salida (antes era el total).
- Editor de estilo: filas «Entrada» (animación y segundos), «Mostrar» (solo en pies: toda la foto o unos segundos) y «Salida» (igual que la entrada, ninguna, fundido, hacia abajo/arriba/derecha/izquierda, zoom, máquina de escribir que se borra, aleatorio, y segundos).

### 5. Alternativas descartadas
- Un único tiempo para todo: era justo la limitación señalada.

### 6. Pendiente de comprobar
Nada.

## 2026-10-16 — Título y cierre empalmados con la foto contigua

### 1. La petición tal como se ha entendido
*(modo directo, sin análisis previo)* Que el título en pantalla propia se quede quieto mientras la tarjeta se funde con la primera foto (y salga después sobre ella), y que el cierre aparezca sobre la última foto y se mantenga mientras esta se funde a su pantalla de texto. Confirmado: «si».

### 2. Preguntas y respuestas
Ninguna (la propuesta iba en la respuesta a la pregunta del usuario).

### 3. Fuentes analizadas
- `applyText`, `textCard` y `TextOverlay` (desfase y retardo).

### 4. Decisiones
- Dos interruptores en «Portada y texto»: «Mantener el título quieto mientras la tarjeta se funde con la primera foto» (con «Segundos sobre la foto», que reutiliza los segundos mostrándose) y «Empezar el cierre sobre la última foto y mantenerlo al fundir a su pantalla» (con sus «Segundos sobre la foto»).
- Por dentro: el mismo texto va en la tarjeta y en la foto contigua, y en el empalme no hay animación (la tarjeta sin salida y la foto sin entrada, o la foto sin salida y la tarjeta sin entrada), así durante el fundido las dos capas tienen el texto en el mismo sitio y no se mueve. En collages, el texto se reparte por los pasos del primer o último collage con el desfase encadenado; el cierre calcula su retardo para empezar «segundos» antes del final del último elemento.
- Preset: `titleCarryOver`, `closingCarryOver`, `closingOverlaySeconds`. Gancho `text.carry=1`.
- Primera prueba: durante el fundido el texto de la tarjeta se veía atenuado, porque el texto superpuesto acababa justo donde acababa la foto y el elemento que se va sigue visible toda la transición. Un texto sin salida se alarga 5 s de margen (`carryOverExtra`), más que cualquier transición, así sigue nítido hasta que la tarjeta desaparece del todo. Comprobado fotograma a fotograma en los dos empalmes.

### 5. Alternativas descartadas
- Hacer que el texto sea una capa global fuera de las fotos: rompería que las transiciones arrastren el pie con su foto.

### 6. Pendiente de comprobar
Nada.

## 2026-10-16 — Tarjetas de texto en cualquier punto del timeline

### 1. La petición tal como se ha entendido
**Tarjetas de texto** como elemento del timeline del Slideshow, en sustitución del título y el cierre fijos (P1):

- Un botón «Añadir texto» (en la pestaña «Portada y texto» y en el menú contextual del timeline) crea una tarjeta **antes del elemento seleccionado** o al final; las tarjetas se reordenan arrastrando como las fotos y los collages, y se quitan desde su inspector o el menú contextual.
- Cada tarjeta tiene: texto y subtítulo; **fondo** (negro, blanco, gris, o **ninguno**: entonces no es pantalla propia sino texto superpuesto a la foto siguiente, lo que hoy es «sobre la primera foto»); duración; transición de entrada propia o por defecto; **estilo** propio partiendo del global de títulos (P2), con «Volver al estilo de títulos»; animaciones de entrada y salida con sus tiempos (del estilo); y los dos **empalmes**: «mantener el texto quieto mientras se funde con el elemento siguiente» (y segundos sobre él) y «empezar sobre el elemento anterior» (y segundos sobre él).
- Pestaña «Portada y texto»: el grupo «Título» pasa a «Textos», con la lista de tarjetas (texto, posición en el timeline, duración) y «Añadir texto»; el estilo de títulos se queda como estilo por defecto de las tarjetas nuevas. Los pies de foto no cambian.
- Inspector de la tarjeta (al seleccionarla en el timeline): todo lo anterior en un sitio, con el editor de estilo completo.
- La vista previa de la derecha enseña la tarjeta seleccionada (o la primera) y el pie.
- **Migración** de los proyectos guardados: el título en pantalla propia o sobre la primera foto se convierte en una tarjeta al principio (fondo de color o ninguno), y el cierre en una tarjeta al final, con sus empalmes y el estilo de títulos; nada se pierde.
- El pie de foto no se aplica a las tarjetas de texto. Las tarjetas cuentan en el timeline, en el ritmo (como duración fija) y en la duración total como cualquier elemento.

*Confirmación: «si» (16-10-2026). Plan aprobado: «dale».*

### 2. Preguntas y respuestas

**P1. ¿Sustituir título y cierre por tarjetas de texto normales (con migración) o añadir las tarjetas manteniendo los fijos?** R: 1, sustituir.
**P2. ¿Estilo por tarjeta partiendo del global, o un único estilo para todas?** R: 1, estilo por tarjeta partiendo del global de títulos.

### 3. Fuentes analizadas
- Todo lo de texto en `SlideshowDocument` (título y cierre fijos, `applyText`), `TimelineItem.Kind`, `TimelineSelection`, `ReorderModifier`, `ExtrasTab`, `TextCardInspector`, `TextPreviewPanel`, `SlideshowPreset.TextSection`.

### 4. Decisiones
- **`TextCard`** en el motor (codificable): texto, subtítulo, fondo opcional (`nil` = superpuesta al elemento siguiente), duración (con fondo, la de la tarjeta; sin fondo, segundos mostrándose), estilo propio opcional, empalmes `carryNext`/`carryPrevious` con sus segundos, y **ancla**: `start`, `end` o el id del elemento ante el que va. Las tarjetas cuyo ancla ya no existe van al final. Un timeline puede tener varias ante el mismo elemento (en el orden de la lista).
- `orderedKinds` intercala las tarjetas; `TimelineItem.Kind.text(TextCard)` y `TimelineSelection.text(UUID)`. Duración, borrado, ritmo (fijo) y pestaña contextual las tratan como cualquier elemento. Arrastrar una tarjeta sobre un elemento la coloca ante él; sobre otra tarjeta, delante de ella. Menú contextual: «Quitar texto» y «Añadir texto antes».
- **Generación**: `makePhotos` devuelve también el dueño (id de elemento) de cada foto, y en collages los pasos comparten dueño. `applyText(to:owners:)` localiza, para cada tarjeta, el rango de fotos del elemento siguiente y del anterior; con fondo emite la tarjeta (fondo liso y texto superpuesto con retardo) y aplica los empalmes sobre esos rangos; sin fondo pone el texto sobre el siguiente (o el anterior si es la última). Luego monta la lista final recorriendo el timeline. En la vista previa solo entran las tarjetas pegadas a algún elemento incluido.
- **Interfaz**: grupo «Textos» en «Portada y texto» con la lista (texto, instante, tipo, duración), «Editar», quitar, «Añadir texto…» (ante lo seleccionado o al final) y el estilo de títulos como estilo por defecto; `TextCardInspector` con contenido, fondo (incluido «Ninguno · sobre el siguiente»), duración o segundos, transición, empalmes y «Estilo propio» con editor completo y «Volver al estilo de títulos». Tarjeta del timeline con su fondo, o rayada con icono si es superpuesta. Vista previa de la tarjeta seleccionada (o la primera) sobre la foto que le sigue.
- **Migración**: al cargar un `.caoba` sin `cards`, el título fijo pasa a una tarjeta con ancla `start` (fondo o superpuesta según el modo, con su empalme) y el cierre a otra con ancla `end`; al guardar ya solo se escriben las tarjetas. `TitleMode` desaparece.
- Probado con BOOK: título al inicio con empalme, «Segunda parte» superpuesto ante el tercer collage (entra deslizando desde la derecha abajo a la derecha) y cierre con empalme; `.caoba` con las tres tarjetas. Restaurado el `.caoba` de BOOK tras la prueba.

### 5. Alternativas descartadas
- Mantener título y cierre fijos además de las tarjetas: descartado en P1.
- Guardar la posición como índice: se desordena al reordenar o quitar fotos; el ancla por id aguanta.

- Añadido a petición del usuario («faltaría la opción de crear el texto después»): «Añadir texto después» en la pestaña y en el menú contextual; se ancla al siguiente elemento que no sea tarjeta (o al final) y, tras otra tarjeta, se coloca justo detrás de ella (`moveTextCard(_:afterCard:)`).

### 6. Pendiente de comprobar
- Las tarjetas superpuestas ocupan 0 s en el timeline y se ven como una tira estrecha; valorar darles un ancho mínimo mayor o un marcador.

## 2026-10-17 — Sección de descarga de la landing

### 1. La petición tal como se ha entendido
*(modo directo, sin análisis previo)* En la parte inferior de `index.html`: el botón de descarga directo al DMG como el de arriba, ocultar el botón de GitHub, el botón de donativo igual que el de arriba, y en el tercer paso explicar el aviso de seguridad de macOS (sin certificado porque, al ser gratuita, no compensa pagar la licencia de desarrollador) y que la app es 100 % segura.

### 2. Preguntas y respuestas
Ninguna.

### 3. Fuentes analizadas
- `index.html` (sección de descarga y el script que consulta la última release).

### 4. Decisiones
- Los dos botones de descarga llevan la clase `download-link` y el script apunta todos al DMG de la última release (comprobado: ambos enlazan `CAOBA-3.2.0.dmg`). Sin release, quedan en la página de releases.
- Botón de GitHub quitado de la sección (sigue en la barra superior y en el pie). Botón de donativo amarillo con el mismo texto e icono que el del hero.
- Paso 3 reescrito en los dos idiomas: por qué sale el aviso (sin certificado de Apple; gratuita, no compensa la licencia) y por qué es segura (código público, sin cuentas, nada sale del Mac, solo consulta si hay versión nueva).

### 5. Alternativas descartadas
- Ninguna.

### 6. Pendiente de comprobar
Nada.

## 2026-10-17 — Landing: sección «Por qué CAOBA»

### 1. La petición tal como se ha entendido
*(modo directo, sin análisis previo)* La sección «Por qué nativa» no decía mucho; rediseñarla. Propuesta aceptada («vale»): «Por qué CAOBA» con cuatro razones en lenguaje de usuario y una nota final que conecta con la historia.

### 2. Preguntas y respuestas
Ninguna.

### 3. Fuentes analizadas
- La sección existente (hablaba de Core Image, VideoToolbox, ImageIO).

### 4. Decisiones
- Cuatro bloques con el mismo CSS: «0 € · Gratis. De verdad», «100 % · Tus fotos no salen de tu Mac», «↩ · Pensada para no perder nada» y «14 MB · Rápida y ligera», cada uno con una frase sobre lo que gana el usuario; sin nombres de frameworks. Nota final en cursiva: hecha por un estudio para su propio trabajo. Enlace de la barra: «Por qué CAOBA». El dato de tamaño pasa de 30 a 14 MB (el DMG real).

### 5. Alternativas descartadas
- Mantener los datos técnicos (GPU, frameworks): es lo que no decía nada al fotógrafo.

### 6. Pendiente de comprobar
Nada.


## 2026-10-17 — Slideshow: metadatos de CAOBA y URL en el vídeo exportado

### 1. La petición tal como se ha entendido
Confirmada por el usuario («sí») el 2026-10-17.

Todo MP4 que exporta el slideshow, tenga música o no, lleva estas etiquetas fijas:
- **Software/Encoder**: `CAOBA <versión>` (por ejemplo, `CAOBA 3.2.0`).
- **Comentario/Descripción**: «Creado con CAOBA — https://caobafoto.com» (o «Made with CAOBA — https://caobafoto.com» si la app está en inglés).
- **Fecha de creación**: el momento de la exportación.
- **Autor**: el nombre que el usuario ponga en un nuevo campo «Autor» de los Ajustes. Si lo deja vacío, el vídeo sale sin autor. Desaparece el autor fijo «CAOBA» que se escribía hasta ahora.

El slideshow no cambia: no hay casillas para quitar las etiquetas ni campos para editarlas.

En el módulo Metadatos, el campo «Artista» propone el autor de los Ajustes solo cuando la foto no trae uno; si la foto ya tiene artista, se muestra el suyo. Junto al campo hay un botón «Usar mi autor» que pone el de los Ajustes aunque la foto tenga otro (desactivado si el campo de Ajustes está vacío). Nada se escribe hasta pulsar «Escribir metadatos».

Queda fuera: el collage, la hoja de contactos y el resto de imágenes que genera CAOBA.

### 2. Preguntas y respuestas
- **¿Etiquetas fijas, desactivables o editables por el usuario?** → Fijas, sin cambios en la interfaz.
- **El campo «Autor» (hoy «CAOBA»): ¿quitarlo o mantenerlo?** → Ni una cosa ni otra: el autor se configura en un campo de los ajustes de la app.
- **Si el campo «Autor» de los ajustes está vacío, ¿qué se escribe?** → Nada: el vídeo sale sin autor. CAOBA sigue figurando como software y en el comentario.
- **¿El campo «Autor» de los ajustes se usa solo en el vídeo o en más sitios?** → En el vídeo del slideshow y, además, como valor que propone el módulo Metadatos para el campo «Artista».
- **En Metadatos, ¿cuándo se propone el autor de los ajustes?** → Solo si la foto no trae artista; si ya tiene uno, se muestra el suyo. Se escribe únicamente al pulsar «Escribir metadatos», como ahora.
- **¿En qué idioma va el comentario con la web?** → En el de la app: «Creado con CAOBA — https://caobafoto.com» o «Made with CAOBA — https://caobafoto.com».
- **¿Se añade también un botón «Usar mi autor» para forzarlo aunque la foto ya tenga artista?** (en la pregunta anterior era una opción excluyente; se retomó a petición del usuario) → Sí, las dos cosas: se propone si la foto no tiene artista y el botón lo fuerza. El botón se desactiva si el autor de los Ajustes está vacío.

### 3. Fuentes analizadas
- `CaobaCore/Slideshow/VideoWriter.swift`, `SlideshowRenderer.swift`, `SlideshowSpec.swift` y `Audio/AudioMuxer.swift` (CAOBA 3.2.0): solo `AudioMuxer` escribía un metadato, autor «CAOBA», así que los vídeos sin música salían sin etiquetas.
- `CaobaApp/Views/ContentView.swift` (`SettingsView`), `Model/Preferences.swift`, `Views/Modules/MetadataView.swift`, `Model/SlideshowDocument.swift`.
- `Tools/make-release.sh` y `CHANGELOG.md` para la release.
- Ficheros MP4 generados en las pruebas, revisados con el exiftool que va dentro de la app (`CaobaApp/Vendor/exiftool`).

### 4. Decisiones
- `VideoMetadata` (nuevo, en `SlideshowSpec.metadata`) monta las etiquetas, y la usan `VideoWriter` y `AudioMuxer`. Así todos los vídeos las llevan, tengan música o no.
- La app envía el texto del comentario ya traducido con `L(…)`, porque el motor no sabe en qué idioma está la app.
- **El campo «Software» (`CAOBA 3.3.0`) se quita del plan.** Probado con exiftool: en un `.mp4`, AVAssetWriter solo guarda las etiquetas 3GPP (`dscp`, `auth`, `perf`, `date`). Las de software se descartan en silencio en las cuatro variantes probadas: comunes (salen como `swre`, que nadie lee), iTunes (`©too`), datos de usuario de QuickTime (`©swr`) y `mdta`. Lo pedido se cumple igual, porque el nombre de CAOBA y la web van en la descripción.
- Se escriben los identificadores 3GPP directamente, no los «comunes», porque el artista común no llegaba al fichero. El autor va como `auth` y como `perf` (intérprete), que es lo que muchos reproductores muestran como artista.
- En Metadatos, el botón observa el autor con `@AppStorage`, para que se active nada más rellenarlo en Ajustes sin tener que reabrir el módulo.
- Versión 3.3.0 (función nueva → sube el número menor).

### 5. Alternativas descartadas
- Editar las etiquetas desde el slideshow o poder desactivarlas: el usuario prefirió etiquetas fijas.
- Mantener «CAOBA» como autor: CAOBA es la herramienta, no la autora de las fotos.
- Escribir el software con exiftool después de generar el vídeo: el motor dependería del exiftool de la app y habría que reescribir un fichero grande solo por una etiqueta.
- Exportar como `.mov` o `.m4v` para que entren las etiquetas de QuickTime/iTunes: cambia el tipo de fichero que el usuario espera y que admiten las redes.
- Llevar el autor también a collage y hoja de contactos: fuera del alcance pedido.

### 6. Pendiente de comprobar
- Qué enseña el Finder (Obtener información) con un vídeo exportado de verdad: Spotlight no indexa la carpeta temporal de las pruebas.
- Las redes sociales (YouTube, Instagram, WhatsApp) borran casi todas las etiquetas al subir el vídeo; solo se conservan en el fichero original.

## 2026-10-17 — Aviso de versión nueva: sin enlace en la barra lateral y banda en rojo

### 1. La petición tal como se ha entendido
Confirmada por el usuario («sí») el 2026-10-17.

Cuando hay una versión nueva:
- Desaparece de la barra lateral el enlace «Nueva versión X». El pie queda siempre igual: CAOBA, la versión, caobafoto.com y «Hacer donación».
- La banda de arriba pasa a tener fondo rojo sólido #D71921 (el color de acento), con el texto y los iconos en blanco. El botón «Actualizar ahora» o «Descargar» va en blanco con el texto en rojo. También cambian de color los estados de descarga, comprobación, instalación y error.
- La × oculta la banda solo mientras la app sigue abierta. Al volver a arrancar sale otra vez, hasta que se actualice. Ya no se recuerda la versión cerrada (`caoba.update.dismissedVersion` deja de usarse).

### 2. Preguntas y respuestas
- **Sin el enlace lateral, ¿qué pasa al cerrar la banda con la ×?** → Se oculta solo mientras la app sigue abierta; al volver a arrancar sale otra vez, hasta que se actualice.
- **¿Rojo sólido o suave?** → Sólido: fondo #D71921 (el color de acento), texto e iconos en blanco y el botón «Actualizar ahora» en blanco con el texto en rojo.

### 3. Fuentes analizadas
- `CaobaApp/Views/ContentView.swift` (pie de la barra lateral), `Model/AppState.swift` (`checkForUpdates`, `dismissUpdateBanner`), `Model/Preferences.swift`, `Views/Shared/DonationSheet.swift` (`UpdateBanner`), `Assets.xcassets/AccentColor` (#D71921), todo en CAOBA 3.3.0.

### 4. Decisiones
- La banda usa `Color.accentColor`, no un rojo escrito a mano: si algún día cambia el acento, la banda cambia con él.
- `BannerButtonStyle` (privado) para los botones de la banda: blanco con el texto en el color de acento. Se usa en «Actualizar ahora/Descargar», «Cancelar» y «Abrir en el navegador».
- La banda fuerza `colorScheme = .dark` para que los controles del sistema (spinner, barra de progreso) salgan claros sobre el rojo.
- Se quita `Preferences.updateDismissedVersionKey`. El valor que quede guardado en los Macs no molesta porque nadie lo lee.
- Comprobado con una captura (`--state demo.update=9.9.9 --screenshot`).
- Versión 3.3.1 (cambio pequeño de interfaz).

### 5. Alternativas descartadas
- Rojo suave (semitransparente con borde): destaca menos, y lo que se pedía era resaltar.
- Mantener la × «hasta la siguiente versión»: sin el enlace lateral, esa versión no se volvería a avisar nunca.
- Banda sin ×: demasiado insistente.

### 6. Pendiente de comprobar
- Cómo se ven en rojo los estados de descarga, instalación y error (solo se capturó el estado inicial).

## 2026-10-17 — Landing: la historia al final, después de la descarga

### 1. La petición tal como se ha entendido
Confirmada por el usuario («sí») el 2026-10-17.

En `index.html`, la sección «La historia» (`#historia`), con el mismo contenido, pasa de estar detrás del hero a ir la última, después de «Descarga» y antes del pie. En la barra de arriba, el enlace «Historia» pasa también al final: Módulos · Por qué CAOBA · Descarga · Historia.

### 2. Preguntas y respuestas
- **¿El enlace «Historia» del menú también va al final?** → Sí, para que el menú siga el orden de la página.

### 3. Fuentes analizadas
- `index.html`: el orden de las secciones, el `<nav>` y el CSS de `.story` (no depende de la posición de la sección).

### 4. Decisiones
- Se mueve el bloque entero tal cual, sin tocar el texto ni las clases. Comprobado con una captura de Chrome sin interfaz: la historia queda entre «Descarga» y el pie.
- El menú sigue el orden de la página.

### 5. Alternativas descartadas
- Dejar «Historia» la primera en el menú: el menú quedaría desordenado respecto a la página.

### 6. Pendiente de comprobar
Nada.

## 2026-10-17 — Pie de la barra lateral en una fila, recordar el último módulo y Shutter Count con CR3

### 1. La petición tal como se ha entendido
Confirmada por el usuario («sí») el 2026-10-17.

1. **Pie de la barra lateral.** La fila «CAOBA · vX» no cambia. Debajo, en una sola fila, «caobafoto.com» a la izquierda y el icono del café con «Donación» a la derecha. Los dos enlaces en el rojo de la app (#D71921, el color de acento) en lugar del azul de enlace.
2. **Recordar el último módulo.** Al abrir la app se entra en el último módulo de la barra lateral que se usó. La primera vez, el Procesador, como ahora. Las pestañas interiores no se recuerdan.
3. **Shutter Count con CR3 de Canon.** Se lee el contador que guardan los CR3 (en el fichero de prueba, una Canon EOS R6 Mark II con 11.768 disparos, igual que en la app de Electron). Además, el firmware sale bien (1.6.0) y los modelos que Canon guarda con nombre corto («EOS R6m2», «R5m2»…) encuentran su vida útil en la tabla (R6 Mark II → 400.000) en lugar de la estimación genérica.
4. Al terminar: versión 3.3.2, commit, push y release publicada.

### 2. Preguntas y respuestas
- **Además del contador, ¿se arreglan en el CR3 el firmware vacío y la vida útil «genérica» (la cámara se llama «EOS R6m2» y en la tabla figura «EOS R6 Mark II»)?** → Sí, los dos.
- **¿Qué es «la última sección»: solo el módulo de la barra lateral o también la pestaña interior del Slideshow?** → Solo el módulo.
- **Al terminar, ¿versión y release?** → Sí: 3.3.2, commit, push y release publicada en GitHub.

### 3. Fuentes analizadas
- `CaobaCore/ShutterCount/ShutterCountReader.swift` (CAOBA 3.3.1) y exiftool 13.59 (el que va en la app) sobre `R6V29159.CR3` (Canon EOS R6 Mark II, fichero local del usuario). Con `-fast2` no sale `ShutterCount`; sin esa opción o con `-fast` sale `[Track4] ShutterCount: 11768`.
- `CaobaApp/Model/AppState.swift` (`currentModule`), `Model/Preferences.swift`, `Views/ContentView.swift` (`sidebarFooter`).

### 4. Decisiones
- `-fast` en lugar de `-fast2`: lee las pistas CTMD de los CR3 y tarda lo mismo (0,12 s frente a 0,15 s sin ninguna opción).
- Firmware: se pide `CanonFirmwareVersion` y se quita el prefijo «Firmware Version».
- Nombres cortos de Canon (`…m2` → `… mark ii`) solo en `ShutterLife`. En pantalla se sigue mostrando el nombre que guarda la cámara. Al revisarlo se vio que antes «canon eos r6m2» caía en la coincidencia parcial con un resultado que dependía del orden del diccionario (R6 con 300.000 o R con 200.000); ahora coincide exactamente con «canon eos r6 mark ii» (400.000).
- Último módulo: `didSet` en `currentModule` sobre `caoba.lastModule`; no se guarda en modo captura. Comprobado: con `qr` guardado, la app arranca en Código QR.
- Pie: `HStack` con `Spacer`, botones `.plain` y `Color.accentColor`. Comprobado con captura.
- Prueba con el CR3 real en un test temporal que se borró después (fichero real del usuario, no se añade al repositorio): 11.768 disparos, firmware 1.6.0, 400.000 de vida útil y 2,94 % usado.

### 5. Alternativas descartadas
- Quitar `-fast` del todo: no aporta nada frente a `-fast` con estos ficheros y lee más.
- Recordar también la pestaña interior del Slideshow: el usuario prefirió solo el módulo.
- Añadir «canon eos r6m2» como clave más en la tabla: habría que duplicar cada modelo; la conversión cubre todos los «mN».

### 6. Pendiente de comprobar
- El texto de la pantalla vacía de Shutter Count dice que Canon «en la mayoría de modelos» no guarda el contador; con los CR3 sí lo guarda. Se deja como está (fuera de esta petición), avisado al usuario.

## 2026-10-17 — Shutter Count: texto sobre Canon

### 1. La petición tal como se ha entendido
Confirmada por el usuario («sí, con release y publica») el 2026-10-17.

La frase sobre Canon («Canon, en la mayoría de modelos, no») cambia a «Canon, en los RAW CR3 (los JPG y los CR2 antiguos no lo traen)», en español y en inglés, en dos sitios: la pantalla vacía de Shutter Count de la app y la tarjeta de Shutter Count de la landing (`index.html`).

### 2. Preguntas y respuestas
- **¿Qué texto se pone para Canon y dónde?** → «Nikon, Sony y Pentax lo guardan; Canon, en los RAW CR3 (los JPG y los CR2 antiguos no lo traen).» En la app y en la landing.
- **¿Release o solo commit y push?** → Release 3.3.3 y publicar.

### 3. Fuentes analizadas
- `CaobaApp/Views/Modules/ShutterCountView.swift`, `Localizable.xcstrings` e `index.html` (tarjeta de Shutter Count).
- JPG de Canon EOS 60D y 5D Mark II en el Mac del usuario: ninguno trae contador con exiftool.

### 4. Decisiones
- En el `.xcstrings`, la clave es el texto en español: se sustituye la entrada (clave y traducción) en lugar de añadir una nueva y dejar la vieja huérfana.
- Versión 3.3.3.

### 5. Alternativas descartadas
- Texto corto sin mencionar los JPG: no explica por qué un JPG de Canon sale sin contador.

### 6. Pendiente de comprobar
- Si los JPG de la serie R de Canon traen contador (solo se comprobaron JPG de réflex antiguas).

## 2026-10-17 — Ajustes descolocados desde la 3.3.0

### 1. La petición tal como se ha entendido
*(sin preguntas: arreglo de un fallo)* El usuario pregunta qué le ha pasado a la ventana de Ajustes: filas desplazadas a la derecha, menús cortados y un campo de texto diminuto. Se le explicó la causa y el arreglo, y lo aprobó con release («sí, con release y publica»).

### 2. Preguntas y respuestas
Ninguna.

### 3. Fuentes analizadas
- `CaobaApp/Views/ContentView.swift` (`SettingsView`, cambiado en la 3.3.0) y `Views/Shared/Theme.swift` (`LabeledRow`).

### 4. Decisiones
- Causa: dentro de un `Form` de macOS, el título de un `TextField` se va a la columna de etiquetas. «Tu nombre o el de tu estudio» ensanchó esa columna y desplazó todas las filas. Arreglo: `TextField("", text:, prompt:)` + `.labelsHidden()` y ancho fijo de 220.
- Las notas de Autor y Presets llevan `.fixedSize(horizontal: false, vertical: true)` para que bajen de línea en vez de cortarse con «…».
- Nueva opción de captura `--state demo.settings=1`. En macOS 14, `showSettingsWindow:` no hace nada, así que se pulsa el elemento con atajo «,» del menú de la app. Se comprobó antes (reproduce el fallo) y después del arreglo.
- Versión 3.3.4.

### 5. Alternativas descartadas
- Sustituir el `Form` por un `VStack`: el arreglo es de una línea y el `Form` funciona bien con controles sin etiqueta.

### 6. Pendiente de comprobar
Nada.

## 2026-10-17 — El fondo «Negro» no es negro del todo

### 1. La petición tal como se ha entendido
En las tarjetas de texto del timeline, al elegir el fondo «Negro» el frame sale gris muy oscuro en lugar de negro. La causa es que `CanvasBackground.black` vale RGB 30/30/30 (#1E1E1E). Se quiere que «Negro» sea negro puro (0,0,0) en **todos** los sitios que lo usan: tarjetas de texto y fondo del pase, Collage y Contact Sheet. El color del texto por defecto sobre negro y el del borde no cambian.
Confirmada por el usuario («sí, confirmado»).

### 2. Preguntas y respuestas
- **¿Dónde debe pasar a ser negro puro: en todos, solo en el pase o solo en las tarjetas de texto?** → En todos.

### 3. Fuentes analizadas
- `CaobaCore/Sources/CaobaCore/Drawing/Drawing.swift` (`CanvasBackground.fill`).
- Usos de `.fill`: `TextOverlay.swift` (`TextRenderer.card`), `SlideshowDocument.swift` (`renderCardBackground`), `TextPreviewPanel.swift`, `SlideshowTimelineView.swift`, `CollageRenderer.swift`, `ContactSheetRenderer.swift`.

### 4. Decisiones
- Plan aprobado; release y publicación aprobadas («sí, con release y publica»).
- `CanvasBackground.black.fill` pasa de RGB 30/30/30 a 0,0,0. El color del texto por defecto sobre negro y el del borde no cambian.
- Test nuevo en `TextOverlayTests` («El fondo «Negro» es negro puro»): el color y la esquina de una tarjeta dibujada valen 0,0,0. Pasan los 127 tests del motor.
- Comprobado en la app: vídeo generado con una tarjeta negra al principio; a los 2 s, el fondo de la tarjeta da 0,0,0.
- Versión 3.3.5.

### 5. Alternativas descartadas
- Negro puro solo en el pase o solo en las tarjetas: descartado por el usuario; mejor que «Negro» signifique lo mismo en toda la app.
- Oscurecer solo la previsualización: el gris salía también en el vídeo exportado, así que el fallo estaba en el color, no en la vista.

### 6. Pendiente de comprobar
- Con `--folder` en una carpeta nueva, `--state text.demo=card` no deja las tarjetas en el timeline: al cargar la carpeta se aplica el preset (o los valores por defecto) y las borra. Para comprobar el arreglo se metió la tarjeta a mano en el `.caoba` de la carpeta de prueba.

## 2026-10-17 — Sin nombres de ficheros temporales en el progreso del vídeo

### 1. La petición tal como se ha entendido
Mientras se codifica el vídeo del Slideshow, el mensaje de progreso enseña bajo el porcentaje el nombre del fichero del elemento en curso. En los collages y en las tarjetas de texto con fondo, ese fichero es una imagen temporal (`page007_frame03.jpg` o un identificador largo), y no le dice nada a quien usa la app. En esos casos tiene que salir una descripción legible: «Collage 7 · <nombre de la plantilla>», el mismo nombre que enseña el timeline, y «Texto · <primera línea de la tarjeta>». Las fotos normales, la portada y los créditos siguen mostrando su nombre de fichero, que sí es del usuario.
Confirmada por el usuario («así»).

### 2. Preguntas y respuestas
- **Al codificar un collage o una tarjeta de texto, ¿qué sale bajo el porcentaje: una descripción legible, nada, o nada en ningún caso (tampoco en fotos)?** → Descripción legible.

### 3. Fuentes analizadas
- `CaobaCore/Sources/CaobaCore/Slideshow/VideoWriter.swift` (progreso con `url.lastPathComponent`).
- `CaobaCore/Sources/CaobaCore/Slideshow/CollageSlideshow.swift` (`page%03d_frame%02d.jpg`).
- `CaobaApp/Sources/Model/SlideshowDocument.swift` (`textCardPhoto`, `renderCardBackground`, `launch`).
- `CaobaApp/Sources/Views/Shared/ProgressSheet.swift` y `SlideshowTimelineView.swift` (etiquetas del timeline).

### 4. Decisiones
- Plan aprobado («si»), con release y publicación como la 3.3.5.
- `SlideshowPhoto.label` (opcional) y `displayName` (`label` o el nombre del fichero) en el motor; `VideoWriter` usa `displayName` en el progreso de codificación. Así el motor no tiene que saber qué ficheros son temporales: lo decide quien monta el vídeo.
- La app pone la etiqueta en `textCardPhoto` («Texto · <primera línea>», o «Texto» si no hay texto) y en cada paso de collage («Collage n · <plantilla>», el nombre que enseña el timeline). Cadenas nuevas en `Localizable.xcstrings` con su versión en inglés.
- Test nuevo en `SlideshowRenderTests`: el progreso enseña la etiqueta o, sin ella, el nombre del fichero. Pasan los 128 tests del motor.
- Comprobado en la app con un `print` temporal en `JobRunner` (ya quitado), con dos collages y una tarjeta: salen «Collage 1 · Single 16:9», «Collage 2 · Single centrado 16:9» y «Texto · Alex & Sofi».
- Versión 3.3.6.

### 5. Alternativas descartadas
- Detectar en el motor si la URL está en la carpeta temporal y ocultarla: no da un texto legible y ata el motor a dónde guarda la app sus temporales.
- No enseñar nada en collages y tarjetas, o quitar la línea también en las fotos: descartadas por el usuario; se pierde la pista de por dónde va el vídeo.

### 6. Pendiente de comprobar
- La hoja de progreso no sale en las capturas de `--screenshot` (es una ventana aparte); por eso se comprobó con el `print`.

## 2026-10-17 — Agrupar formularios y listas de fotos

### 1. La petición tal como se ha entendido
En varias pantallas los controles y las listas de fotos van sueltos por la ventana y parece todo desperdigado. Se quiere un único estilo de bloque en toda la app: **fondo tenue + borde fino de 1 px con esquinas redondeadas**, aplicado a:
- Los grupos de opciones que ya existen (`OptionGroup`: Operaciones, Salida, Patrón, Textos…), que hoy solo tienen un fondo casi invisible.
- La lista de fotos con su cabecera («3 de 3», Orden, Orientación), en todos los módulos que la usan.
- La pestaña Fotos/Collages del Slideshow (fila Modo, botones Componer/Añadir/Ajustar foco/Vaciar y la lista).
- La ficha de la foto en Metadatos (miniatura y datos EXIF).
- La barra de carpeta de arriba, la de destino/acciones de abajo y el panel del Timeline, que ya tienen fondo y ganan el borde.

Los bloques nuevos (lista, ficha) van sin título de cabecera. No cambia ningún comportamiento, solo el aspecto.
Confirmada por el usuario («si»).

### 2. Preguntas y respuestas
- **¿Hasta dónde llega la agrupación: toda la app, solo el Slideshow o solo las listas de fotos?** → Toda la app: la lista de fotos en todos los módulos, la pestaña Fotos/Collages del Slideshow y la ficha de Metadatos.
- **¿Qué aspecto tienen los grupos: fondo tenue + borde fino, solo el fondo actual o solo borde?** → Fondo tenue + borde fino de 1 px con esquinas redondeadas, también en los grupos de opciones que ya existen.
- **¿Los grupos nuevos (lista de fotos, ficha de Metadatos) llevan título de cabecera?** → Sin título: la lista ya tiene su cabecera y la ficha el nombre de la foto.
- **¿La barra de carpeta, la de destino/acciones y el panel del Timeline llevan también el borde?** → Sí, a juego.

### 3. Fuentes analizadas
- `CaobaApp/Sources/Views/Shared/Theme.swift` (`OptionGroup`), `FileListView.swift`, `SourceFolderBar.swift`, `DestinationBar.swift`.
- `CaobaApp/Sources/Views/Modules/Slideshow/SlideshowView.swift` (pestaña Fotos/Collages, `SlideshowActionBar`), `SlideshowTimelineView.swift`, `MetadataView.swift`, `RenamerView.swift`.
- Capturas de todos los módulos antes del cambio (`--screenshot`).

### 4. Decisiones
- Plan aprobado («dale»), incluida la tabla de vista previa del Renombrador.
- Un solo modificador `.caobaPanel()` en `Theme.swift` (fondo `controlBackgroundColor`, borde `separatorColor` de 1 px, radio 8). Los colores del sistema se adaptan solos a claro y oscuro, sin mantener dos juegos. `OptionGroup` deja el `GroupBox` y usa el panel con el título encima, así cambian de golpe todos los grupos de opciones.
- `FileListView` va en su propio bloque y quita el fondo de la `List` (`scrollContentBackground(.hidden)`) para no dejar un recuadro dentro de otro. Con `framed: false` va sin bloque: lo usa la pestaña Fotos/Collages del Slideshow, que es un solo bloque.
- Ficha de Metadatos (miniatura, EXIF y mapa), tabla de vista previa y barra «Deshacer» del Renombrador, barras de carpeta y destino, barra de acciones del Slideshow y Timeline: todos con `.caobaPanel()`.
- Fuera del plan, por coherencia: la barra «Elige o arrastra una foto» de Shutter Count, que es la misma pieza que la de carpeta. Las dos usan ahora `.caobaDropPanel(isTargeted:)` (al arrastrar: fondo rojo tenue y borde rojo de 2 px), así ese resaltado no está repetido.
- Comprobado con capturas de los 9 módulos en oscuro y en claro (`-caoba.appearance light|dark` al arrancar, sin tocar las preferencias de la app instalada).
- Versión 3.4.0: cambio visual en toda la app.
- Cuenta de GitHub: el usuario pidió que figure su cuenta personal y no quede rastro de la de EDISA. Revisado: los 52 commits (autor y committer) son de `marcosesperon@gmail.com`, las 14 releases las publicó `marcosesperon` y es el único contribuidor; no hubo que reescribir nada.

### 5. Alternativas descartadas
- Mantener `GroupBox` y añadirle el borde con un `GroupBoxStyle`: el fondo y el relleno del `GroupBox` de macOS no se controlan bien y los bloques que no son `GroupBox` (lista, barras) no casarían al píxel. Un modificador propio sirve para todo.
- Dejar la lista de fotos con su bloque dentro del bloque de la pestaña del Slideshow: un bloque dentro de otro recarga la vista.
- Solo el Slideshow o solo las listas: descartado por el usuario.

### 6. Pendiente de comprobar
- Riesgo de que se cuele la cuenta de EDISA en el futuro: el email global de git es el de EDISA (este repo usa el personal en local) y `gh` tiene las dos cuentas iniciadas; el script de release publica con la activa.

## 2026-10-17 — La release solo se publica con la cuenta personal

### 1. La petición tal como se ha entendido
*(sin preguntas: propuesta concreta aceptada)* Al revisar la cuenta de GitHub en la petición anterior quedaron dos riesgos: el email global de git es el de EDISA y `gh` tiene también la cuenta de EDISA iniciada. Se propuso que `Tools/make-release.sh --publish` compruebe antes de nada que el email de git del repo es `marcosesperon@gmail.com` y que la cuenta activa de `gh` es `marcosesperon`, y que pare si no. El usuario lo aceptó («si»).

### 2. Preguntas y respuestas
Ninguna.

### 3. Fuentes analizadas
- `Tools/make-release.sh` (ASCII, LF).

### 4. Decisiones
- La comprobación solo corre con `--publish` (compilar el DMG en local no publica nada) y va antes de los tests y la compilación, para fallar rápido.
- Si `gh` falla (sin sesión o token caducado), la cuenta se da por vacía y la release para igual.
- Probado con una copia del script cortada tras la comprobación: pasa con la configuración actual, para con el email de EDISA (forzado con `GIT_CONFIG_*`) y con `gh` sin sesión válida (`GH_TOKEN` inválido), y sin `--publish` no comprueba nada.
- Sin versión nueva: la app no cambia.

### 5. Alternativas descartadas
- Cambiar el email global de git o cerrar la sesión de EDISA en `gh`: afecta al trabajo de EDISA en otros repos.
- Un hook de git que valide el email en cada commit: el email ya está fijado en el repo; el riesgo real es la release con `gh`, y esto lo cubre sin añadir piezas.

### 6. Pendiente de comprobar
Nada.

## 2026-10-18 — Reorganizar los inspectores de Collage y Foto del Slideshow

### 1. La petición tal como se ha entendido
El inspector del collage seleccionado en el Slideshow tiene los controles apretados en una fila de arriba y en filas sueltas, con el collage pegado a la izquierda y mucho hueco vacío. El de Foto tiene el mismo problema. Se reorganizan los dos con el mismo esquema, para aprovechar el espacio y que se entienda qué hace cada control:
- **Cabecera:** nombre (plantilla o fichero) y, a la derecha, las acciones. Collage: Encuadre/Resultado, Centrar, Cambiar y Quitar. Foto: Ampliar.
- **Izquierda, a todo lo que dé:** la vista. Collage: encuadre o resultado, con la ayuda «arrastra cada foto para encuadrarla» debajo. Foto: los paneles de inicio y fin del Ken Burns.
- **Derecha, columna de ancho fijo con grupos con título** (el estilo de bloque de la 3.4.0):
  - Collage: **Tiempo** (Mantener, con su vuelta al valor global), **Transición** (tipo y duración, con su vuelta al valor global) y **Pie** (Patrón/Propio/Sin pie y, si es propio, el campo debajo).
  - Foto: **Efecto**, **Tiempo** (Duración), **Transición**, **Pie** y **Encuadre**, con los controles del Ken Burns que hoy van en una columna propia (Rellenar/Entera, Enfocar caras, Inicio → Fin, Intercambiar, Restablecer, Retardo). Así queda una sola columna de ajustes.
- **«Cambiar» del collage:** las plantillas salen en un popover del botón, que se cierra al elegir una.

No cambia lo que hace ningún control, solo dónde está. La hoja de encuadre ampliado de Foto y los demás inspectores (Texto, Portada/Créditos, Pista) se quedan como están.
Confirmada por el usuario («si»).

### 2. Preguntas y respuestas
- **¿Qué inspectores se reorganizan: Collage y Foto, solo Collage o todos?** → Collage y Foto, con el mismo esquema.
- **¿Qué distribución: vista + columna de ajustes a la derecha, o ajustes arriba y vista debajo?** → Vista grande a la izquierda y columna fija a la derecha con los ajustes en grupos con título.
- **Al pulsar «Cambiar», ¿dónde salen las plantillas: popover del botón, en lugar de los ajustes o en un grupo fijo de la columna?** → Popover del botón, que se cierra al elegir.

### 3. Fuentes analizadas
- `CaobaApp/Sources/Views/Modules/Slideshow/SlideshowInspector.swift` (`CollageInspector`, `PhotoInspector`, `TransitionOverrideRow`, `CaptionOverrideRow`), `KenBurnsFramingView.swift`, `SlideshowView.swift`.
- `CaobaApp/Sources/Views/Shared/Theme.swift` y `TemplateViews.swift`.
- `CaobaCore/Sources/CaobaCore/Slideshow/CollageSlideshow.swift` (qué significa «Mantener»: segundos extra con el collage completo).

### 4. Decisiones
- Plan aprobado («dale»), con release y publicación (versión 3.4.1).
- `InspectorColumn` (300 puntos, con desplazamiento) para la columna de los dos inspectores, y `StackedSlider` (etiqueta arriba) porque en 300 puntos la fila de `LabeledSlider` (etiqueta de 130) deja el deslizador en nada.
- `TransitionOverrideRow` y `CaptionOverrideRow` con `stacked`: misma lógica, solo cambia la disposición; Texto y Portada/Créditos siguen en horizontal.
- `KenBurnsFramingView` con huecos `leading`/`trailing`: el estado del Ken Burns (reproducción, detección de caras) sigue en la vista y no hace falta partirla. La hoja ampliada usa el inicializador sin huecos y queda igual.
- **Cambio sobre lo confirmado:** en Foto, el grupo Encuadre va justo después de Efecto (no al final). En la primera captura quedaba abajo del todo, casi fuera de la vista, y es lo que se toca junto con los paneles de inicio y fin. Tiempo, Transición y Pie van después.
- El selector de transición va alineado a la izquierda en su bloque (centrado quedaba raro).
- Nueva opción de prueba `--state slideshow.select=collage|photo` para capturar los inspectores. Comprobado en oscuro y claro a 1440×900 y en oscuro a 1100×720: nada se corta; con la ventana pequeña la columna se desplaza.
- Versión 3.4.1.

### 5. Alternativas descartadas
- Ajustes arriba en franja y vista debajo: descartado por el usuario; la vista pierde alto.
- Plantillas en lugar de los ajustes o en un grupo fijo: descartado por el usuario; el popover no quita sitio.
- Controles del Ken Burns debajo de los paneles, a la izquierda: con la ventana pequeña los paneles se quedaban diminutos.
- Partir `KenBurnsFramingView` en dos vistas (paneles y controles): habría que sacar su estado a otro sitio; los huecos lo resuelven sin moverlo.

### 6. Pendiente de comprobar
- El popover de plantillas no sale en las capturas (es una ventana aparte); se comprobó que compila y usa el mismo `TemplatePicker`, pero no se vio en pantalla.

## 2026-10-19 — Slideshow › Portada y texto: orden de secciones y fuera la lista de textos

### 1. La petición tal como se ha entendido
En la pestaña «Portada y texto» del Slideshow:
- **Orden nuevo de los bloques:** Portada y créditos, Marca de agua, Estilo de títulos y Pies de foto.
- **Fuera la sección «Textos»:** su lista de tarjetas (con Editar y quitar) y los botones «Añadir texto antes/después». Las tarjetas se gestionan pulsándolas en el timeline.
- **Se queda el estilo de títulos** como bloque propio, «Estilo de títulos». Sigue siendo el estilo por defecto de las tarjetas que no tienen uno propio, y funciona igual que ahora.
- **Botón nuevo «Añadir texto»** en el Timeline, junto a «Añadir pista». Pone la tarjeta tras el elemento seleccionado, o al final si no hay selección, y la deja seleccionada para editarla en su inspector, como hacía el botón de la sección. El clic derecho del timeline sigue igual.

La vista previa de la derecha de la pestaña se queda como está.
Confirmada por el usuario («si»).

### 2. Preguntas y respuestas
- **¿Qué se hace con el «Estilo de títulos» (estilo por defecto de las tarjetas), que hoy solo se edita en la sección Textos: bloque propio en la pestaña, al inspector de la tarjeta o quitarlo?** → Bloque propio «Estilo de títulos» en la pestaña, como «Pies de foto» tiene el suyo.
- **Sin la sección, «Añadir texto» solo quedaría en el clic derecho del timeline: ¿botón a la vista o solo el clic derecho?** → Botón «Añadir texto» en el Timeline, junto a «Añadir pista», tras el elemento seleccionado o al final si no hay selección. El clic derecho sigue igual.

### 3. Fuentes analizadas
- `CaobaApp/Sources/Views/Modules/Slideshow/SlideshowInspector.swift` (`ExtrasTab`, `TextStyleEditor`, `TextCardInspector`).
- `SlideshowTimelineView.swift` (botón «Añadir pista» y menú contextual con «Añadir texto antes/después»).
- `CaobaApp/Sources/Model/SlideshowDocument.swift` (`addTextCard(after:)`: coloca la tarjeta y la deja seleccionada).

### 4. Decisiones
- Plan aprobado («dale»), con release y publicación (versión 3.4.2).
- `ExtrasTab` queda en Portada y créditos → Marca de agua → Estilo de títulos → Pies de foto. Fuera la sección Textos (lista, Editar/quitar y los dos botones de añadir).
- El estilo de títulos va en su bloque con una línea que explica que es el de las tarjetas sin estilo propio. `TextStyleEditor` pasa a tener el título opcional (`nil` = sin subtítulo), porque dentro de un bloque con título sobraba; el inspector de la tarjeta, que le pasaba `""`, deja de dejar una línea vacía.
- «Añadir texto» bajo el Timeline llama a `addTextCard(after: true)`, la misma función que el clic derecho «Añadir texto después», así que no hay lógica nueva. Se desactiva con el timeline vacío.
- Cadenas nuevas en `Localizable.xcstrings` con su versión en inglés.
- Comprobado: capturas de la pestaña en oscuro y claro; y, con un gancho temporal (ya quitado) que selecciona la segunda foto y hace lo mismo que el botón, la tarjeta queda entre la foto 2 y la 3 y se abre su inspector.
- Versión 3.4.2.

### 5. Alternativas descartadas
- Llevar el estilo de títulos al inspector de cada tarjeta: editar algo que afecta a todas desde una sola tarjeta confunde; descartado por el usuario.
- Quitar el estilo común: cambia el funcionamiento (cada tarjeta con el suyo), no solo la pantalla; descartado por el usuario.
- Dejar «Añadir texto» solo en el clic derecho: cuesta de descubrir; descartado por el usuario.

### 6. Pendiente de comprobar
Nada.

## 2026-10-19 — Desplegables desalineados

### 1. La petición tal como se ha entendido
*(sin preguntas: arreglo de un fallo)* El usuario pregunta por qué hay campos sin alinear (Transición en Vídeo; Posición, Entrada y Salida en los estilos de títulos y pies). Se le explicó la causa y el arreglo, y lo aprobó con release («si»).

### 2. Preguntas y respuestas
Ninguna.

### 3. Fuentes analizadas
- `CaobaApp/Sources/Views/Modules/Slideshow/SlideshowInspector.swift` (`VideoTab`, `TextStyleEditor`, `TextCardInspector`, `TransitionOverrideRow`), `KenBurnsFramingView.swift` (hoja ampliada) y `RenamerView.swift`.

### 4. Decisiones
- Causa: un `Picker` de menú con `.frame(maxWidth: N)` sin alineación. En macOS el desplegable no se estira hasta ese ancho y SwiftUI lo centra en el hueco, así que cuanto más corto es su texto, más a la derecha queda. Deslizadores, segmentados y campos de texto sí llenan el hueco y salían bien.
- Arreglo: `alignment: .leading` en los 7 desplegables con ancho máximo (Vídeo › Transición; Posición, Entrada y Salida del editor de estilo; Fondo de la tarjeta; Transición en horizontal; Efecto de la hoja ampliada; Modo del Renombrador). Regla anotada en `documentacion.md`.
- Comprobado con capturas de Vídeo, Portada y texto (con pies) y Renombrador en oscuro y claro. La tarjeta de texto con estilo propio usa el mismo `TextStyleEditor` y el Fondo tiene el mismo arreglo; no se capturó aparte.
- Versión 3.4.3.

### 5. Alternativas descartadas
- `.fixedSize()` en los desplegables: también los alinea, pero pierden el ancho máximo y los textos largos podrían empujar lo que va detrás.

### 6. Pendiente de comprobar
Nada.

## 2026-10-19 — Cada tarjeta de texto con su estilo y rediseño de su inspector

### 1. La petición tal como se ha entendido
**Sin estilo común de títulos:**
- Desaparece el bloque «Estilo de títulos» de la pestaña «Portada y texto», que queda con Portada y créditos, Marca de agua y Pies de foto.
- Cada tarjeta de texto lleva siempre su propio estilo. Ya no existe «Estilo propio para esta tarjeta» ni «Volver al estilo de títulos».
- Las tarjetas que ya existen y no tenían estilo propio se quedan con una copia del estilo de títulos guardado en el proyecto, así que se ven igual que antes.
- Una tarjeta nueva copia el estilo de la tarjeta de texto anterior en el timeline, o el de la siguiente si es la primera. Si no hay ninguna, usa el estilo por defecto de la app.
- **«Aplicar estilo a todas»:** copia el estilo de esta tarjeta (letra, colocación y animaciones) a todas las tarjetas de texto del proyecto, pidiendo confirmación antes.

**Inspector de la tarjeta, con el mismo esquema que Collage y Foto:**
- **Cabecera:** «Texto · <primera línea>» y, a la derecha, «Aplicar estilo a todas».
- **Izquierda:** vista previa en vivo de la tarjeta, con su fondo o sobre el elemento siguiente.
- **Derecha, columna de grupos con título:**
  1. **Contenido:** texto y subtítulo.
  2. **Pantalla y tiempo:** dónde se ve (pantalla propia con fondo negro, blanco o gris, o sobre el elemento siguiente) y cuánto dura. Con pantalla propia, también su transición.
  3. **Letra:** fuente, negrita, tamaño y color.
  4. **Colocación:** posición y realce del texto (nada, sombra o banda). Se llama «Realce» para no confundirlo con el fondo de la pantalla.
  5. **Animación:** entrada y salida, cada una con su duración.
  6. **Empalmes**, solo con pantalla propia: empezar el texto sobre el elemento anterior y mantenerlo al fundirse con el siguiente, cada uno con sus segundos y con textos más cortos.

El estilo de los pies de foto no cambia.
Confirmada por el usuario («si»).

### 2. Preguntas y respuestas
- **¿Con qué estilo nace una tarjeta nueva: copia de la anterior o siempre el de la app?** → Copia del estilo de la tarjeta de texto anterior en el timeline (o de la siguiente si es la primera); si no hay ninguna, el estilo por defecto de la app.
- **Sin estilo común, ¿acción para copiar el estilo de una tarjeta a las demás?** → Sí: «Aplicar a todas» en el grupo de estilo, con confirmación; copia el estilo (fuente, tamaño, color, posición, animaciones) a todas las tarjetas de texto del proyecto.
- **¿Distribución del inspector: vista previa + columna de grupos, o dos columnas de grupos sin vista previa?** → Vista previa en vivo de la tarjeta a la izquierda y columna de grupos a la derecha, como Collage y Foto.

### 3. Fuentes analizadas
- `CaobaApp/Sources/Model/SlideshowDocument.swift` (`titleStyle`, `addTextCard`, carga y guardado del preset, `applyText`).
- `CaobaApp/Sources/Views/Modules/Slideshow/SlideshowInspector.swift` (`ExtrasTab`, `TextStyleEditor`, `TextCardInspector`), `TextPreviewPanel.swift`, `SlideshowView.swift` (demo `text.demo`).
- `CaobaCore/Sources/CaobaCore/Slideshow/TextOverlay.swift` (`TextCard`, `TextStyle`) y `SlideshowPreset.swift` (`text.titleStyle`).

### 4. Decisiones
- Plan aprobado («dale»), con release y publicación (versión 3.5.0).
- `TextCard.style` sigue siendo opcional en el formato del fichero, para leer los `.caoba` antiguos sin tocar el motor. Al cargar, toda tarjeta con `style == nil` recibe una copia de `text.titleStyle` (o `.title`); al guardar ya no se escribe `titleStyle`. Comprobado con una carpeta de prueba: las tarjetas heredan Georgia y el fichero deja de llevar `titleStyle`.
- `titleStyle` sale del documento. El fondo liso de las tarjetas y el render usan `.title` como reserva (`card.style ?? .title`), que solo se usaría si algo creara una tarjeta sin estilo.
- Tarjeta nueva: `inheritedStyle(for:)` toma el de la tarjeta de texto anterior en el timeline, si no el de la siguiente, si no `.title`. «Aplicar estilo a todas» (`applyStyleToAllCards(from:)`) con confirmación que explica qué cambia y qué no. Comprobado con un gancho temporal (ya quitado): la nueva hereda Georgia y al aplicar Menlo a todas, las tres pasan a Menlo.
- `TextStyleEditor` con `parts` y `stacked`: un solo editor para los pies (completo, en filas) y para la tarjeta (cada parte en su grupo, en columna). «Fondo» del texto pasa a «Realce» en todos los sitios para no confundirlo con el fondo de la pantalla.
- `StackedRow` en `Theme.swift` (etiqueta encima), compartido por el editor y el inspector.
- En «Pantalla y tiempo», la duración de la transición en columna se llama «Duración de la transición»: había dos «Duración» seguidas. Afecta también a Collage y Foto, donde se lee igual de bien.
- `TextPreviewPanel(content:)`: `.card` en el inspector, `.caption` en «Portada y texto» (la tarjeta ya se ve en su inspector).
- `slideshow.select` acepta `text`. Test nuevo en el motor: una tarjeta guardada sin `style` se sigue leyendo junto con el `titleStyle` antiguo. Pasan los 129 tests.
- Versión 3.5.0: cambia el funcionamiento (no hay estilo común).

### 5. Alternativas descartadas
- Toda tarjeta nueva con el estilo de la app: obliga a repetir los ajustes en cada tarjeta; descartado por el usuario.
- Sin «Aplicar estilo a todas»: cambiar la fuente del proyecto sería ir tarjeta por tarjeta; descartado por el usuario.
- Dos columnas de grupos sin vista previa: descartado por el usuario.
- Hacer `TextCard.style` obligatorio en el motor: rompería la lectura de los `.caoba` antiguos o necesitaría un decodificador propio; la migración en la app basta.

### 6. Pendiente de comprobar
- El grupo Empalmes queda en la parte de la columna que hay que desplazar y no salió en las capturas; usa las mismas piezas (casillas, ayuda y `StackedSlider`) que se ven en el resto.
- La confirmación de «Aplicar estilo a todas» (ventana aparte) no se vio en pantalla; la acción se comprobó con el gancho temporal.
