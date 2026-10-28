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

## 2026-10-19 — Los ajustes de la tarjeta de texto ocupan el ancho que sobra

### 1. La petición tal como se ha entendido
En los inspectores de **Texto, Collage y Foto**, la columna de ajustes mide 300 puntos fijos. La vista, que ocupa el resto, queda limitada por la altura disponible y deja un hueco vacío entre las dos. Se invierte el reparto:
- **La vista toma solo el ancho que necesita** para llenar el alto disponible con su proporción: la tarjeta en el formato del vídeo, el collage en el de su plantilla y, en Foto, los dos paneles de Inicio y Fin.
- **Los ajustes se quedan con todo lo demás**, creciendo hacia la izquierda. Nunca bajan de una columna de unos 300 puntos; si no cabe, es la vista la que encoge.
- **Con el ancho extra, los grupos se reparten en 2 o 3 columnas**, de unos 280 puntos como mínimo cada una. Se leen en orden, de arriba abajo y de izquierda a derecha, y el reparto busca columnas de alto parecido. Si aun así no cabe en alto, la zona se desplaza como ahora.

No cambia ningún control, solo el reparto del espacio.
Confirmada por el usuario («si»).

### 2. Preguntas y respuestas
- **Con la zona de ajustes más ancha, ¿grupos en varias columnas o una columna más ancha?** → Grupos repartidos en 2 o 3 columnas según quepan (mínimo unos 280 puntos cada una).
- **¿Se aplica también a Collage y Foto, que usan la misma columna fija?** → Sí, a los tres inspectores.

### 3. Fuentes analizadas
- `CaobaApp/Sources/Views/Modules/Slideshow/SlideshowInspector.swift` (`InspectorColumn`, `TextCardInspector`, `CollageInspector`) y `KenBurnsFramingView.swift`.

### 4. Decisiones
- Plan aprobado («si»), con release y publicación (versión 3.5.1).
- `InspectorSplit` sustituye a `InspectorColumn`. Cada inspector pasa la cuenta alto → ancho de su vista: tarjeta `(alto − 56) × proporción del vídeo` (título y etiqueta de la vista previa), collage `(alto − 24) × proporción de la plantilla` (línea de ayuda), foto `2 × (alto − 44) × proporción + 10` (dos paneles con su etiqueta y zoom). Ajustes con un mínimo de 300 puntos.
- `BalancedColumns` (un `Layout` de SwiftUI): 1–3 columnas de al menos 280 puntos; reparte en orden y en tramos seguidos probando todos los cortes (son pocos grupos), y se queda con el que deja la columna más alta más baja.
- Error encontrado al probar: SwiftUI pregunta a veces el tamaño con un ancho infinito y la cuenta de columnas hacía caer la app (`Double` infinito a `Int`). Se mide como una columna cuando el ancho no es finito.
- La previsualización animada del grupo Encuadre se ajusta al ancho de su columna (antes, 270 puntos fijos); la hoja ampliada no cambia.
- Comprobado con capturas de los tres inspectores a 1440×900, 1100×720 y 2000×1300, y Texto y Foto a 2000×900. A 1440×900 la tarjeta tiene unos 430 puntos de ajustes (una columna más ancha); a 2000×900, tres columnas. En Foto los dos paneles necesitan mucho ancho para llenar el alto y los ajustes se quedan en su mínimo.
- Versión 3.5.1.

### 5. Alternativas descartadas
- Una sola columna más ancha: sigue habiendo que desplazar; descartado por el usuario.
- Repartir los grupos a la columna más baja (tipo «masonry»): rompe el orden de lectura.
- Encoger la vista para forzar dos columnas a 1440×900: el usuario pidió que la vista tome lo que necesita y los ajustes el resto.

### 6. Pendiente de comprobar
- En Foto, con ventanas anchas y bajas, los paneles se llevan casi todo el ancho y los ajustes quedan en 300 puntos. Es lo acordado; si se ve estrecho, se podría limitar el ancho de los paneles.

## 2026-10-20 — Inspector de Foto: encuadre solo con «Personalizado», controles antes que la previsualización

*(La petición anterior, «limita el ancho de los paneles en Foto», la interrumpió el usuario para pasar a esta, que la sustituye.)*

### 1. La petición tal como se ha entendido
Se reorganiza el inspector de Foto del Slideshow:
- **Cabecera:** nombre del fichero y «Ampliar», igual que ahora.
- **Izquierda, los controles,** en grupos repartidos en columnas si caben: Efecto, Encuadre, Tiempo, Transición y Pie.
- **Encuadre solo con el efecto «Personalizado».** Con cualquier otro efecto (Ninguno, Aleatorio, acercar, alejar, barridos) no aparece nada del encuadre: ni paneles ni sus controles.
- **Inicio y Fin pequeños, dentro del grupo Encuadre:** uno encima del otro, al ancho de su columna, cada uno con su zoom. Debajo, Ajuste, Enfocar caras, Inicio → Fin, Intercambiar, Restablecer y Retardo. Para encuadrar con detalle sigue estando «Ampliar».
- **Derecha, la previsualización animada** con «Reproducir» y la duración. Toma el ancho que necesita para llenar el alto, como mucho más o menos el 45 % del inspector, para que los controles no se queden sin sitio.

No cambia lo que hace ningún control. La hoja «Ampliar» se queda como está.
Confirmada por el usuario («si»).

### 2. Preguntas y respuestas
- **Con un efecto que no es «Personalizado», ¿qué se ve del encuadre: nada o solo el foco?** → Nada del encuadre: solo Efecto, Tiempo, Transición, Pie y la previsualización. Para encuadrar a mano se elige «Personalizado» (o «Ampliar»).
- **¿Distribución: controles a la izquierda y previsualización a la derecha, o controles arriba y previsualización debajo?** → Controles a la izquierda (en columnas si caben) y previsualización animada a la derecha.

### 3. Fuentes analizadas
- `CaobaApp/Sources/Views/Modules/Slideshow/KenBurnsFramingView.swift` y `SlideshowInspector.swift` (`InspectorSplit`, `PhotoInspector`).
- `CaobaCore/Sources/CaobaCore/Slideshow/KenBurns.swift` (`cropRect(for:…)`): Inicio y Fin solo los usa el efecto `custom`; los automáticos usan el foco de inicio, el retardo y el ajuste. En la app, tocar cualquier control del encuadre pasa la foto a «Personalizado».

### 4. Decisiones
- Plan aprobado («dale»), con release y publicación (versión 3.5.2).
- `InspectorSplit` con `previewOnTrailingSide` y `maxPreviewFraction` (Texto y Collage siguen igual).
- En el inspector, `KenBurnsFramingView` pone la previsualización animada a la derecha (como mucho el 45 % del ancho) y el grupo Encuadre solo con «Personalizado». La hoja «Ampliar» no cambia.
- Paneles en pequeño: la imagen del panel y su zoom se separan (`panelImage`, `zoomRow`) para usarlos a tamaño fijo (hoja) o flexible (inspector) sin repetir código.
- Ajuste tras la primera captura: con la ventana pequeña la zona de controles es una sola columna ancha y Inicio y Fin volvían a salir enormes. Ahora van uno al lado del otro de 210 puntos si caben y, si no, uno encima del otro de hasta 260 (`ViewThatFits`).
- Comprobado con capturas con efecto «Ninguno» y «Personalizado» a 1440×900, 1100×720 y 2000×900 (oscuro) y 1440×900 (claro).
- Versión 3.5.2.

### 5. Alternativas descartadas
- Enseñar solo el foco (y «Enfocar caras») con los efectos automáticos: hoy tocarlo pasa la foto a «Personalizado»; descartado por el usuario.
- Controles arriba y previsualización debajo: descartado por el usuario.
- Paneles al ancho completo de la columna: con una sola columna ancha volvían a ocupar demasiado.

### 6. Pendiente de comprobar
- Con los efectos automáticos ya no hay forma de ver ni cambiar el foco que usan (el de Inicio) sin pasar a «Personalizado»; si hiciera falta, sería otra petición.

## 2026-10-20 — Inspector de Foto: columnas fijas (ajustes, encuadre, previsualización)

### 1. La petición tal como se ha entendido
*(sin preguntas: la petición y la captura marcan el reparto)* En el inspector de Foto los grupos dejan de repartirse solos en columnas. Pasan a tres zonas fijas:
- **Izquierda:** Efecto, Tiempo, Transición y Pie, uno debajo de otro (ahora Transición y Pie se iban a una segunda columna).
- **Centro, solo con «Personalizado»:** el grupo Encuadre (Inicio y Fin en pequeño, uno encima del otro, con sus controles).
- **Derecha:** la previsualización animada, como ahora (como mucho el 45 % del ancho).

Sin «Personalizado» solo hay columna de ajustes y previsualización. Si la ventana es estrecha, las dos columnas de controles mantienen un mínimo (unos 280 puntos cada una) y es la previsualización la que encoge. Cada columna se desplaza por su cuenta si no cabe en alto.
Confirmada por el usuario («si»).

### 2. Preguntas y respuestas
Ninguna.

### 4. Decisiones
- Plan aprobado («si»), con release y publicación (versión 3.5.3).
- `InspectorSplit` con `minSettingsWidth` (antes fijo a 300) y `balancesSettings`: con `false` los ajustes se colocan tal cual y quien llama monta sus columnas. Texto y Collage siguen con el reparto automático.
- Foto: dos columnas fijas del mismo ancho, cada una con `InspectorScroll` (el `ScrollView` que ya usaba el reparto, sacado a una pieza para no repetirlo). Mínimo de controles: 280 con una columna, 2 × 280 + 16 con dos.
- Inicio y Fin siempre uno encima del otro (hasta 260 puntos): en la columna central ya no hace falta ponerlos uno al lado del otro.
- Comprobado con capturas con «Ninguno» y «Personalizado» a 1440×900, 1100×720 y 2000×900 (oscuro) y 1440×900 (claro).
- Versión 3.5.3.

### 3. Fuentes analizadas
- `CaobaApp/Sources/Views/Modules/Slideshow/KenBurnsFramingView.swift` y `SlideshowInspector.swift` (`InspectorSplit`).

### 5. Alternativas descartadas
- Mantener el reparto automático (`BalancedColumns`) en Foto: mandaba Transición y Pie a otra columna, que es lo que el usuario quería evitar.

### 6. Pendiente de comprobar
Nada.

## 2026-10-20 — Editar elementos del timeline en un modal

*(El título se queda como se abrió el bloque; durante las preguntas el usuario redefinió la petición: no es un modal.)*

### 1. La petición tal como se ha entendido
Al editar un elemento del timeline (foto, collage, texto, portada, créditos o pista) deja de aparecer una pestaña más. En su lugar:
- **Se abre con un clic** en el elemento, como ahora.
- **El editor tapa la parte de arriba del módulo:** el título SLIDESHOW, las pestañas y su contenido. Se ven igual que antes la barra de carpeta, el timeline y la barra inferior.
- **Para que se note que se está editando,** lleva un borde rojo y una cabecera «Editando · <tipo> · <nombre>». A la derecha de la cabecera van las acciones de ese elemento (Ampliar, Aplicar estilo a todas, Encuadre/Resultado, Centrar, Cambiar, Quitar…) y el botón **Cerrar**, que también responde a Esc. Las cabeceras propias de cada editor desaparecen para no repetir el nombre.
- **Debajo, el editor de ese elemento** con todo el espacio. Es el mismo contenido de hoy (Foto, Collage, Texto, Portada/Créditos, Pista).
- **Si se pulsa otro elemento del timeline** con el editor abierto, pasa a editar ese otro.
- **Al cerrar se deselecciona el elemento** y vuelve a verse lo que había: el título, las pestañas y la pestaña que estaba abierta. Pulsar en un hueco vacío del timeline, que ya deselecciona, también lo cierra.
- **La pestaña contextual** («Foto», «Texto», «Collage 1»…) desaparece de la barra de pestañas.
Confirmada por el usuario («si»).

### 2. Preguntas y respuestas
- **¿Cómo se abre el editor modal: doble clic (un clic solo selecciona) o un clic?** → Un clic. Para mover o borrar se usa arrastrar directamente o el clic derecho.
- **¿Qué tapa el modal: todo el módulo o todo menos el timeline?** → El usuario redefine la petición: **no es un modal**. El editor usa el mismo espacio de arriba, tapando lo que hay (no como una pestaña más); hay que cerrarlo para volver a ver lo anterior, y al cerrarlo se deselecciona el elemento en el timeline. El timeline sigue visible debajo.
- **¿Desde dónde tapa el editor: título y pestañas, o solo las pestañas?** → Título SLIDESHOW, pestañas y su contenido. La barra de carpeta, el timeline y la barra inferior siguen visibles.

### 4. Decisiones
- Plan aprobado («dale»), con release y publicación (versión 3.6.0).
- Con selección, `SlideshowView` cambia título, pestañas y contenido por `SelectionEditor` dentro de `.caobaPanel(padding: 12, border: .accentColor, borderWidth: 2)`; sin selección, lo de siempre. Fuera `SlideshowTab.inspector`, la pestaña contextual, `selectionTitle` y la lógica de «pestaña anterior»: como ya no se cambia de pestaña al seleccionar, al cerrar se ve la que estaba.
- `EditorHeader` común (nombre en una sola línea «Editando · tipo · nombre», acciones del editor y «Cerrar» con `.keyboardShortcut(.cancelAction)`, es decir, Esc). Sustituye a las cabeceras propias de Foto, Collage, Texto, Portada/Créditos y Pista.
- `slideshow.select` acepta `track` (primera pista).
- Comprobado con capturas de Foto (oscuro y claro), Collage, Texto, Pista y sin selección; y con un gancho temporal (ya quitado): con «Portada y texto» abierta y una foto seleccionada, al hacer lo mismo que «Cerrar» la selección queda vacía y vuelve «Portada y texto».
- Versión 3.6.0: cambia cómo se edita.

### 3. Fuentes analizadas
- `CaobaApp/Sources/Views/Modules/Slideshow/SlideshowView.swift` (barra de pestañas, pestaña contextual y cambio de pestaña al seleccionar) y `SlideshowInspector.swift` (`SelectionTab` y cabeceras de cada editor).

### 5. Alternativas descartadas
- Modal sobre la ventana con fondo oscurecido: el usuario redefinió la petición; tapaba el timeline y obligaba a cerrar para cambiar de elemento.
- Doble clic para editar (un clic solo selecciona): descartado por el usuario; se edita con un clic.
- Dejar el título SLIDESHOW visible y tapar solo las pestañas: descartado por el usuario.

### 6. Pendiente de comprobar
- Esc cierra el editor desde el botón «Cerrar» (`cancelAction`); si el foco está en un campo de texto, ese campo puede quedarse el Esc. No se probó con el teclado de verdad, solo la acción de cerrar.

## 2026-10-20 — Foto: previsualización más pequeña y sin «Ampliar»

### 1. La petición tal como se ha entendido
En el editor de Foto del Slideshow:
- **La previsualización animada** de la derecha ocupa como mucho **un tercio del ancho** del editor (ahora, el 45 %). Sigue sin pasar de lo que necesita para llenar el alto, y los ajustes ganan el espacio.
- **Fuera la opción «Ampliar»:** el botón de la cabecera y la hoja de encuadre a pantalla grande, con sus flechas para pasar de foto. El encuadre se hace solo en el grupo Encuadre del editor, con «Personalizado».
- Como la hoja era lo único que usaba la vista de encuadre «sin columnas» (paneles grandes uno al lado del otro), ese modo desaparece del código.
Confirmada por el usuario («si»).

### 2. Preguntas y respuestas
- **¿Qué paneles se limitan: la previsualización, Inicio y Fin, o los dos?** → La previsualización.
- **¿Qué tope: 480 puntos, un tercio del ancho o 360 puntos?** → Un tercio del ancho del editor.

### 3. Fuentes analizadas
- `CaobaApp/Sources/Views/Modules/Slideshow/KenBurnsFramingView.swift` (vista de encuadre y `KenBurnsFramingSheet`), `SlideshowInspector.swift` (`SelectionEditor`, `PhotoInspector`) y `SlideshowView.swift`.

### 4. Decisiones
- Plan aprobado («si»), con release y publicación (versión 3.6.1).
- `maxPreviewFraction` de Foto: de 0,45 a 1/3.
- Fuera el botón «Ampliar», `KenBurnsFramingSheet` y el estado `expandedFraming` (en `SlideshowView`, `SelectionEditor` y `PhotoInspector`).
- `KenBurnsFramingView` queda con un solo camino (el del editor): fuera el inicializador sin huecos, `compact`, `hasLeading`, los paneles grandes uno al lado del otro y `panel(title:size:)` de tamaño fijo.
- La cadena «Ampliar» se queda en `Localizable.xcstrings` sin uso: Xcode la marca como obsoleta al compilar el catálogo; no se borra a mano.
- Comprobado con capturas con «Personalizado» y «Ninguno» a 1440×900 y 2000×900 (oscuro) y 1440×900 (claro), y con `grep` de que no queda «Ampliar», `expandedFraming`, `KenBurnsFramingSheet` ni `compact:` en el código.
- Versión 3.6.1.

### 5. Alternativas descartadas
- Tope fijo de 480 o 360 puntos para la previsualización: descartado por el usuario; prefiere que crezca con la ventana (un tercio).
- Mantener la hoja «Ampliar» para encuadrar con más detalle: el usuario pidió quitarla.

### 6. Pendiente de comprobar
Nada.

## 2026-10-20 — Foto: la columna de Encuadre, del ancho justo de Inicio y Fin

### 1. La petición tal como se ha entendido
*(sin preguntas: la captura marca el problema)* En el editor de Foto, con «Personalizado», la columna del Encuadre crece igual que la de la izquierda y deja un hueco vacío a la derecha de Inicio y Fin. Pasa a tener **ancho fijo, el justo para Inicio y Fin** (sus 260 puntos más el margen del bloque). El espacio que sobre se lo queda la columna de la izquierda (Efecto, Tiempo, Transición y Pie); la previsualización no cambia.
Confirmada por el usuario («si»).

### 2. Preguntas y respuestas
Ninguna.

### 4. Decisiones
- Plan aprobado («dale»), con release y publicación (versión 3.6.2).
- Columna del Encuadre con `.frame(width: framingColumnWidth)`: `panelMaxWidth` (260) + 2 × 10 del margen del bloque + 2 del hueco de la barra de desplazamiento. El 260 pasa a ser una constante compartida con el tope de los paneles. Mínimo de controles: 280 + 16 + ese ancho.
- Comprobado con capturas con «Personalizado» a 1440×900 y 2000×900 (oscuro) y 1440×900 (claro).
- Versión 3.6.2.

### 3. Fuentes analizadas
- `CaobaApp/Sources/Views/Modules/Slideshow/KenBurnsFramingView.swift`.

### 5. Alternativas descartadas
- Repartir el ancho entre las dos columnas a partes iguales (lo que había): dejaba el hueco vacío junto a los paneles.

### 6. Pendiente de comprobar
Nada.

## 2026-10-20 — Revisión: «Desde» de una pista no parece aplicarse al exportar

### 1. La petición tal como se ha entendido
*(revisión, sin cambios de código)* El usuario cree que el «Desde» de una pista (segundo del MP3 desde el que empieza a sonar, para saltarse silencio o voces del principio) no se aplica al exportar cuando se escribe a mano. Se pide revisar si hay un fallo.

### 2. Preguntas y respuestas
Ninguna (se investigó primero; las dudas quedan en el apartado 6).

### 3. Fuentes analizadas
- `CaobaCore/Sources/CaobaCore/Audio/AudioMuxer.swift`, `AudioPlan.swift`, `Slideshow/SlideshowRenderer.swift` (camino del audio al exportar).
- `CaobaApp/Sources/Model/SlideshowDocument.swift` (guardado y carga de las pistas en el preset) y `TimecodeField` en `SlideshowView.swift`.
- `.caoba` del proyecto real del usuario (solo lectura): la primera pista tiene `trimStart: 5`.

### 4. Decisiones
- Pruebas hechas (todas correctas):
  - Motor con un tono de 440 Hz los primeros 5 s y 1000 Hz después, en MP3 y M4A, «Desde» = 5: el vídeo empieza en 1000 Hz.
  - App de punta a punta (preset → documento → vídeo) con el mismo tono en MP3, y con un MP3 de bitrate variable de 3 minutos: empieza en 1000 Hz.
  - App con el MP3 real del usuario («Desde» = 5): el audio del vídeo coincide con el MP3 a partir del segundo 4,9 (dentro del margen de la medición).
- Mismo camino de audio en «Vista previa» y «Generar vídeo»; «Normalizar» solo cambia el volumen.
- Hallazgo: `TimecodeField` solo guarda el valor al pulsar Intro. Si se escribe y se sale del campo de otra forma (clic en otro sitio, «Cerrar», Esc, «Generar vídeo»), el valor no se guarda aunque el campo lo siga mostrando. Encaja con «asignando a mano el valor no funciona». No se ha cambiado nada: se propone como arreglo.
- Observación: esa canción suena con el mismo volumen desde el segundo 0, sin silencio ni voces al principio; saltarse 5 s de música continua puede pasar desapercibido al oírlo.

### 5. Alternativas descartadas
Ninguna.

### 6. Pendiente de comprobar
- Si el usuario pulsaba Intro al escribir el valor, y qué oye exactamente al principio del vídeo exportado.
- En el mismo proyecto, la segunda pista tiene `startTime` 24,09 y `trimStart` 17,09 (justo 7 s menos); puede venir de estirar su borde en el timeline. No se ha revisado.

## 2026-10-20 — Preescuchar una pista en su editor

### 1. La petición tal como se ha entendido
En el editor de una pista del Slideshow se añade un **reproductor** para oír cómo queda el recorte:
- **Botón play/pausa y barra de posición** del tramo entre Desde y Hasta. La barra se puede arrastrar para saltar, y al lado se ve el tiempo de la canción.
- Suena **la pista tal cual**, sin fundidos ni normalización: sirve para oír dónde empieza y dónde acaba.
- **Al cambiar Desde** mientras suena, salta al nuevo Desde y sigue sonando. **Al cambiar Hasta**, sigue y para al llegar al nuevo Hasta. Lo mismo si se cambian estirando los bordes del bloque en el timeline.
- **Al llegar a Hasta** se para y vuelve a Desde. También se para al cerrar el editor o al pasar a editar otro elemento.
- **Arreglo incluido:** Inicio en el vídeo, Desde y Hasta se guardan también al pulsar Tab, hacer clic fuera o cerrar el editor, no solo con Intro.
Confirmada por el usuario («si»).

### 2. Preguntas y respuestas
- **¿Qué tipo de preescucha: reproductor con atajos de inicio y final, solo los atajos o solo un reproductor?** → Solo un reproductor (play/pausa y barra de posición) del tramo Desde → Hasta.
- **Al cambiar Desde o Hasta mientras suena, ¿vuelve a empezar o se para?** → Si cambia Desde, salta al nuevo Desde y sigue sonando; si cambia Hasta, sigue y para al llegar al nuevo Hasta.
- **¿Se arregla también aquí que Desde y Hasta solo se guarden con Intro?** → Sí: los campos de tiempo guardan también al pulsar Tab, hacer clic fuera o cerrar el editor.

### 4. Decisiones
- Plan aprobado («dale»), con release y publicación (versión 3.7.0).
- `TrackPreviewPlayer` (`@Observable`, en `Model/`) sobre `AVAudioPlayer`: reproduce el fichero tal cual, con un temporizador de 20 Hz que sigue la posición y para en Hasta. `setRange(start:end:)` salta a Desde si cambia y para si la posición queda por detrás de Hasta.
- Vista `TrackPreview` en un grupo «Preescucha» del editor de pista, solo cuando ya se conoce la duración del fichero. El editor de pista lleva `.id(track.id)` para que al pasar a otra pista la vista se rehaga y el reproductor anterior se pare (`onDisappear`).
- `TimecodeField` guarda también al perder el foco (`@FocusState`) y al desaparecer, pero **solo si el texto ha cambiado**: guardar lo mismo redondearía a segundos enteros (un Hasta de 182,01 pasaría a 182) y en «Inicio en el vídeo» cambiaría «tras la anterior» por un tiempo fijo. Comprobado: tras abrir y cerrar el editor, el `.caoba` conserva `trimEnd` 182,0137.
- Comprobado el reproductor compilándolo aparte con un programa de prueba (tono de 440/1000 Hz, Desde 5, Hasta 7): empieza en 5 y avanza; al cambiar Desde a 6 salta allí y sigue; al llegar a Hasta para y vuelve a Desde. El sonido no se ha podido oír, solo la posición.
- Captura del editor de pista en oscuro y claro. Cadenas nuevas en `Localizable.xcstrings` con su inglés.
- Versión 3.7.0: función nueva.

### 3. Fuentes analizadas
- `CaobaApp/Sources/Views/Modules/Slideshow/SlideshowInspector.swift` (`TrackInspector`) y `SlideshowView.swift` (`TimecodeField`).

### 5. Alternativas descartadas
- Reproductor con atajos «Oír el inicio» y «Oír el final», o solo los atajos: descartado por el usuario.
- Pararse al cambiar Desde o Hasta: descartado por el usuario.
- Reproducir con la mezcla real (fundidos, normalización) a través de `AudioMuxer`: más lento y no hace falta para oír dónde empieza y acaba.

### 6. Pendiente de comprobar
- El guardado al perder el foco (Tab o clic fuera) se ha revisado en el código, pero no con el teclado de verdad.

## 2026-10-20 — Que se vea que la lista de fotos se puede reordenar

### 1. La petición tal como se ha entendido
En las listas de fotos que se pueden reordenar arrastrando (Slideshow, Collage y Contact Sheet) no se nota que se puede hacer. Se añade:
- **Un asa ≡ al final de cada fila**, **cursor de mano abierta** al pasar por encima de la fila y **«Arrastra para cambiar el orden»** junto al contador («24 de 24»). En las listas que no se pueden reordenar (Procesador, Marca de agua, Metadatos, Renombrador) no sale nada de esto.
- **Opción «Manual» en el selector «Orden»** (junto a Nombre y Fecha). Se elige sola al arrastrar una foto. Con «Manual», la carpeta no se vuelve a ordenar por su cuenta.
- **Pasar de «Manual» a Nombre o Fecha pide confirmación**, porque se pierde el orden hecho a mano.
- El orden manual se guarda y se recupera con el proyecto, como ahora. Al abrir otra carpeta, si no tiene orden manual guardado, «Orden» vuelve a «Nombre».
Confirmada por el usuario («si»).

### 2. Preguntas y respuestas
- **¿Cómo se indica que se pueden arrastrar las fotos: asa + cursor + aviso, solo el asa o solo el aviso?** → Asa ≡ al final de cada fila, cursor de mano abierta al pasar por encima y «Arrastra para cambiar el orden» junto al contador.
- **Tras reordenar a mano, «Orden» sigue diciendo «Nombre» y tocarlo pierde el orden: ¿se arregla aquí?** → Sí: opción «Manual» en «Orden», que se elige sola al arrastrar; volver a Nombre o Fecha pide confirmación si había orden manual.

### 4. Decisiones
- Plan aprobado («dale»), con release y publicación (versión 3.7.1).
- «Manual» va como marca de la app (`AppState.isManualOrder`) y no en el `SortMode` del motor: ese tipo también lo usa «Ordenar por» del Renombrador, donde «Manual» no tiene sentido.
- Indicadores solo con `allowsReorder`: asa `line.3.horizontal` (en gris secundario: en terciario casi no se veía), cursor `openHand` con `onHover` y «· Arrastra para cambiar el orden» junto al contador.
- Selector «Orden» con Nombre, Fecha y Manual. Manual guarda el orden actual (`keepCurrentOrderAsManual`); de Manual a Nombre o Fecha, `confirmationDialog` y `sortAutomatically(by:)`.
- Fallo encontrado al probar (y que ya pasaba antes de este cambio): al reabrir la carpeta, el Slideshow aplicaba su `fileOrder` antes de que terminase la lectura de la carpeta y esta lo pisaba, así que el orden manual se perdía. Arreglo: `AppState` recuerda el orden manual (`manualNames`) y lo vuelve a aplicar al final de cada lectura mientras esté en Manual (también al cambiar el filtro de orientación).
- Preset del Slideshow: `sortMode: "manual"` cuando hay orden manual (el orden ya iba en `fileOrder`); al abrir, `"manual"` enciende la marca (también en proyectos de la app antigua).
- Comprobado con un gancho temporal (ya quitado), en tres arranques: mover la foto 3 al principio → Manual y guardado `"manual"` con ese orden; reabrir → Manual y el mismo orden; cambiar el filtro de orientación y volver → se mantiene. Capturas de la lista del Slideshow con Manual (oscuro y claro) y del Procesador (sin indicadores).
- Versión 3.7.1.

### 3. Fuentes analizadas
- `CaobaApp/Sources/Views/Shared/FileListView.swift`, `CaobaApp/Sources/Model/AppState.swift` (lectura de la carpeta, `moveFiles`, `applyOrder`), `SlideshowDocument.swift` (guardado y carga del orden) y `CaobaCore/Sources/CaobaCore/Scanning/FolderScanner.swift` (`SortMode`).

### 5. Alternativas descartadas
- Solo el asa o solo el aviso: descartado por el usuario.
- Dejar el selector «Orden» como estaba: descartado por el usuario (decía «Nombre» con un orden manual y tocarlo lo perdía).
- Añadir `manual` al `SortMode` del motor: aparecería en «Ordenar por» del Renombrador.

### 6. Pendiente de comprobar
- El cursor de mano abierta no sale en las capturas; se ha revisado en el código, no con el ratón.
- Collage y Contact Sheet no guardan el orden en su preset; durante la sesión se mantiene, pero al reabrir la carpeta en esos módulos vuelve al orden por nombre si el Slideshow no tenía orden manual guardado.

## 2026-10-20 — Arrastrar desde cualquier sitio de la fila y orden manual en Collage y Contact Sheet

### 1. La petición tal como se ha entendido
Dos cosas en las listas de fotos reordenables (Slideshow, Collage y Contact Sheet):
- **Arrastrar desde cualquier sitio de la fila.** Ahora solo funciona en el hueco junto a la casilla, porque un clic de la fila (el que usa la ficha de Metadatos para elegir foto) está puesto siempre, y el de la miniatura (abre la foto en grande) también se come el arrastre.
  - El clic de selección solo se pone donde hace falta (Metadatos).
  - La foto en grande se abre con un **botón de lupa** que aparece al pasar el ratón por la fila. La miniatura deja de abrirla. Esto vale en todas las listas, también en las que no se reordenan, para que funcione igual en toda la app.
- **El orden manual se guarda también para Collage y Contact Sheet**, con un único orden por carpeta común a los tres módulos: si reordenas en Collage, el Slideshow lo ve igual. Se recupera al volver a abrir la carpeta desde cualquiera de ellos. Los proyectos que solo tenían el orden manual guardado en el Slideshow lo siguen recuperando. «Reiniciar» lo quita, como el resto de la configuración de la carpeta.
Confirmada por el usuario («si»).

### 2. Preguntas y respuestas
- **Un clic en la miniatura abre la foto en grande y bloquea el arrastre: ¿doble clic, botón de lupa o dejarlo así?** → Botón de lupa al pasar el ratón por la fila; el resto de la fila se arrastra.
- **¿El orden manual se guarda uno por carpeta común a los tres módulos o uno por módulo?** → Uno por carpeta, común a Slideshow, Collage y Contact Sheet (como ya se comparte mientras la app está abierta).

### 4. Decisiones
- Plan aprobado («dale»), con release y publicación (versión 3.7.2).
- Causa del arrastre: `FileListView` ponía `.onTapGesture` (elegir foto para la ficha de Metadatos) en todas las filas, aunque la lista no lo usara, y la miniatura tenía otro `onTapGesture` (foto en grande); los dos se comían el arrastre de `List.onMove`. Ahora el de la fila solo se pone con `selection` (`SelectOnTap`), la miniatura no tiene clic y la foto en grande se abre con un botón de lupa que solo se ve (y responde) al pasar el ratón por la fila.
- Motor: `FileOrderSettings`, sección `fileOrder` del `.caoba` (no protegida, así que «Reiniciar» la borra). Test: guardar, leer, quitar y que «Reiniciar» la borra sin tocar `renameHistory`. Pasan los 130 tests.
- `AppState` lee `fileOrder` al abrir la carpeta (enciende Manual y aplica el orden al terminar la lectura), lo guarda al arrastrar o elegir Manual, lo quita con Nombre o Fecha y apaga Manual con «Reiniciar».
- Slideshow: antes aplicaba siempre su `fileOrder`, lo que pisaría un orden hecho en Collage. Ahora manda el orden común; el del Slideshow solo se usa sin él, y si era manual pasa a ser el común (`adoptManualOrder(names:)`, que no depende de que la carpeta ya esté leída: si no, se guardaría una lista vacía).
- Comprobado con un gancho temporal en `ContentView` (ya quitado), en arranques separados sobre la misma carpeta: mover en Collage → sección `fileOrder` con ese orden → Contact Sheet y Slideshow lo recuperan con Manual. Proyecto de antes con el orden manual solo en el Slideshow → al abrirlo se crea la sección común con ese orden y Collage lo ve igual. Captura de Collage con Manual.
- Versión 3.7.2.

### 3. Fuentes analizadas
- `CaobaApp/Sources/Views/Shared/FileListView.swift` (gestos de la fila y de la miniatura), `CaobaApp/Sources/Model/AppState.swift`, `SlideshowDocument.swift` (carga del orden) y `CaobaCore/Sources/CaobaCore/Config/` (`CaobaConfig`, `ComposeSettings`).

### 5. Alternativas descartadas
- Doble clic para ver la foto en grande, o dejar el clic en la miniatura: descartado por el usuario.
- Un orden por módulo: descartado por el usuario; mientras la app está abierta el orden ya es uno solo para todos.

### 6. Pendiente de comprobar
- El arrastre con el ratón de verdad: no se puede simular desde aquí sin permiso de Accesibilidad. Se ha quitado lo que lo bloqueaba (comprobado en el código); falta que el usuario lo pruebe.
- La lupa aparece al pasar el ratón: no sale en las capturas.
- Confirmado por el usuario («correcto»): el arrastre funciona desde cualquier sitio de la fila.

## 2026-10-20 — Ficheros del proyecto que ya no están en su sitio

### 1. La petición tal como se ha entendido
Al abrir un Slideshow guardado, los ficheros de fuera de la carpeta que recuerda el proyecto (**pistas de audio, imagen de portada, de créditos y PNG de marca de agua**) pueden no estar ya donde estaban. Hoy se descartan sin avisar y se pierden sus ajustes. En su lugar:
- **Se conservan con todos sus ajustes**: inicio en el vídeo, Desde y Hasta de una pista; duración y transición de la portada y los créditos; posición, tamaño y opacidad de la marca. También se siguen guardando en el proyecto mientras falten.
- **Se marcan:**
  - En el timeline, el bloque de la pista o la tarjeta de portada o créditos sale en rojo y rayado, con un aviso y el nombre del fichero. Una pista que falta ocupa desde su inicio hasta su Hasta, o hasta el final del vídeo si no tiene Hasta, porque no se sabe lo que dura.
  - En su editor, «No se encuentra: <ruta>» y un botón **«Localizar…»**.
  - La marca de agua, igual en su bloque de «Portada y texto».
- **«Localizar…»** abre el selector de ficheros para elegir el nuevo sitio (puede tener otro nombre) y cambia solo la ruta, sin tocar el resto de los ajustes. Después **busca en esa misma carpeta los demás ficheros que falten con el mismo nombre**, los recoloca solos y avisa de cuántos ha encontrado.
- **Al pulsar Generar vídeo o Vista previa con ficheros sin encontrar**, avisa: «Faltan N ficheros: se generará sin ellos», con «Generar igualmente» o «Cancelar». Si se genera, esos ficheros simplemente no entran.
Confirmada por el usuario («si»).

### 2. Preguntas y respuestas
- **¿Solo las pistas de audio o también el resto de ficheros externos (portada, créditos, marca de agua)?** → Todos: pistas, imagen de portada, de créditos y PNG de marca de agua.
- **Con ficheros sin encontrar, al pulsar Generar vídeo o Vista previa: ¿avisa y deja seguir, no deja generar o sigue sin avisar?** → Avisa («Faltan N ficheros: se generará sin ellos») con «Generar igualmente» o «Cancelar».
- **Al localizar un fichero en otra carpeta, ¿se buscan ahí los demás que faltan?** → Sí: los que tengan el mismo nombre se recolocan solos y se avisa de cuántos.

### 4. Decisiones
- Plan aprobado («dale»), con release y publicación (versión 3.8.0).
- Carga del preset: pistas, portada, créditos y marca se cargan aunque el fichero no exista (antes se descartaban y se perdían sus ajustes) y se siguen guardando tal cual.
- `SlideshowDocument`: `isMissing(_:)`, `missingFiles`, `available(_:)` (el fichero si está) y `relocate(_:to:)`. Lo que falta no entra en el vídeo (audio, portada, créditos, marca) ni en el análisis de ritmo. `timelineDuration(of:)`: una pista que falta (o aún sin leer) se dibuja hasta su Hasta o, sin él, lo que dure el vídeo desde su Desde.
- Interfaz: `MissingStripes` (rayado rojo) en el bloque de la pista y en la tarjeta de portada o créditos; `MissingFileNotice` («No se encuentra el fichero», ruta y «Localizar…», que abre el selector en la carpeta antigua con el nombre puesto) en los editores de Pista y Portada/Créditos y en el bloque de la marca; ⚠︎ y nombre en rojo en la fila de portada/créditos de «Portada y texto». La Preescucha no sale mientras la pista falte (no hay duración).
- Barra de acciones: «Vista previa» y «Generar vídeo» piden confirmación si faltan ficheros, con la lista de nombres.
- Comprobado: proyecto con dos pistas, portada y marca en una carpeta externa que luego se mueve. Capturas del timeline, del editor de pista (oscuro) y de «Portada y texto» (claro) con las marcas; el `.caoba` sigue con los cuatro ficheros. Gancho temporal (ya quitado): al recolocar solo la primera pista se encuentran los otros 3, se conservan Desde, Hasta, inicio, tamaño y opacidad, y el vídeo suena desde el Desde (1000 Hz con el tono de prueba). Con todo sin encontrar, el vídeo se genera (25 s, sin audio ni portada) sin fallar.
- Versión 3.8.0.

### 3. Fuentes analizadas
- `CaobaApp/Sources/Model/SlideshowDocument.swift` (carga y guardado del preset, `makeSpec`, montaje de fotos, banda sonora del timeline, ritmo), `SlideshowInspector.swift`, `SlideshowTimelineView.swift` (`TrackBlock`, tarjetas), `SlideshowView.swift` (`SlideshowActionBar`) y `Theme.swift`.

### 5. Alternativas descartadas
- Solo las pistas: descartado por el usuario.
- No dejar generar hasta resolverlos, o generar sin avisar: descartado por el usuario.
- Localizar uno a uno sin buscar el resto: descartado por el usuario.

### 6. Pendiente de comprobar
- La ventana de «Faltan N ficheros» y el aviso de «Se han encontrado N más» no salen en las capturas (ventanas aparte); se comprobó la acción, no la ventana.
- Collage y Contact Sheet tienen su propia marca de agua o logo; no se han tocado (no estaban en la petición, que era del Slideshow).

## 2026-10-20 — Sin carpeta de origen, todo deshabilitado salvo elegirla

### 1. La petición tal como se ha entendido
En los módulos que trabajan sobre una carpeta de fotos (Slideshow, Collage, Contact Sheet, Procesador, Marca de agua, Metadatos y Renombrador), mientras no haya carpeta elegida:
- **Todo el módulo y la barra de destino de abajo se ven apagados y no responden**: presets, opciones, listas, destino y botones de acción.
- **Solo quedan activas la barra de carpeta** (Elegir carpeta…, Recientes y arrastrar una carpeta encima) **y la barra lateral** para cambiar de módulo.
- **La barra de carpeta se resalta** con el borde rojo de la app y el texto «Empieza eligiendo o arrastrando una carpeta de fotos».
- En cuanto se elige carpeta, todo vuelve a la normalidad. Código QR y Shutter Count no usan carpeta y no cambian.
Confirmada por el usuario («si»).

### 2. Preguntas y respuestas
- **Además de deshabilitar el resto, ¿se resalta la barra de carpeta?** → Sí: borde rojo de la app y el texto «Empieza eligiendo o arrastrando una carpeta de fotos»; el resto de la pantalla, apagado y sin responder.
- **¿Qué se queda activo sin carpeta, además de la barra de carpeta y la lateral?** → Nada más: presets, opciones, destino y botones de acción, todo apagado hasta elegir carpeta.

### 4. Decisiones
- Plan aprobado («si»), con release y publicación (versión 3.8.1).
- Un solo sitio: `ContentView` calcula «falta la carpeta» (`usesSourceFolder` y sin `sourceFolder`) y pone `.disabled` y opacidad 0,45 al módulo y a la barra de destino. No hace falta tocar cada módulo.
- `caobaDropPanel(isTargeted:highlighted:)`: con `highlighted`, borde rojo de 2 puntos sin estar arrastrando. `SourceFolderBar` lo usa sin carpeta, con el texto en rojo «Empieza eligiendo o arrastrando una carpeta de fotos».
- Comprobado con capturas sin carpeta de Collage (oscuro y claro), Slideshow, Procesador y Metadatos; Código QR sin cambios; y Collage con carpeta, de vuelta a la normalidad.
- Versión 3.8.1.

### 3. Fuentes analizadas
- `CaobaApp/Sources/Views/ContentView.swift`, `CaobaApp/Sources/Views/Shared/SourceFolderBar.swift`, `Theme.swift` y `CaobaApp/Sources/Model/Module.swift` (`usesSourceFolder`).

### 5. Alternativas descartadas
- Solo deshabilitar, sin resaltar la barra de carpeta: descartado por el usuario.
- Dejar activos los presets sin carpeta: descartado por el usuario.

### 6. Pendiente de comprobar
- Los botones principales en rojo («Generar vídeo», «Escribir metadatos») siguen viéndose algo vivos aunque estén apagados, por su color de fondo; no responden.

## 2026-10-20 — Confirmación antes de «Reiniciar»

### 1. La petición tal como se ha entendido
*(sin preguntas: el código dice qué se borra)* El botón «Reiniciar» de la barra de carpeta borra sin preguntar lo guardado para la carpeta en su `.caoba`. Pasa a pedir confirmación con un mensaje que explique qué hace:
- **Título:** «¿Reiniciar la configuración de esta carpeta?».
- **Qué se borra:** todo el montaje del Slideshow (orden y selección de fotos, collages, encuadres, tarjetas de texto, pies, portada y créditos, música, marca de agua y ajustes del vídeo), los ajustes de «Componer» del Collage y el orden manual de las fotos.
- **Qué no se toca:** las fotos de la carpeta, los presets guardados de cada módulo y el historial del Renombrador (se puede seguir deshaciendo).
- **Botones:** «Reiniciar» (en rojo, porque no se puede deshacer) y «Cancelar».
Confirmada por el usuario («si»).

### 2. Preguntas y respuestas
Ninguna.

### 4. Decisiones
- Plan aprobado («dale»), con release y publicación (versión 3.8.2).
- `SourceFolderBar`: «Reiniciar» abre un `confirmationDialog` («Reiniciar» con `role: .destructive` y «Cancelar»); solo al confirmar se llama a `resetFolderConfig()`, que no cambia. Comprobado en el código que es el único sitio que la llama.
- El mensaje sale de lo que de verdad borra `CaobaConfig.resetSettings`: las secciones `slideshow`, `collage` y `fileOrder`; conserva `renameHistory`. Los presets de cada módulo no van en el `.caoba` de la carpeta, así que no se tocan.
- Traducciones al inglés del título y el mensaje. Corregida de paso en `documentacion.md` la lista de secciones del `.caoba` (decía solo `slideshow` y `renameHistory`).
- Versión 3.8.2.

### 3. Fuentes analizadas
- `CaobaApp/Sources/Views/Shared/SourceFolderBar.swift`, `AppState.resetFolderConfig`, `CaobaCore/Sources/CaobaCore/Config/CaobaConfig.swift` (`resetSettings`, `protectedSections`) y las secciones que escribe la app.

### 5. Alternativas descartadas
Ninguna.

### 6. Pendiente de comprobar
- La ventana de confirmación no sale en las capturas (ventana aparte); se comprobó en el código.

## 2026-10-20 — Landing: capturas nuevas y novedades

### 1. La petición tal como se ha entendido
El usuario ha cambiado las capturas de `assets/screenshots/` (mismos nombres, así que la página ya las usa). Falta contar en `index.html` lo que ha entrado desde la última vez que se tocó la landing (3.3.3), integrado en cada módulo y en «Por qué CAOBA», en español y en inglés y sin hablar de versiones:
- **Slideshow:**
  - Tarjetas de texto en cualquier punto del timeline, a pantalla propia o sobre la foto siguiente, cada una con su letra, posición, realce y animación de entrada y salida, y «Aplicar estilo a todas».
  - Pies de foto con patrón ({nombre}, {fecha}, {camara}…).
  - Editor de cada elemento al pulsarlo en el timeline.
  - Preescucha del tramo de cada pista.
  - Ficheros movidos (música, portada, créditos, marca) que se marcan y se localizan sin perder ajustes.
  - El vídeo guarda tu autor y una descripción.
- **Introducción de «Lo que hace»:** las fotos se ordenan arrastrando, y ese orden es el mismo en Slideshow, Collage y Contact Sheet.
- **Metadatos:** «Usar mi autor», con el autor puesto en Ajustes.
- **«Por qué CAOBA»:** en «Pensada para no perder nada», que «Reiniciar» avisa antes y que los ficheros movidos se recuperan; en «Rápida y ligera», que se actualiza desde la propia app.
- **Pie de la captura grande:** que diga lo que se ve ahora (un título, collages y dos pistas de música en el timeline).
Confirmada por el usuario («si»).

### 2. Preguntas y respuestas
- **¿Cómo se incluyen las novedades: dentro de cada módulo, una sección «Novedades» además, o solo la sección?** → Dentro de cada módulo (sobre todo Slideshow) y en «Por qué CAOBA», como funciones de la app y sin hablar de versiones.

### 4. Decisiones
- Plan aprobado («si»), con commit y push a `main` (que publica la landing en GitHub Pages); sin versión de la app.
- `index.html`, en español e inglés (79 textos de cada idioma, HTML bien formado):
  - Slideshow: viñeta nueva de títulos y textos (con estilo para todos y pies con patrón); la de Ken Burns pasa a «un clic abre su editor»; la de música suma la preescucha; viñeta nueva de ficheros movidos y autor del vídeo.
  - Introducción de «Lo que hace»: ordenar arrastrando, con el mismo orden en Slideshow, Collage y Contact Sheet.
  - Metadatos: autor de Ajustes con un clic.
  - «Por qué CAOBA»: «Reiniciar» avisa y los ficheros movidos se recuperan; se actualiza desde la propia app.
  - Pie y `alt` de la captura grande: un título, collages y dos pistas.
- Las capturas nuevas del usuario (mismos nombres, PNG y WebP, también `og`) entran en el mismo commit.
- Comprobado con una captura de la página hecha con WebKit (programa temporal, sin abrir el navegador): la tarjeta del Slideshow crece y deja algo de hueco bajo el texto del Collage, sin descuadrar nada; los recortes de las capturas nuevas encajan.
- Sin versión de la app: la landing se publica con el push a `main` (GitHub Pages).

### 3. Fuentes analizadas
- `index.html` (secciones Slideshow, «Lo que hace», Metadatos, «Por qué CAOBA» y pie de la captura grande) y `CHANGELOG.md` de la 3.3.0 a la 3.8.2.

### 5. Alternativas descartadas
- Sección «Novedades» aparte (con o sin actualizar los módulos): descartado por el usuario; la landing describe lo que hace la app, no su historial.

### 6. Pendiente de comprobar
- Cómo se ve en móvil (no se ha capturado a ese ancho).

## 2026-10-20 — Revisión: capturas de otras apps de collage (`collages/`)

### 1. La petición tal como se ha entendido
*(revisión, sin cambios de código)* Revisar las 46 capturas de `collages/` (tres apps de collage de iPhone) y hacer la lista de los diseños que no tiene CAOBA y lo que costaría añadir cada uno.

### 2. Preguntas y respuestas
- **¿Qué se hace con la revisión: lista de lo que falta, propuesta de qué añadir u otra cosa?** → La lista de lo que falta y lo que costaría.

### 3. Fuentes analizadas
- Capturas `collages/IMG_1057`–`IMG_1102`.
- `CaobaCore/Sources/CaobaCore/Collage/templates.json` (570 plantillas: 1–9 fotos, 84 superpuestas, 10 proporciones; tiras solo hasta 4 bandas; 9 fotos solo `grid_3x3`), `CollageTemplate.swift` (la celda es un rectángulo x, y, w, h), `CollageRenderer.swift` y los sitios que dibujan plantillas (`TemplateViews`, `CollageResultView`, editor de secuencia, timeline e inspector del Slideshow, `CollageSlideshow`).

### 4. Decisiones
- Lista entregada en el chat, en tres niveles de coste: solo catálogo (añadir plantillas al JSON), cambio pequeño del motor (círculo o elipse, giro, color de fondo) y cambio grande (polígonos y diagonales, curvas, formas, carrusel troceado, stickers).

### 5. Alternativas descartadas
Ninguna.

### 6. Pendiente de comprobar
- Qué se hace con la lista (el usuario decide).
- Aclaración del usuario: IMG_1073–IMG_1079 son carruseles para Instagram (N fotos que se suben juntas). Le gusta que las fotos de fondo ocupen más de una diapositiva y sigan en la siguiente. Visto en las capturas: un lienzo ancho con cortes marcados (3–6 diapositivas verticales), fotos de fondo que cruzan cortes y fotos encima con margen, algunas también a caballo de un corte. En CAOBA encajaría como plantillas superpuestas muy anchas, más proporciones de carrusel, guías de corte, exportación troceada en N JPG numerados y saber en «Componer» qué fotos van de fondo. Sin cambiar la forma de las celdas: coste medio-alto.
- El usuario descarta de la lista: bordes en onda o zigzag, formas (corazones, flores, puzle, nubes) y stickers y texto libre sobre el collage. Quedan: grupo 1 (tiras de 5–9 bandas, rejillas de 7–9 fotos, columna de tiras + foto grande, escalonadas, más superpuestas), grupo 2 (celda redonda u ovalada, fotos giradas, fondo de cualquier color) y del grupo 3 los cortes en diagonal y polígonos y el carrusel panorámico.
- Aclaración del usuario sobre la celda redonda: solo interesan las plantillas que **combinan un círculo con celdas de otro tipo** (por ejemplo, un círculo encima de una rejilla rectangular). Las ovaladas, no.
- Y el collage de un solo círculo también se queda. Celda redonda: plantillas de un solo círculo y plantillas que mezclan un círculo con celdas rectangulares; ovaladas, no.

## 2026-10-20 — Collage: plantillas nuevas (grupo de coste bajo)

### 1. La petición tal como se ha entendido
Se añaden al catálogo de plantillas (`templates.json`) los diseños del grupo de coste bajo de la revisión de `collages/`. Todos son rectángulos, así que no se toca el motor:
- **Tiras** de 5, 6, 7, 8 y 9 bandas, verticales y horizontales.
- **Rejillas de 7, 8 y 9 fotos** con celdas de varios tamaños (hoy 9 fotos solo tiene la 3×3).
- **Columna de 4 a 6 tiras finas junto a una foto grande**.
- **Celdas escalonadas** (filas o columnas desplazadas, tipo ladrillo).
- **Más variantes superpuestas** con marco (tarjetas sobre un fondo).

Cada diseño en 16:9, 9:16, 3:2, 2:3, 4:5, 5:4 y 1:1, salvo donde las celdas quedarían demasiado finas. Antes de añadir nada, el usuario ve una **hoja de muestras** con todos los diseños propuestos dibujados y elige cuáles entran. Los que entren aparecen solos en Collage, en el Slideshow, en Componer (que ya admite grupos de 7 a 9 fotos) y en los filtros por número de fotos y proporción.
Confirmada por el usuario («ok»).

### 2. Preguntas y respuestas
- **¿En qué proporciones se crea cada diseño nuevo?** → Las 6 principales (16:9, 9:16, 3:2, 2:3, 4:5, 5:4) y 1:1, como el resto del catálogo, salvo donde no tenga sentido (por ejemplo, tiras demasiado finas).
- **¿Se aprueban los diseños antes de entrar en el catálogo?** → Sí: hoja de muestras con todos los propuestos dibujados; el usuario elige cuáles entran.

### 4. Decisiones
- Plan aprobado («si»), con release y publicación (versión 3.9.0).
- Diseños generados con un script temporal (fuera del repo): 36 diseños en las 7 proporciones, descartando las variantes con celdas de menos del 8 % del lado o 8 veces más largas que anchas y las que ya existían en el catálogo. En 9:16, 4:5 y 2:3, «tiras + grande» pasa a foto grande arriba o abajo con las tiras al lado contrario. Identificadores y nombres en el estilo del catálogo (`16_9_strips_v9`, «Tiras 9 verticales 16:9»).
- Hoja de muestras HTML con cada diseño numerado y dibujado en sus proporciones; aprobados todos («todas ok»). Corregido antes de enseñarla: las superpuestas se dibujaban sin margen ni sombra.
- `templates.json`: 570 + 220 = 790 (112 superpuestas). Cada nueva va tras la última de su mismo número de fotos. Se mantiene el formato compacto en una sola línea (comprobado: reescribir el original daba los mismos bytes).
- Test `CollageTemplatesTests.catalog` actualizado (790 y 112) y ampliado: sin identificadores repetidos, tantas celdas como fotos, al menos 40 plantillas de 7, 8 y 9 fotos. Pasan los 130 tests.
- Comprobado: 10 plantillas nuevas dibujadas con el motor real (tiras, rejillas, ladrillo, escalera y superpuestas con marco y sombra) y captura del selector de Collage con «Fotos: 9». Nueva opción de prueba `collage.photos`.
- Número de plantillas actualizado en `documentacion.md`, `README.md` y la landing (la landing se publica con el push).
- Versión 3.9.0.

### 3. Fuentes analizadas
- `CaobaCore/Sources/CaobaCore/Collage/templates.json`, `CollageTemplate.swift`, `ContentComposer.swift` (forma grupos según las plantillas que haya, sin tope propio de tamaño), `CaobaCore/Tests/CaobaCoreTests/CollageTests.swift` y `CollageView.swift`.

### 5. Alternativas descartadas
- Solo 6 proporciones, o solo 1:1 y 4:5: descartado por el usuario.
- Añadirlas sin revisar: descartado por el usuario.

### 6. Pendiente de comprobar
- Con 9 fotos por grupo, «Componer según el contenido» reparte las fotos con el método rápido (a partir de 6 fotos no prueba todas las combinaciones); no se ha medido cuánto tarda con carpetas grandes.
- La carpeta `collages/` (capturas de otras apps, solo de referencia) se ignora en git a petición del usuario, para no publicarla; el script de release exige el árbol limpio.

## 2026-10-20 — Fondo de cualquier color (grupo de coste medio, 1 de 3)

*(El grupo de coste medio se hace en tres peticiones seguidas, a elección del usuario: fondo de color, celda redonda y fotos giradas.)*

### 1. La petición tal como se ha entendido
En **Collage**, en los **collages del Slideshow** (pestaña Vídeo, modo collages) y en **Contact Sheet**, el selector de fondo pasa a ofrecer **Blanco, Negro, Gris y «Personalizado»**:
- Con «Personalizado», al lado aparece el selector de color de macOS, sin transparencia.
- El color del texto (título, nombres de archivo, numeración) y el del borde se eligen solos según lo claro u oscuro que sea el fondo, como hoy con los tres de siempre.
- El color se guarda donde ya se guarda el fondo: presets de Collage y Contact Sheet y proyecto del Slideshow. Los presets y proyectos antiguos se siguen leyendo igual.
- Las tarjetas de texto del Slideshow siguen con Negro, Blanco y Gris.
Confirmada por el usuario («si»).

### 2. Preguntas y respuestas
- **¿Las tres cosas del grupo una a una o juntas?** → Una a una, cada una con su versión: primero el fondo de color, luego la celda redonda y por último las fotos giradas.
- **¿Dónde se elige el color libre: Collage, collages del Slideshow y Contact Sheet; también tarjetas de texto; o solo Collage y Slideshow?** → Collage, collages del Slideshow y Contact Sheet. Las tarjetas de texto siguen con Negro, Blanco y Gris.
- **¿Cómo se elige: Blanco/Negro/Gris + «Personalizado», o solo un selector de color?** → Se quedan Blanco, Negro y Gris y se añade «Personalizado», con el selector de color de macOS al lado. Texto y borde se ajustan solos al color (claros sobre fondo oscuro, oscuros sobre claro).

### 4. Decisiones
- Plan aprobado («si»), con release y publicación (versión 3.9.1). Contact Sheet no tiene presets: su color dura lo que el resto de sus ajustes (la sesión).
- Motor: `CanvasColor` (`.preset(CanvasBackground)` o `.custom(RGBColor)`), con `fill`, `text`, `border`, `isDark` (luminancia relativa < 0,5) y `rawValue` («white» o «#RRGGBB»); se codifica como una cadena, así los presets de Collage (`CollageSettings.background`) y los proyectos del Slideshow (`collage.bgColor`) antiguos se leen igual. `CollageOptions` y `ContactSheetOptions` pasan a `CanvasColor`; las tarjetas de texto siguen con `CanvasBackground`. `RGBColor` pasa a `Hashable`.
- Fallo encontrado al probar: el color propio salía más claro (0,5 daba 145 en vez de 128) porque `CGColor(red:green:blue:)` es RGB genérico y se convierte a sRGB al dibujar; el selector de macOS trabaja en sRGB. Se crea con `CGColor(srgbRed:…)`. El «Gris» de siempre tiene el mismo efecto (sale 146) y no se ha tocado para no cambiar los collages existentes.
- App: `BackgroundPicker` (desplegable + `ColorPicker` sin transparencia; al pasar a «Personalizado» parte del color que hubiera) en Collage, Contact Sheet y la pestaña Vídeo del Slideshow en modo collages.
- Tests nuevos (suite `CanvasColor`): leer y guardar «white» y «#336699», rechazar valores no válidos, contraste del texto, y collage y hoja de contacto con fondo `#008080` que sale tal cual (±1). Pasan los 133 tests.
- Comprobado en la app: proyecto del Slideshow con `#1E3A5F`; la pestaña Vídeo enseña «Personalizado» con el color, el proyecto lo conserva y el vídeo generado tiene el fondo (29, 57, 95), dentro del redondeo del vídeo.
- Versión 3.9.1.

### 3. Fuentes analizadas
- `CaobaCore/Sources/CaobaCore/Drawing/Drawing.swift` (`CanvasBackground`), `CollageRenderer.swift`, `ContactSheetRenderer.swift`, `QR/QRGenerator.swift` (`RGBColor`), `CaobaApp/Sources/Model/ModulePresets.swift`, `SlideshowDocument.swift`, `CollageView.swift`, `ContactSheetView.swift` y `SlideshowInspector.swift`.

### 5. Alternativas descartadas
- Solo el selector de color (sin Blanco, Negro y Gris): descartado por el usuario.
- Color libre también en las tarjetas de texto: descartado por el usuario.
- Corregir de paso el «Gris» a sRGB: cambiaría los collages ya hechos; no estaba en la petición.

### 6. Pendiente de comprobar
- Contact Sheet no tiene presets: su color dura lo que el resto de sus ajustes (la sesión).
- El selector de color y el desplegable de Collage y Contact Sheet se han revisado en el código; la captura es de la pestaña Vídeo del Slideshow.

## 2026-10-20 — Celda redonda (grupo de coste medio, 2 de 3)

### 1. La petición tal como se ha entendido
Las plantillas de collage pueden tener **celdas redondas**:
- **Plantilla de un solo círculo:** una foto recortada en redondo sobre el fondo.
- **Círculo encima de una rejilla de rectángulos** (en el centro o en otra posición), tapando parte de las fotos de debajo, con un **aro del color del fondo** alrededor para separarlo. El aro sigue la «Separación» del collage.
- **Círculo perfecto** en cualquier proporción del collage. Nada de óvalos.
- Las redondas son un **tipo propio, «Redondas»**, que sale en **Collage y en el Slideshow** (no como las superpuestas, que solo salen en el Slideshow), con su opción en el filtro de tipo.
- En todos los sitios que dibujan plantillas (selector, resultado, editor de encuadre, timeline, collages del vídeo), la foto del círculo se recorta en redondo y su encuadre se sigue arrastrando igual.
- **Antes de añadir nada,** el usuario ve una hoja de muestras con los diseños propuestos y elige cuáles entran.
Confirmada por el usuario («si»).

### 2. Preguntas y respuestas
- **¿Cómo es el círculo combinado con rectángulos: encima con aro, en su propio hueco o los dos?** → Encima de la rejilla (por ejemplo, en el centro de una 2×2), tapando parte de las fotos, con un aro del color del fondo alrededor.
- **Las superpuestas solo salen en el Slideshow: ¿dónde salen las redondas?** → En Collage y en el Slideshow, como un tipo propio («Redondas») con su filtro, aunque el círculo vaya encima de otras fotos.
- **¿Hoja de muestras antes de añadir los diseños redondos?** → Sí: unos 10–15 diseños dibujados en sus proporciones; el usuario elige.

### 4. Decisiones
- Plan aprobado («dale»), con release y publicación (versión 3.10.0).
- Modelo: `CollageCell.shape` opcional (`circle`), `isCircle`, `CollageTemplate.isRound`, `TemplateType.round` y `CollageTemplates.type(of:)`. `filter` saca las redondas aunque no se pidan superpuestas (van en Collage) y `.basic` ya no las incluye. Las 860 plantillas se leen; las antiguas no llevan `shape`.
- Motor: el círculo va en el cuadrado centrado dentro de su celda (perfecto aunque el título cambie el alto), con un aro del color del fondo (`ringWidth`: la separación, mínimo 4 px o 0,6 % del lado menor) y la foto recortada en elipse. Se dibuja el último (en el catálogo, la celda redonda va al final).
- App: `TemplateView` recorta en círculo con aro (`ringColor`, por defecto el fondo de los controles); el selector «Tipo» sale siempre (Básicas, Superpuestas solo en el Slideshow, Redondas), también en «Aleatorias» de Collage (`typeFilter`). Arreglado el filtro de «Añadir collage» del Slideshow, que comparaba solo superpuestas sí o no. Nueva prueba `collage.type`.
- Diseños: 10 diseños × 7 proporciones = 70, propuestos con un script temporal y enseñados en una hoja de muestras dibujada con el motor real (esta vez no con un dibujo aproximado). Aprobados todos («ok»). En vertical, los diseños de columnas pasan a filas.
- Tests: suite «Collage redondo» (el centro del círculo es la foto del círculo, la esquina de su cuadro la de debajo y justo fuera el aro blanco) y en `CollageTemplatesTests`: las antiguas sin forma, el círculo cuadrado en píxeles (±2) en las 70 y el último de su plantilla, y las cuentas (860; 70 redondas). Pasan los 135 tests.
- Comprobado en la app: selector de Collage con «Redondas», editor de un collage redondo del Slideshow (círculo con aro en el editor y en el timeline) y vídeo generado con la foto central en redondo.
- Número de plantillas actualizado en `documentacion.md`, `README.md` y la landing.
- Versión 3.10.0.

### 3. Fuentes analizadas
- `CaobaCore/Sources/CaobaCore/Collage/CollageTemplate.swift`, `CollageRenderer.swift` (`cellRect`, dibujo de celdas), `Drawing.swift`, `templates.json`; `CaobaApp/Sources/Views/Shared/TemplateViews.swift` (`TemplateView`, `TemplateFilters`), `CollageView.swift`, `CollageSequenceEditor.swift`, `SlideshowView.swift` (hoja «Añadir collage»).

### 5. Alternativas descartadas
- Círculo en su propio hueco (sin tapar nada), o los dos tipos: descartado por el usuario.
- Redondas solo en el Slideshow, como las superpuestas: descartado por el usuario.
- Óvalos: descartados por el usuario.

### 6. Pendiente de comprobar
- En el selector y el editor, el aro usa el color de fondo de los controles (no el del collage); en el resultado y el vídeo usa el del fondo del collage. Con fondos de collage muy distintos al de la ventana, el aro del editor no coincide con el final.

## 2026-10-21 — Fotos giradas (grupo de coste medio, 3 de 3)

### 1. La petición tal como se ha entendido
Las plantillas de collage podrán tener **fotos giradas**, en dos estilos:
- **Tarjetas:** fotos sueltas con marco blanco y sombra, algo giradas (de unos 3 a 12 grados) y montadas unas sobre otras sobre el fondo, como fotos impresas.
- **Rejilla girada:** celdas de una rejilla normal, sin marco, cada una algo girada, dejando huecos del color del fondo.

Además:
- Serán un **tipo propio, «Giradas»**, en el filtro «Tipo», que sale **en Collage y en el Slideshow** (también las de marco y sombra).
- **En el editor de encuadre**, la celda se ve girada como en el resultado, y al arrastrar la foto se mueve en la dirección de la propia foto. Lo mismo en el selector, el timeline y el resultado, y en el vídeo la foto sale girada igual.
- **Antes de añadir nada,** el usuario ve una hoja de muestras dibujada con el motor real y elige cuáles entran.
Confirmada por el usuario («si»).

### 2. Preguntas y respuestas
- **¿Qué estilo: tarjetas con marco y sombra, rejilla con celdas giradas sin marco o las dos?** → Las dos.
- **¿Dónde salen: Collage y Slideshow como tipo «Giradas», o como las superpuestas?** → Tipo propio «Giradas» en el filtro «Tipo», en Collage y en el Slideshow (también las de marco y sombra).
- **En el editor de encuadre, ¿la foto girada se arrastra siguiendo la foto o se ve recta?** → Se ve girada, como en el resultado, y arrastrar la mueve en la dirección de la propia foto.
- **¿Hoja de muestras antes de añadirlas?** → Sí, dibujada con el motor real: unos 10–12 diseños en sus proporciones; el usuario elige.

### 4. Decisiones
- Plan aprobado («dale»), con release y publicación (versión 3.11.0).
- Modelo: `CollageCell.rotation` (grados) y `angle`; `CollageTemplate.isRotated`; `TemplateType.rotated`, que manda en `type(of:)`; `filter` saca las giradas siempre, aunque sean `overlap`. El estilo lo decide `overlap`: tarjetas con marco y sombra o rejilla girada sin marco.
- Motor: el contexto se gira alrededor del centro de la celda antes de dibujarla (marco, sombra y foto); el encuadre se calcula sobre la celda sin girar.
- App: `TemplateView` aplica `rotationEffect`. El arrastre del encuadre se mide en coordenadas de la ventana y se gira al revés que la celda (`CellPhotoView(rotation:)`), en vez de fiarse de cómo pasa SwiftUI los gestos por un `rotationEffect`. Filtro «Tipo» con «Giradas».
- Diseños: 11 × 7 = 77 (49 tarjetas, 28 rejilla girada), propuestos con un script temporal que encoge cada diseño lo justo para que ninguna celda girada se salga del lienzo, y enseñados en una hoja dibujada con el motor. Aprobados todos («todo»).
- Tests: suite «Collage girado» (centro con la foto, hueco del giro con el fondo, y un punto que solo cae dentro si el giro es a la derecha) y en `CollageTemplatesTests`: antiguas sin giro, ninguna celda girada fuera del lienzo y cuentas (937; 77 giradas; 161 con marco). Corregido el test que suponía que sin superpuestas no salía ninguna plantilla con marco. Pasan los 137 tests.
- Comprobado en la app: selector de Collage con «Giradas», editor del Slideshow con tarjetas giradas (también en el timeline) y vídeo generado con las tarjetas giradas.
- Número de plantillas actualizado en `documentacion.md`, `README.md` y la landing.
- Versión 3.11.0. Con esto se cierra el grupo de coste medio.

### 3. Fuentes analizadas
- `CaobaCore/Sources/CaobaCore/Collage/CollageTemplate.swift`, `CollageRenderer.swift` (`drawFramedPhoto`, dibujo de celdas), `templates.json` («Disperso» y «Pila», rectos); `CaobaApp/Sources/Views/Shared/TemplateViews.swift` (`TemplateView`, `CellPhotoView`, `TemplateFilters`).

### 5. Alternativas descartadas
- Solo tarjetas o solo rejilla girada: el usuario quiso las dos.
- Giradas como las superpuestas (solo en el Slideshow): descartado por el usuario.
- Celdas rectas en el editor y giro solo en el resultado: descartado por el usuario.

### 6. Pendiente de comprobar
- El arrastre del encuadre en una celda girada con el ratón de verdad (no se puede simular desde aquí); la cuenta del giro se revisó en el código.
- La sombra de las tarjetas gira con la tarjeta (en una foto real la sombra iría siempre hacia el mismo lado); con giros pequeños apenas se nota.

## 2026-10-21 — Carrusel de Instagram

### 1. La petición tal como se ha entendido
Una forma nueva de hacer collages para **publicaciones en carrusel de Instagram**: un collage muy ancho que se corta en N diapositivas y se sube junto.
- **Dónde:** dentro de **Collage**, como tercera opción de «Plantillas» (Secuencia, Aleatorias, **Carrusel**). Reutiliza la lista de fotos, el editor de encuadre, el fondo (también el personalizado), la separación, las esquinas, la sombra y la salida.
- **Formato de diapositiva,** a elegir: **4:5** (1080×1350), **1:1** (1080×1080) o **3:4** (1080×1440).
- **Montaje:** el carrusel se forma **encadenando tramos** de un catálogo propio. Cada tramo ocupa 1, 2 o 3 diapositivas y puede tener **fotos de fondo que cruzan los cortes** y fotos encima, alguna también a caballo de un corte. Los tramos se añaden, se cambian, se quitan y se reordenan, hasta **10 diapositivas** (el máximo de Instagram). Además, **«Componer»** lo monta solo con las fotos marcadas.
- **Vista:** la tira completa con las **líneas de corte** marcadas y el número de cada diapositiva; el encuadre de cada foto se arrastra como en las demás plantillas.
- **Exportar:** una carpeta con **una imagen por diapositiva** numerada en el orden de subida (01.jpg, 02.jpg…) y además **la panorámica completa**.
- **Antes de añadir los tramos,** el usuario ve una **hoja de muestras** dibujada con el motor, con los cortes marcados, y elige cuáles entran.
Confirmada por el usuario («si»).

### 2. Preguntas y respuestas
- **¿Con cuál de los dos de coste alto se empieza: carrusel o diagonales y polígonos?** → Carrusel de Instagram.
- **¿Dónde va: dentro de Collage o como módulo nuevo?** → Dentro de Collage, como tercera opción de «Plantillas» (Secuencia, Aleatorias, Carrusel), reutilizando lista de fotos, editor de encuadre, fondo, separación y salida.
- **¿Formato de cada diapositiva?** → A elegir entre 4:5 (1080×1350), 1:1 (1080×1080) y 3:4 (1080×1440).
- **¿Cómo se monta: encadenando tramos o con plantillas completas cerradas?** → Encadenando tramos de un catálogo de diseños de carrusel (de 1 a 3 diapositivas de ancho, con fotos de fondo que cruzan los cortes y fotos encima) hasta 10 diapositivas, y «Componer» para que lo monte solo con las fotos marcadas.
- **¿Qué se exporta?** → Una carpeta con una imagen por diapositiva numerada en el orden de subida (01.jpg, 02.jpg…) y además la panorámica completa.
- **¿Hoja de muestras de los tramos antes de añadirlos?** → Sí, dibujada con el motor, con las líneas de corte marcadas; el usuario elige.
- Tramos de carrusel: 15 primeros aprobados («esas estan bien»); el usuario pidió además diseños como los de IMG_1073–1078 y franjas verticales. Se propusieron 11 más (16–26, fotos encima sin marco como en las capturas); descartados el 22 y el 23 («se pueden generar como diapositivas sueltas»: las franjas caen justo en los cortes). Catálogo final: 24 tramos × 3 formatos.
- Petición añadida a mitad de trabajo: más combinaciones de franjas y bloques de al menos 4 o 5 diapositivas, incluidas franjas horizontales que ocupen todo el ancho de la diapositiva. Se proponen 6 tramos más (27–32) en otra hoja.

### 4. Decisiones
- Plan aprobado («dale»), todo seguido; con release y publicación (versión 3.12.0). Tramos 25–30 aprobados («todo ok»): catálogo final de 30 tramos × 3 formatos.
- Motor (`Collage/Carousel.swift`): `CarouselFormat`, `CarouselTemplates` (catálogo `carousel_templates.json` sin formato, ofrecido en los tres; ids `carousel_<formato>_<id>`, fuera de los selectores de collage pero encontrables con `CollageTemplates.template(id:)`), `Carousel.combine`, `renderPanorama`, `slices`, `limited` y `generate` (subcarpeta `carrusel`, `carrusel_2`…; `01…NN.jpg` y `panoramica.jpg`). Nuevos `CollageCell.framed` (marco por celda, para mezclar fondo sin marco y fotos encima con marco) y `CollageTemplate.slides`.
- Cada tramo es una plantilla normal: se reutilizan la secuencia (`SequenceItem`), Componer (`CollageRenderer.group` y `ContentComposition`, recortados a 10 diapositivas) y el motor de dibujo. La panorámica se dibuja entera y se corta, así las fotos que cruzan un corte siguen sin salto.
- App: `CollageMode` (secuencia, aleatorias, carrusel) y `CarouselEditor`. Ajustes del carrusel guardados por carpeta en `CollageFolderSettings.carousel` (`CarouselSettings`); la secuencia no se guarda, como la del Collage.
- Fallo encontrado al probar: «Resultado» salía desplazado respecto a los cortes por el margen y la sombra de `CollageResultView`; nuevo parámetro `framed` (a sangre en el carrusel).
- Tests nuevos (suite «Carrusel»): catálogo (30 × 3, celdas dentro, ids encontrables y separados de las plantillas de collage), tamaños exactos en los tres formatos, continuidad de una foto al cruzar un corte (degradado), tope de 10 y escritura de `01…NN` + panorámica sin pisar una carpeta anterior. Pasan los 141 tests.
- Comprobado en la app: modo Carrusel con Componer (tira con cortes y números; «Resultado» alineado) y «Generar» de punta a punta: 8 diapositivas de 1080×1350 y panorámica de 8640×1350.
- Opciones de prueba nuevas: `collage.tab=carousel`, `carousel.compose=1`, `carousel.result=1`, `collage.run=1`.

### 3. Fuentes analizadas
- Capturas `collages/IMG_1073`–`IMG_1078`; `CaobaApp/Sources/Views/Modules/CollageView.swift`, `CollageSequenceEditor.swift`, `CollageResultView.swift`, `ContentComposition.swift`; `CaobaCore/Sources/CaobaCore/Collage/CollageRenderer.swift`, `CollageTemplate.swift`, `Config/ComposeSettings.swift`.

### 5. Alternativas descartadas
- Módulo nuevo «Carrusel»: descartado por el usuario (va dentro de Collage).
- Plantillas de carrusel completas y cerradas: descartado por el usuario (se encadenan tramos).
- Solo las diapositivas sin la panorámica: descartado por el usuario.
- Los tramos 22 y 23 (franjas que caen justo en los cortes): descartados por el usuario.
- Meter los tramos en `templates.json`: se mezclarían con las plantillas de collage en todos los selectores.

### 6. Pendiente de comprobar
- El arrastre del encuadre sobre la tira con el ratón de verdad.
- «Componer según el contenido» con tramos anchos: puntúa igual que con collages (proporción de celda y sujeto); no se ha evaluado con fotos reales.

## 2026-10-21 — Cortes en diagonal y polígonos

### 1. La petición tal como se ha entendido
Las plantillas de collage podrán tener **celdas con forma de polígono** (cada una definida por sus esquinas), en tres familias:
- **Cortes inclinados:** rejillas de 2 a 5 fotos con líneas que no son horizontales ni verticales (diagonal completa, cortes en ángulo, «Y» de tres piezas…).
- **Abanicos:** triángulos que salen de una esquina o del centro (3 a 6 fotos).
- **Figura central:** un rombo o un hexágono en el centro, con 4 o 6 piezas alrededor.

Además:
- **Separación real:** cada pieza se encoge hacia dentro, de modo que el hueco entre fotos mide lo mismo que la «Separación» en todas las direcciones y deja ver el fondo, también el de color. En los bordes del lienzo, igual que en las demás plantillas.
- Serán un **tipo propio, «Diagonales»**, en el filtro «Tipo», en **Collage y en el Slideshow**.
- La foto se recorta con la forma de su pieza en todos los sitios: selector, editor de encuadre, timeline, resultado y vídeo. El encuadre se sigue arrastrando igual.
- **Antes de añadir nada,** el usuario ve una hoja de muestras dibujada con el motor y elige cuáles entran.
Confirmada por el usuario («si»).

### 2. Preguntas y respuestas
- **¿Qué familias: cortes inclinados, abanicos, figura central?** → Las tres.
- **¿Separación real (cada pieza encoge hacia dentro) o líneas pintadas encima?** → Separación real: el hueco mide la «Separación» en todas las direcciones y deja ver el fondo.
- **¿Dónde salen?** → En Collage y en el Slideshow, como tipo propio «Diagonales» en el filtro «Tipo».
- **¿Hoja de muestras antes de añadirlas?** → Sí, dibujada con el motor: unos 15–18 diseños de las tres familias en sus proporciones.

### 4. Decisiones
- Plan aprobado («dale»), con release y publicación (versión 3.13.0).
- Modelo: `CollageCell.points` y `polygon`; la caja (`x, y, w, h`) contiene la pieza, así el resto del código no cambia. `CollageTemplate.isPolygon`, `TemplateType.polygon`.
- Motor: `polygonInPixels` e `insetPolygon` (cada lado desplazado la mitad de la separación, o entera por el borde; esquinas = cruce de lados desplazados) y `drawPolygonPhoto` (encuadre sobre la caja encogida, recorte con la forma). Solo piezas convexas, para que la cuenta sea exacta.
- App: `PolygonShape` en `TemplateView` y «Diagonales» en el filtro «Tipo».
- Diseños: 16 × 7 = 112 (8 cortes inclinados, 5 abanicos, 3 figura central), propuestos con un script que comprueba que cada pieza es convexa y que cubren el lienzo sin huecos ni solapes, y enseñados en una hoja dibujada con el motor. Aprobados todos («todas ok»), también en las proporciones verticales.
- Tests: suite «Collage en polígonos» (en `poly_diag_2` con separación 40, el blanco a lo largo de la perpendicular a la diagonal mide 40 ± 3 px; cada triángulo con su foto; encoger un cuadrado da el cuadrado centrado) y en `CollageTemplatesTests`: antiguas sin polígono, cada pieza convexa y dentro de su caja, y que entre todas cubren el lienzo (área 1). Pasan los 144 tests.
- Comprobado en la app: selector de Collage con «Diagonales», editor del Slideshow con «Hexágono + 6» (también en el timeline) y vídeo generado.
- Número de plantillas actualizado en `documentacion.md`, `README.md` y la landing.
- Versión 3.13.0. Con esto se cierra la lista de la revisión de `collages/`.

### 3. Fuentes analizadas
- Capturas `collages/IMG_1066`, `IMG_1081`, `IMG_1083`, `IMG_1085`; `CaobaCore/Sources/CaobaCore/Collage/CollageTemplate.swift`, `CollageRenderer.swift`; `CaobaApp/Sources/Views/Shared/TemplateViews.swift`.

### 5. Alternativas descartadas
- Líneas del color del fondo pintadas encima (fotos tocándose): descartado por el usuario; las esquinas donde se cruzan las líneas quedan peor y no deja ver un fondo de color de forma limpia.
- Mezclarlas con las Básicas: descartado por el usuario.
- Piezas no convexas: el encogido por lados ya no es exacto; ninguno de los diseños las necesita.

### 6. Pendiente de comprobar
- Las esquinas redondeadas («Esquinas») no se aplican a las piezas en polígono.
- En vertical, los cortes verticales dejan piezas estrechas (el usuario las aceptó así).

## 2026-10-21 — Componer usaba plantillas marcadas que no se ven

### 1. La petición tal como se ha entendido
*(arreglo de un fallo)* El usuario marca una sola plantilla en «Componer secuencia» (filtros: 3 fotos, Diagonales) y salen collages que no tienen que ver. Causa: el proyecto guardaba 225 plantillas marcadas de otras veces; la hoja solo enseña las que pasan los filtros, pero Componer usa todas las marcadas, también las ocultas. Arreglo elegido: seguir usando todas las marcadas (así se pueden elegir de varios filtros), pero **avisar** de cuántas hay ocultas por los filtros y poder **desmarcarlas** de un clic. Vale para las tres listas con filtros y casillas: Componer del Collage, «Aleatorias» del Collage y Componer del Slideshow. El Componer del carrusel no tiene filtros y no lo necesita.
Confirmada por el usuario al elegir el arreglo.

### 2. Preguntas y respuestas
- **¿Componer solo con las visibles, o avisar de las ocultas y poder quitarlas?** → Avisar de las ocultas y poder desmarcarlas; se siguen usando todas las marcadas.

### 3. Fuentes analizadas
- `.caoba` de la carpeta del usuario (solo lectura): 225 plantillas en `collage.compose.selectedTemplates`, filtros 3 fotos y `polygon`.
- `CaobaApp/Sources/Views/Shared/CollageSequenceEditor.swift` (hoja Componer), `CollageView.swift` («Aleatorias»), `Slideshow/SlideshowView.swift` (`TemplatePickerSheet`).

### 4. Decisiones
- Plan aprobado («si»), con release y publicación (versión 3.13.1).
- `HiddenSelectionNotice` en `TemplateViews.swift`, junto a «Todas las visibles» en las tres listas (sustituye al «N plantillas elegidas» de «Aleatorias»). «Desmarcar las ocultas» quita solo las marcadas que no pasan los filtros.
- Comprobado con una carpeta de prueba con 8 plantillas marcadas de varios tipos y los filtros «3 fotos · Diagonales»: la hoja de Componer muestra «8 elegidas · 6 ocultas por los filtros» y el botón. El botón es una resta de conjuntos y no se ha pulsado en la prueba.
- Versión 3.13.1.

### 5. Alternativas descartadas
- Componer solo con las visibles: descartado por el usuario; impediría elegir plantillas de varios filtros para un mismo Componer.

### 6. Pendiente de comprobar
- La carpeta del usuario sigue con sus 225 marcadas: verá el aviso y podrá desmarcar las ocultas.

## 2026-10-21 — La hoja «Componer secuencia» se sale por los lados

### 1. La petición tal como se ha entendido
*(arreglo de un fallo)* En el Slideshow, la hoja «Componer secuencia» se ve cortada: las etiquetas de la izquierda («rto», «rción»…) y la opción «Diagonales» de la derecha no caben. Causa: el filtro «Tipo» son seis botones seguidos que, sumados a la columna de etiquetas, miden más que los 720 pt de la hoja; SwiftUI centra el contenido y lo recorta por los dos lados. Arreglo: «Tipo» pasa a ser un desplegable, como «Fotos» y «Proporción».
Confirmada por el usuario al aprobar el plan.

### 2. Preguntas y respuestas
- Ninguna: el usuario aprobó directamente el plan propuesto («si»). Además pidió no hacer commit hasta que lo indique.

### 3. Fuentes analizadas
- `CaobaApp/Sources/Views/Shared/TemplateViews.swift` (`TemplateFilters`).
- Hojas que lo usan: `Slideshow/SlideshowView.swift` (`TemplatePickerSheet`), `Shared/CollageSequenceEditor.swift` (Componer y Añadir), `CollageView.swift` («Aleatorias»).

### 4. Decisiones
- «Tipo» como desplegable de hasta 220 pt, alineado a la izquierda. Al estar en `TemplateFilters`, el arreglo llega a todas las hojas de elegir plantillas.
- Comprobado con capturas: Componer del Slideshow en oscuro y Componer del Collage en claro (con «Diagonales» elegido); todo cabe y queda alineado.
- Sin commit ni versión nueva: el cambio queda en el árbol de trabajo y en el CHANGELOG bajo «Sin publicar».

### 5. Alternativas descartadas
- Ensanchar la hoja: con cada tipo nuevo volvería a pasar, y en pantallas pequeñas no hay sitio.
- Botones en dos filas o con textos más cortos: más frágil y se lee peor que un desplegable, que ya es lo que usan los otros filtros.

### 6. Pendiente de comprobar
- Nada.

## 2026-10-21 — Previsualización en la pantalla de Collage

### 1. La petición tal como se ha entendido
En la pantalla de Collage, la columna derecha se divide en dos: arriba la lista de fotos y abajo una **previsualización de toda la secuencia**, con un divisor que se arrastra (empieza mitad y mitad).
- **Qué se ve**: los collages dibujados con el motor real y las opciones de Salida y Logo (fondo, separación, esquinas, título, logo), en una **tira horizontal** con scroll y numerados. Se vuelven a dibujar al cambiar esas opciones o la secuencia.
- **Secuencia**: los collages de la secuencia. Pulsar uno abre el editor de enfoque.
- **Aleatorias**: se sortea un reparto con las plantillas marcadas y ese reparto es **el que usa Generar** (ya no sortea por su cuenta). Hay un botón «Otro reparto» para volver a sortear; también se vuelve a sortear solo al cambiar las fotos o las plantillas marcadas (perdiendo los encuadres retocados). El «Enfoque» (Centro / Automático / Caras) se aplica al sortear. Pulsar un collage abre el editor de enfoque. Como la secuencia, no se guarda en el `.caoba`.
- **Carrusel**: la tira con las diapositivas y sus cortes, con el resultado real. Se quita el conmutador «Encuadre / Resultado» de su panel, que queda solo para encuadrar.
- **Además**: la columna izquierda deja de cortarse por la derecha (valores de los deslizadores y botón «Generar» siempre visibles).
Confirmada por el usuario («dale»).

### 2. Preguntas y respuestas
- **¿Qué enseña la previsualización bajo la lista de fotos: el collage seleccionado, la secuencia completa o la foto seleccionada?** → La secuencia completa.
- **En «Aleatorias» (sin secuencia fija), ¿qué enseña: un reparto de muestra orientativo, el reparto que luego se usa al generar, o nada?** → Usar el reparto que se ve: Generar usa exactamente el reparto mostrado.
- **¿Render real con las opciones de Salida y Logo, o esquema rápido de plantillas?** → Render real.
- **¿Cómo se reparte la columna derecha: divisor ajustable, mitad fija o plegable?** → Divisor ajustable, empezando mitad y mitad.
- **¿Rejilla con scroll vertical, uno debajo de otro o tira horizontal?** → Tira horizontal.
- **En el carrusel, ¿quitar el conmutador «Encuadre / Resultado» o dejarlo?** → Quitar «Resultado»: el panel del carrusel queda para encuadrar y el resultado se ve en la previsualización.
- **¿Pulsar un collage de la previsualización abre el editor de enfoque o es solo para mirar?** → Abre el editor de enfoque (también en Aleatorias; en el carrusel se encuadra en su panel).
- **La columna izquierda se corta por la derecha («10 px», «90», «Generar»): ¿se arregla en este cambio?** → Sí, en este cambio.

### 3. Fuentes analizadas
- `CaobaApp/Sources/Views/Modules/CollageView.swift` (`HSplitView` con opciones a la izquierda y `FileListView` a la derecha).
- `CaobaApp/Sources/Views/Modules/CarouselEditor.swift` y `Shared/CollageResultView.swift` (vista «Resultado» ya existente).
- `CaobaCore/Sources/CaobaCore/Collage/CollageRenderer.swift` (`CollageOptions`, `group`: las fotos de cada collage van seguidas, así que el reparto se puede guardar como secuencia).
- `Shared/FileListView.swift` (cabecera con «Orden» y «Orientación», que fija el ancho mínimo de la lista).

### 4. Decisiones
- Plan aprobado («dale»). Sin commit ni versión: queda en el árbol de trabajo y en el CHANGELOG bajo «Sin publicar».
- Vista nueva `CollagePreview` (`Shared/CollagePreview.swift`): tira horizontal, un `CollageResultView` por collage a 900 px de lado mayor, para que al tocar un collage solo se redibuje ese. Carrusel: la tira entera con las opciones reales del carrusel (1080 px por diapositiva, sin título), a 500 px por diapositiva.
- `CollageOptions.scaled(toLongestSide:)` en el motor: al dibujar pequeño, separación y esquinas bajan en proporción. Antes la vista «Resultado» del editor de foco los dejaba en píxeles de la salida y salían más gruesos; ahora se ve igual que el fichero (afecta también al editor de foco y al inspector del Slideshow, para bien). Sustituye al `gap / 3` a ojo del carrusel. Test nuevo.
- Columna derecha con `VSplitView` (lista arriba, previsualización abajo, 400 pt ideales cada una, mínimo 180).
- Aleatorias: `randomSequence` en `CollageView`. Se sortea al entrar, al cambiar fotos, plantillas marcadas o «Enfoque», y con «Otro reparto» (en la fila de «Enfoque»). Los focos se calculan después en segundo plano; Generar se desactiva hasta que acaban, para que salga lo que se ve. Si mientras tanto se retoca un encuadre a mano, se respeta. En otros modos el reparto se tira y se sortea al volver.
- El editor de enfoque se abre desde la previsualización con una hoja propia de `CollageView` (sobre `sequence` o `randomSequence`).
- Carrusel: fuera el conmutador «Encuadre / Resultado», el texto de «Resultado» y el `carousel.result` de pruebas. Las líneas de corte pasan a `CarouselCuts`, compartido. El formato pasa a desplegable: como botones (más la etiqueta) medía unos 530 pt.
- Recorte de la columna izquierda: venía de controles que no encogen (el formato del carrusel y el conmutador). Además el mínimo de la columna sube de 360 a 400 pt. Con 420 la lista de fotos se cortaba a 1000 pt de ventana: su cabecera mide unos 350 pt. Con 400 caben las dos a 1000 pt, comprobado con capturas.
- Comprobado con capturas a 1000×625: Secuencia (oscuro), Aleatorias (claro) y Carrusel (claro y oscuro). Generar en Aleatorias (`collage.run=1`) ha sacado los mismos tres collages que la previsualización. 145 tests en verde.

### 5. Alternativas descartadas
- Previsualizar solo el collage seleccionado o la foto seleccionada: el usuario prefiere ver la secuencia entera.
- Reparto de muestra orientativo en Aleatorias (Generar sorteando otro): descartado por el usuario; lo que se ve tiene que ser lo que sale.
- Esquema rápido con `TemplateView` en vez del render real: no enseña fondo, esquinas, título ni logo.
- Rejilla o uno debajo de otro: el usuario eligió tira horizontal.
- Dibujar toda la secuencia en una sola imagen: cualquier cambio obligaría a redibujarla entera.
- Mínimo de 420 pt en la columna izquierda: a 1000 pt de ventana cortaba la lista de fotos.
- Tocar la cabecera de `FileListView` para que encoja: la usan otros módulos; no hacía falta.

### 6. Pendiente de comprobar
- Con carpetas grandes (más de 100 fotos) y enfoque «Automático» o «Caras», cada nuevo sorteo vuelve a pedir los focos; van con caché, pero la primera vez Generar tarda en activarse.
- No se ha probado a mano el clic en la previsualización ni «Otro reparto» (solo compilación y capturas).

## 2026-10-21 — Selección y previsualización de Collage en un solo bloque abajo; encuadre manual en el carrusel

### 1. La petición tal como se ha entendido
La pantalla de Collage pasa a tener **arriba** las opciones (izquierda) y la lista de fotos entera (derecha), y **abajo, a todo el ancho**, un único bloque con la secuencia, separado por un divisor que se arrastra (el bloque empieza con unos 260 pt).
- **El bloque de abajo** une selección y previsualización. Su cabecera lleva los botones y el recuento del modo; debajo, la tira con los collages dibujados de verdad (fondo, separación, esquinas, título, logo).
  - **Secuencia**: cabecera con Componer, Añadir, Ajustar foco, Vaciar y «N de M fotos asignadas · K collages». Sobre cada collage: clic → editor de enfoque; arrastrar → cambia el orden; clic derecho → «Editar enfoque» y «Quitar». Desaparecen las tarjetas de la izquierda y el grupo «Secuencia».
  - **Aleatorias**: cabecera con «Otro reparto» y el recuento; los collages del reparto con las mismas acciones. A la izquierda se quedan los filtros, el «Enfoque» y la lista de plantillas permitidas.
  - **Carrusel**: cabecera con Componer, Añadir, Ajustar foco, Vaciar y «N de 10 diapositivas…»; la tira real con los cortes y el número de cada diapositiva. Sobre cada tramo: clic → **editor de encuadre del carrusel** (nuevo); arrastrar → cambia el orden; clic derecho → cambiar o quitar el tramo. A la izquierda queda solo el «Formato»; desaparecen la tira de encuadre y las fichas de tramos.
- **Editor de encuadre del carrusel** (hoja, como el de Secuencia): el tramo en grande con los cortes entre diapositivas, cada foto se arrastra dentro de su celda, flechas para pasar de un tramo a otro, «Centrar celdas» y conmutador «Encuadre / Resultado».
- «Generar» sigue al pie de la columna de opciones.
Confirmada por el usuario («si»).

### 2. Preguntas y respuestas
- **¿Qué se puede hacer sobre cada collage del bloque unificado de abajo?** → Todo lo que hacían las tarjetas de «Secuencia»: clic abre el editor de enfoque, arrastrar cambia el orden, clic derecho «Editar enfoque» y «Quitar».
- **¿Cómo se reparte la altura entre la parte de arriba y el bloque de abajo?** → Divisor ajustable; el bloque empieza con unos 260 pt.
- **¿Dónde van los botones de la secuencia (Componer, Añadir, Ajustar foco, Vaciar) y el recuento?** → En la cabecera del bloque de abajo; a la izquierda quedan solo las opciones.
- **En el carrusel, ¿cómo se ajusta a mano el encuadre?** → Con un editor que se abre al pulsar un tramo, como en Secuencia (fotos arrastrables, cortes visibles, flechas entre tramos, «Encuadre / Resultado»).

### 3. Fuentes analizadas
- Captura del usuario: tira de tarjetas de «Secuencia» tachada; recuadro a todo el ancho en la parte baja (de «Título» hasta «Generar», más la previsualización).
- `CollageView.swift`, `Shared/CollageSequenceEditor.swift`, `Shared/CollagePreview.swift`, `Modules/CarouselEditor.swift`.

### 4. Decisiones
- Plan aprobado («dale»). Sin commit: queda en el árbol de trabajo y en el CHANGELOG bajo «Sin publicar» (las entradas de la previsualización de antes se han rehecho, porque ninguna se había publicado).
- Publicado después, a petición del usuario, como versión 3.14.0 (junto con el desplegable «Tipo»), con release en GitHub. La landing añade «Toda la secuencia a la vista» y el encuadre por tramo del carrusel.
- `CollageSequenceEditor` solo lo usa Collage (el Slideshow tiene su propio editor), así que se ha convertido entero en el bloque de abajo sin tocar el Slideshow.
- Tira interactiva: `CollagePreview` con `onSelect`, `onMove` y el menú de cada modo; las acciones van en `SequenceItemActions` (clic, arrastrar, soltar, menú) y `moveSequenceItem`, compartidos por los tres modos.
- Carrusel: se sigue dibujando de una pieza (cortes exactos) y encima van zonas invisibles por tramo para el clic, el arrastre y el menú. Al arrastrar se ve la plantilla del tramo en pequeño.
- Editor nuevo `CarouselFocusEditorSheet` (en `CarouselEditor.swift`), hecho a semejanza de `FocusEditorSheet`; los números de diapositiva siguen la numeración del carrusel. Opción de arranque `carousel.editor=1` para capturas.
- Divisor propio `BottomSplit` en vez de `VSplitView`: con `VSplitView` el bloque salía con 340 pt en un modo y con 180 en otro; el propio empieza en 260 y guarda la altura en las preferencias (`collage.sequenceBlockHeight`).
- «Otro reparto» pasa de la fila de «Enfoque» a la cabecera del bloque «Reparto».
- Se quitan `PreviewTarget`, la vista `preview` y el `VSplitView` de la columna derecha de la versión anterior, la tira de encuadre y las fichas de tramos del carrusel, y el `updateFocus(globalCell:)`.
- El `body` de `CollageView` se ha partido (`setUp`, `modeChanged`, `randomEditingTarget`) porque el compilador no podía comprobar los tipos de la expresión entera.
- Comprobado con capturas: Secuencia a 1000×625 (oscuro), Aleatorias a 1440×900 (claro), Carrusel (claro y oscuro) y el editor del carrusel. Generar en Aleatorias ha vuelto a sacar los mismos cuatro collages que se ven.

### 5. Alternativas descartadas
- Encuadrar el carrusel arrastrando sobre la propia tira: la tira es pequeña y el arrastre chocaría con el de reordenar (descartado por el usuario).
- Dejar los botones de la secuencia en la columna izquierda (descartado por el usuario).
- Altura fija del bloque (el usuario prefirió divisor ajustable).
- `VSplitView`: no respeta la altura inicial.
- Dibujar cada tramo del carrusel por separado: los bordes entre tramos no saldrían exactamente como en el fichero.

### 6. Pendiente de comprobar
- A 1000×625 la parte de arriba queda baja (unos 250 pt para las opciones) y hay que hacer scroll; se puede bajar el divisor.
- No se ha probado a mano: arrastrar para reordenar en la tira, el menú del clic derecho, el divisor, «Otro reparto», ni la vista «Resultado» del editor del carrusel.

## 2026-10-23 — Botón principal de cada módulo al final de la barra inferior

### 1. La petición tal como se ha entendido
El botón que lanza la acción principal de cada módulo deja el pie de la columna de opciones y pasa al **extremo derecho de la barra inferior**, como «Generar vídeo» en Slideshow.
- **Con barra de destino** (Collage, Contact Sheet, Procesador, Marca de agua, Renombrador): el botón se añade al final de su barra, tras «Elegir…» (o tras el aviso de «Sobrescribir originales») y separado con una línea vertical.
- **Sin barra** (Metadatos, Código QR): estrenan una barra inferior con el mismo aspecto, solo para su botón principal y lo que lo acompaña.
- **Lo que acompaña al botón baja con él**, justo delante y separado con una línea: «Comparar antes / después» (Procesador), «N cambios» (Renombrador), «Guardar cambio de esta foto» y «N pendientes» (Metadatos) y el mensaje de error (QR).
- El botón conserva su texto, su estilo destacado y sus condiciones para activarse.
- Slideshow y Shutter Count no cambian («Elegir foto…» de Shutter Count no es una acción de proceso).

Confirmada por el usuario («si»).

### 2. Preguntas y respuestas
- **¿A qué módulos se aplica?** → A los 7 con botón principal: los 5 con barra de destino y, además, Metadatos y Código QR con una barra nueva.
- **¿Qué pasa con los botones y textos que acompañan al botón principal?** → Bajan con él a la barra, delante del botón y separados con una línea.

### 3. Fuentes analizadas
- Captura del usuario: «Generar» de Collage al pie de las opciones, con una flecha hacia el final de la barra «Carpeta de salida».
- `Shared/DestinationBar.swift`, `ContentView.swift`, `Model/Module.swift` (`destinationKind`), `Slideshow/SlideshowView.swift` (`SlideshowActionBar`), y las vistas `CollageView`, `ContactSheetView`, `ProcessorView`, `WatermarkView`, `RenamerView`, `MetadataView`, `QRView`, `ShutterCountView`.

### 4. Decisiones
- Plan aprobado («dale»). Sin commit: queda en el árbol de trabajo y en el CHANGELOG bajo «Sin publicar».
- Publicado después, a petición del usuario («publica»), como versión 3.15.0, con release en GitHub. La landing no cambia (no anuncia nada nuevo y la versión la lee de GitHub).
- La barra la pone cada módulo debajo de su vista (como el Slideshow) y `ContentView` deja de pintarla: el botón principal y sus condiciones viven en el módulo. `DestinationBar` pasa a ser genérica con un cierre `actions` que se pinta al final tras una línea; con `kind: .none` solo salen las acciones, a la derecha.
- `Module.destinationKind` se mantiene; cada módulo pasa a la barra el tipo que le toca.
- A 1000 pt de ventana la barra de carpeta con dos botones no cabía: el Procesador se salía de la ventana y el Renombrador hacía caer la app (excepción de AppKit al recalcular las restricciones de la ventana). Arreglo: «Guardar» como texto pegado al selector (sin la columna ancha de `LabeledRow`), ruta y avisos con `minWidth: 0` (ceden y se acortan por el medio) y acciones, «Guardar» y «Elegir…» con `fixedSize` (no se cortan nunca).
- «Comparar antes / después» del Procesador pasa a «Comparar» (con el texto largo como ayuda al pasar el ratón; traducción «Compare» añadida): con el texto largo no cabía a 1000 pt.
- Comprobado con capturas a 1000×625 de los 7 módulos (Collage en Secuencia y Aleatorias, claro y oscuro). 145 tests en verde.

### 5. Alternativas descartadas
- Dejar la barra en `ContentView` y que cada módulo le pase sus botones por `AppState`: habría que sacar del módulo las condiciones y la acción de cada botón.
- Selector de guardar como desplegable en vez de segmentado para ganar sitio: cambiaba el aspecto de la barra en todas las secciones.
- Cambiar solo Collage, o solo los 5 módulos con barra (el usuario quiere los 7).
- Dejar arriba los botones y textos acompañantes (el usuario prefiere que bajen con el principal).

### 6. Pendiente de comprobar
- Metadatos ya salía cortado por los dos lados a 1000×625 antes de este cambio (comprobado con la 3.14.0 instalada): las columnas piden más ancho del que hay. No se ha tocado.
- No se ha capturado el modo «Sobrescribir originales» con los botones al lado del aviso (no hay opción de arranque para dejarlo puesto); el aviso puede partirse en dos líneas en ventanas estrechas.
- No se ha probado a mano pulsar cada botón desde la barra (solo compilación y capturas); la acción es la misma de antes.

## 2026-10-23 — Valores más pequeños en «Aparición» del Slideshow

### 1. La petición tal como se ha entendido
En Slideshow → Vídeo (modo collage), el deslizador «Aparición» (lo que tarda en entrar cada foto de un collage) baja su mínimo de 0,3 s a **0,1 s**, manteniendo el paso de 0,1 s y el máximo de 5 s. El motor (`CollageSlideshow.Options`), que hoy sube a 0,2 s cualquier valor menor, pasa a aceptar 0,1 s para que lo elegido sea lo que sale en el vídeo. El fundido de cada foto sigue durando lo mismo que la aparición (como mucho 1 s).

Confirmada por el usuario («si»).

### 2. Preguntas y respuestas
- **¿Hasta qué valor mínimo debe bajar «Aparición»?** → 0,1 s (fundido muy corto, sin llegar al corte seco).

### 3. Fuentes analizadas
- `Slideshow/SlideshowInspector.swift` (deslizador `0.3...5`, paso 0,1), `Model/SlideshowDocument.swift` (`reveal`), `CaobaCore/Slideshow/CollageSlideshow.swift` (`max(0.2, reveal)`, fundido `min(1, reveal)`), `SlideshowSpec.swift` (la duración de transición admite cualquier valor ≥ 0), `CollageSlideshowTests.swift`.

### 4. Decisiones
- Plan aprobado («dale»). Sin commit: queda en el árbol de trabajo y en el CHANGELOG bajo «Sin publicar».
- Publicado después, a petición del usuario («publica»), en la versión 3.16.0 con release en GitHub.
- Deslizador `0.1...5` (paso 0,1, sin cambios) y suelo del motor `max(0.1, reveal)`: si solo se tocaba el deslizador, al generar 0,1 se convertía en 0,2 sin avisar.
- Test nuevo en `CollageSlideshowTests` (0,1 se respeta; 0,05 y 0 suben a 0,1). 146 tests en verde.
- Comprobado con captura de la pestaña Vídeo: el tirador queda donde corresponde al rango nuevo.

### 5. Alternativas descartadas
- Tocar solo el deslizador y dejar el motor en 0,2: el vídeo no saldría con el valor elegido.
- 0,2 s (el límite actual del motor): se queda corto para lo que se pide.
- 0 s (corte seco): el usuario prefiere conservar un fundido mínimo.

### 6. Pendiente de comprobar
- No se ha generado un vídeo a 0,1 s ni se ha mirado cómo queda el fundido tan corto (a 30 fps son unos 3 fotogramas).
- No se ha capturado el deslizador en 0,1: no hay opción de arranque para fijar el valor.

## 2026-10-23 — Cambiar el fichero de una pista de audio sin perder sus ajustes, y reordenar pistas

### 1. La petición tal como se ha entendido
En el Slideshow, una pista de música ya puesta puede cambiar de fichero conservando todo lo demás: su inicio en el vídeo (un segundo concreto o «tras la anterior»), el recorte «Desde» / «Hasta» y su lugar en la lista.
- **Dónde**: botón «Cambiar fichero…» en el editor de la pista (junto a «Quitar pista»), opción «Cambiar fichero…» en el clic derecho del bloque de la pista en el timeline (hoy no tiene menú) y botón en cada fila de la pestaña Música (junto a «Editar»).
- Abre el selector de audio en la carpeta del fichero actual. Solo cambia esa pista, aunque otra use el mismo fichero.
- **Si el fichero nuevo es más corto que el recorte**: se mantiene lo que quepa. «Hasta» baja al final del fichero nuevo (pasa a «hasta el final») y, si «Desde» también se sale, baja para que suene al menos 1 s. Sale un aviso que dice qué se ha ajustado. La posición en el timeline no cambia.
- Funciona igual con el fichero original presente o desaparecido («Localizar…» sigue como está).

Confirmada por el usuario («si»). Después, antes de empezar, el usuario amplía la petición:
- **Reordenar pistas arrastrando** en la lista de la pestaña Música. Cada pista conserva su forma de empezar: las de segundo fijo se quedan donde están y las de «tras la anterior» se encadenan según el nuevo orden (la primera de la lista, si es «tras la anterior», empieza en 0). El orden nuevo es también el de «Repetir la lista».

Ampliación confirmada por el usuario («si»).

### 2. Preguntas y respuestas
- **¿Desde dónde se podrá cambiar el fichero?** → Editor de la pista, clic derecho en el timeline y cada fila de la lista de Música.
- **Si el fichero nuevo es más corto que el recorte, ¿qué hacemos?** → Ajustar lo que no quepa y avisar.
- **Al reordenar pistas, ¿qué pasa con su posición en el vídeo?** → Se respeta el inicio de cada una: las fijas no se mueven y las de «tras la anterior» siguen el nuevo orden.

### 3. Fuentes analizadas
- `CaobaCore/Slideshow/SlideshowSpec.swift` (`AudioTrack`: `url`, `startMode`, `trimStart`, `trimEnd`), `Model/SlideshowDocument.swift` (`addTracks`, `relocate`/`replace`, `trimLeading`/`trimTrailing`, `trackDurations`), `Slideshow/SlideshowInspector.swift` (`TrackInspector`, lista de Música, `MissingFileNotice`, `audioFileTypes`), `Slideshow/SlideshowTimelineView.swift` (bloque de pista, sin menú contextual).

### 4. Decisiones
- Plan aprobado («dale»). Sin commit: queda en el árbol de trabajo y en el CHANGELOG bajo «Sin publicar».
- Publicado después, a petición del usuario («publica»), en la versión 3.16.0 con release en GitHub.
- `SlideshowDocument.replaceTrackFile(_:with:)` lee primero la duración del fichero nuevo; si no se puede, no cambia nada y avisa. Cambia solo esa pista (por `id`), su duración y, si hace falta, el recorte. El aviso va en `trackFileNotice` y lo enseña una alerta en `SlideshowView`.
- Ajuste del recorte: «Hasta» más allá del final → `nil` (hasta el final); «Desde» más tarde que duración − 1 s → duración − 1 s (como mínimo suena 1 s, igual que al recortar arrastrando).
- Un solo helper `chooseTrackFile(for:doc:)` para los tres sitios. El bloque de la pista en el timeline estrena clic derecho con «Cambiar fichero…» y «Quitar pista».
- Reordenar: la lista de Música no es una `List` (no vale `onMove`), así que va con `draggable` + `dropDestination`, como la tira de Collage. `moveSequenceItem` pasa a `moveItem`, genérico para cualquier `Identifiable`, y lo usan collages, carrusel y pistas (`moveTrack(_:onto:)`). La fila lleva asa ≡ y el texto «Arrastra una pista para cambiar el orden» cuando hay más de una.
- Opción de prueba `--state slideshow.replaceTrack=/ruta`. La prueba se hizo sobre una copia clonada de BOOK en el scratchpad, porque en modo captura la configuración de la carpeta también se guarda.
- Comprobado: con un audio de 3 s sobre la pista «Desde 0:05 Hasta 2:00», el inicio sigue en 0:00, «Desde» pasa a 0:02, «Hasta» al final (0:03) y la alerta lo cuenta; captura de la pestaña Música a 1000×625 con asas y botones. 146 tests en verde.

### 5. Alternativas descartadas
- Reutilizar `relocate` para cambiar el fichero: cambia todas las referencias a esa ruta (otras pistas, portada…) y busca otros ficheros que falten.
- Botones ↑/↓ para reordenar: el usuario pidió arrastrar.
- `onMove`: solo funciona dentro de una `List`.
- Solo en el editor de la pista (el usuario quiere también el clic derecho y la lista de Música).
- Ajustar sin avisar o no permitir el cambio si el recorte no cabe (el usuario prefiere ajustar y avisar).
- Al reordenar, encadenar todas las pistas (se perderían los inicios fijos) o intercambiar sus inicios (el usuario prefiere respetar el de cada una).

### 6. Pendiente de comprobar
- No se ha probado a mano el arrastre en la lista de Música (no se puede automatizar desde las capturas) ni el clic derecho del timeline.
- No se ha probado elegir un fichero que no se puede leer (el aviso está, pero sin captura).
- El análisis de ritmo se guarda por ruta: el fichero nuevo se analiza al pulsar «Ajustar al ritmo»; las duraciones ya ajustadas al ritmo de la canción anterior no se recalculan solas.

## 2026-10-23 — Vista previa completa del Slideshow con fotos reducidas

### 1. La petición tal como se ha entendido
«Vista previa» del Slideshow pasa a enseñar **el vídeo entero**: todas las fotos o todos los collages, portada, créditos, tarjetas de texto, pies, marca de agua y música, con las mismas duraciones y transiciones que el vídeo final. Hoy se corta en las 10 primeras fotos o los 3 primeros collages.
- **Tamaño fijo pequeño**: 640 px de lado mayor (640×360 en 16:9, 360×640 en vertical, 512×640 en 4:5…), siempre en píxeles pares.
- **Fotos reducidas**: cada foto se carga ya reducida a lo que necesita ese tamaño; en modo collage, los pasos de cada collage se dibujan a ese tamaño y no al del vídeo final.
- **Mismos fotogramas por segundo** que el vídeo final.
- El audio va sin normalizar (como ahora), para no tener que analizar cada canción antes.
- **El fallo de Intel**: en el iMac (iMac20,2, macOS 14.6.1) la app se cierra en cuanto empieza la vista previa, pero «Generar vídeo» funciona. No hay informe de fallo (`.ips`); los diagnósticos que hay son avisos de CPU y disco sin acción. La vista previa nueva codificará con los mismos ajustes que «Generar vídeo» (calidad proporcional al tamaño, sin el recorte a la cuarta parte) para no pedir al codificador nada que «Generar» no pida ya. No se puede comprobar aquí: en Rosetta la vista previa actual tampoco falla.
- Se sigue viendo en la ventana de la app, como ahora.

Confirmada por el usuario («si»).

### 2. Preguntas y respuestas
- **¿Se cae con «Vista previa», con «Generar» o con ambos? ¿Cuándo?** → Solo con «Vista previa», en cuanto empieza el proceso.
- **¿Hay informe del fallo?** → El usuario dejó en `logs/` cinco `.diag` (avisos de CPU y de escritura en disco, sin acción). Buscado el `.ips`: no hay ninguno.
- **¿A qué resolución sale la vista previa completa?** → Fija pequeña, 640 px de lado mayor.
- **¿A cuántos fotogramas por segundo?** → Los mismos que el vídeo final.

### 3. Fuentes analizadas
- `Model/SlideshowDocument.swift` (`preview`, `launch`: `makePhotos(limit: 10)`, `prefix(3)` de collages, `makeSpec(preview:)`), `CaobaCore/Slideshow/SlideshowSpec.swift` (`renderSize`: mitad en preview), `VideoWriter.swift` (`bitrate(for:preview:)`: cuarta parte en preview; `cachedImage`: `PhotoLoader.load(fittingAtLeast:)` a 1,2× o 2,4× el lienzo), `CollageSlideshow.swift` (pasos a `collage.longestSide`).
- `logs/` (cinco `.diag` del iMac de Irene, versiones 3.4.1 y 3.15.0).
- Prueba en Rosetta (x86_64) de la 3.16.0: la vista previa actual genera 22,5 s a 960×540 sin caerse.

### 4. Decisiones
- Plan aprobado («si»). Sin commit: queda en el árbol de trabajo y en el CHANGELOG bajo «Sin publicar». `logs/` no entra en el commit.
- Publicado después, a petición del usuario («publica»), en la versión 3.17.0 con release en GitHub.
- `SlideshowSpec.previewLongestSide = 640`; `renderSize` en vista previa escala el formato a ese lado mayor, redondea y deja los píxeles pares (16:9 → 640×360, 9:16 → 360×640, 4:5 → 512×640, 2:3 → 426×640).
- `VideoWriter.bitrate(for:)` sin el parámetro `preview`: misma fórmula para vista previa y final. Es lo único del codificador que distinguía la vista previa (además del tamaño), y la sospecha del cierre en Intel.
- App: sin `limit: 10` ni `prefix(3)`; `makePhotos` pierde el parámetro `limit` (solo lo usaba la vista previa). Los collages de la vista previa se dibujan con `collageOptionsForPreview` (`scaled(toLongestSide: 640)`). Las fotos sueltas no necesitan cambios: `VideoWriter` ya las carga reducidas a lo que pide el lienzo.
- Tests: nuevo `previewSize` (tamaños y bitrate) y adaptados los dos que tenían 960×540 fijo (el de fotogramas, con puntos en proporción del lienzo). 147 tests en verde.
- Comprobado con una copia de BOOK (24 fotos en collages, 50 s en el timeline): la vista previa dura 49,5 s, sale a 640×360 con audio y los collages se ven bien; tarda ~10 s (Debug, M2 Pro), ~9 s (Release, M2 Pro) y ~15 s (Release en Rosetta, x86_64).

### 5. Alternativas descartadas
- Mitad de la resolución del vídeo o la misma resolución que el final (el usuario prefiere 640 px, lo más rápido).
- 15 fps (el usuario prefiere la misma fluidez que el vídeo final).

### 6. Pendiente de comprobar
- **Probar en el iMac Intel** (iMac20,2, macOS 14.6.1): la causa del cierre no se conoce (no hubo `.ips`) y en Rosetta no se reproducía ni antes ni ahora. Igualar el bitrate al de «Generar» es la apuesta razonable, no una certeza.
- No se ha probado con un vídeo largo en modo fotos (cientos de fotos) para ver el tiempo; cada foto se sigue decodificando del original (reducida al cargarla), sin caché entre vistas previas.

## 2026-10-23 — Cruces entre pistas: duración ajustable, rampas en el timeline y escucha del cruce

### 1. La petición tal como se ha entendido
El cruce entre pistas de música ya existe (3 s fijos: la que entra sube de 0 a su volumen y la que sale baja a 0 a la vez). Se mejora en tres cosas:
- **Duración ajustable**:
  - General, en «Opciones» de la pestaña Música: «Cruce entre pistas», de 0 a 10 s de 0,5 en 0,5 (3 s por defecto, como ahora). Con 0 el cambio es un corte seco.
  - Propia por pista, en su editor: la duración de **su entrada** (el cruce con la anterior), con vuelta a la general. La primera pista no tiene entrada (no se funde con nada), salvo al repetirse la lista.
  - Con «tras la anterior», la pista entra tantos segundos antes del final de la anterior como dure su cruce.
  - El «Fundido de salida» del final sigue siendo una casilla y, marcada, enseña su duración: de 1 a 10 s (3 s por defecto).
  - Se guarda en la configuración de la carpeta; las antiguas abren con 3 s.
- **Timeline**: cada bloque de música dibuja su volumen: el principio sube en diagonal durante su entrada y el final baja durante su salida (también el fundido final).
- **Escuchar el cruce sin generar**: en la «Preescucha» del editor de la pista, «Escuchar entrada» (cruce con la anterior) y «Escuchar salida» (con la siguiente o el fundido final). Suena la mezcla real (las mismas rampas que el vídeo) desde 5 s antes hasta 5 s después del cruce, con play/pausa. Cada botón solo aparece si la pista tiene ese cruce.

Confirmada por el usuario («si»).

### 2. Preguntas y respuestas
- **¿Hay forma de fundir pistas al cambiar?** → Sí, ya existe: 3 s fijos, siempre. Lo que falta es ajustar la duración, verlo en el timeline y oírlo sin generar; el usuario quiere las tres («las 3»).
- **¿Duración general o por cambio?** → Una general y, en cada pista, una propia opcional.
- **¿Qué valores?** → De 0 a 10 s, de 0,5 en 0,5; 0 = corte seco; 3 s por defecto.
- **¿También el fundido de salida del final?** → Sí, de 1 a 10 s.
- **¿Cómo se marca en el timeline?** → Rampas de volumen en los bloques.
- **¿Cómo se escucha?** → Botones «Escuchar entrada» / «Escuchar salida» en la Preescucha del editor de la pista.

### 3. Fuentes analizadas
- `CaobaCore/Audio/AudioPlan.swift` (`build`: inicio automático = final de la anterior − cruce; el tramo que sale se alarga hasta inicio de la siguiente + cruce), `Audio/AudioMuxer.swift` (`makeComposition`: rampas de volumen, repetición del tramo recortado), `Slideshow/SlideshowSpec.swift` (`AudioOptions.crossfadeSeconds = 3`, `fadeOutSeconds = 3`), `Slideshow/SlideshowInspector.swift` (pestaña Música, `TrackInspector`, `TrackPreview`), `Slideshow/SlideshowTimelineView.swift` (`TrackBlock`).

### 4. Decisiones
- Plan aprobado («dale»). Sin commit: queda en el árbol de trabajo y en el CHANGELOG bajo «Sin publicar».
- Publicado después, a petición del usuario («publica»), en la versión 3.17.0 con release en GitHub.
- Datos: `AudioOptions.crossfade` y `fadeOutDuration` (3 s por defecto, también al leer configuraciones antiguas); `AudioTrack.crossfade` opcional. Preset: `audio.crossfade`, `audio.fadeoutDuration` y `musicTracks[].crossfade`.
- `AudioSegment` pasa de `fadeIn`/`fadeOut` (sí/no) a `fadeInSeconds`/`fadeOutSeconds`, y lleva `trackID`. Con él, `effectiveStart` y los tramos de relleno del timeline ya no buscan por ruta y recorte (dos pistas con el mismo fichero y recorte se confundían).
- `AudioPlan.build`: cada cambio usa el cruce de la pista que entra; «tras la anterior» entra ese tiempo antes; la que sale se alarga lo mismo; con 0, corte seco. `AudioMuxer` aplica esas duraciones con los mismos recortes de antes y `makeComposition` pasa a pública.
- **Fallo encontrado y corregido**: `AudioPlan` calculaba los cruces en el orden de la lista. Si una pista con inicio fijo iba más abajo y empezaba antes, la otra se quedaba sin duración y desaparecía del vídeo (pasaba ya antes arrastrando un bloque en el timeline; con el reordenado de la 3.16.0 era más fácil). Ahora se ordena por inicio (desempate por orden de llegada). Test que lo reproducía antes del arreglo.
- «Entrada» en el editor solo aparece si algún tramo de esa pista entra tras otro (al principio se puso «no es la primera o la lista se repite», y salía en la primera pista aunque la lista no llegara a repetirse). El valor muestra solo los segundos; debajo, «Usa el cruce general…».
- Reproductor del cruce (`MixPreviewPlayer`) en el mismo fichero que `TrackPreviewPlayer`, para no tener que regenerar el proyecto de Xcode.
- Comprobado sobre una copia de BOOK con dos tonos puros (440 y 1000 Hz) en lugar de las canciones, cruce de 6 s y fundido final de 5 s: midiendo cada frecuencia por separado, entre 0:24 y 0:30 una baja de −21 a −56 dB y la otra sube de −56 a −21; en los últimos 5 s baja la que queda. Igual con la lista invertida. Capturas de Música (oscuro) y del editor (claro). 153 tests en verde.

### 5. Alternativas descartadas
- Escuchar el cruce generando un trozo de vídeo: montar la mezcla con AVFoundation es instantáneo y suena igual.
- Solo duración general, o solo por pista (el usuario prefiere general + propia).
- Rango de 0,5 a 10 s (sin corte seco) o de 0 a 5 s.
- Dejar fijo el fundido de salida del final.
- Franja sombreada en el timeline en vez de rampas.
- Escuchar el cruce pulsando en el timeline (el usuario prefiere los botones del editor).

### 6. Pendiente de comprobar
- No se han pulsado a mano «Escuchar entrada» / «Escuchar salida» (el audio no se puede comprobar desde una captura); la mezcla que usan es la misma que se ha medido en el vídeo.
- Con «Normalizar volumen», la escucha del cruce va sin normalizar (como la vista previa).

## 2026-10-23 — «Recientes» no se queda con el foco

### 1. La petición tal como se ha entendido
El menú «Recientes» de la barra de carpeta deja de quedarse con el foco del teclado (y su marco) al abrir la ventana: no lo recibe nunca. Se sigue usando con el ratón; con Tab se lo salta, como ya pasa con «Reiniciar» y «Elegir carpeta…». Se hace igual que en la hoja de donación (`.focusable(false)`).

Confirmada por el usuario («si»).

### 2. Preguntas y respuestas
- **¿Que no coja el foco nunca, o solo que no lo coja al abrir (sí con Tab)?** → Que no lo coja nunca.

### 3. Fuentes analizadas
- Captura del usuario: marco de foco alrededor de «Recientes».
- `Shared/SourceFolderBar.swift` (menú con `.menuStyle(.borderlessButton)`), `Shared/DonationSheet.swift` (precedente con `.focusable(false)`).

### 4. Decisiones
- Plan aprobado («si»). Sin commit: queda en el árbol de trabajo y en el CHANGELOG bajo «Sin publicar».
- Publicado después, a petición del usuario («publica»), en la versión 3.17.0 con release en GitHub.
- `.focusable(false)` en el menú «Recientes» de `SourceFolderBar`, con comentario del porqué.

### 5. Alternativas descartadas
- Que solo con Tab llegue a él (el usuario prefiere que no lo coja nunca).

### 6. Pendiente de comprobar
- **Comprobar a mano** que el marco ya no sale y si el foco pasa a otro control (p. ej. «Sin preset» o un selector segmentado). Las capturas no sirven para esto: en modo captura la ventana no es la activa y macOS no dibuja el foco (tampoco salía el marco en «Recientes» en las capturas de antes del cambio).

## 2026-10-23 — Cuadrar los cruces entre pistas con el ritmo

### 1. La petición tal como se ha entendido
Nuevo botón **«Cuadrar cruces»** en Música → Ritmo, junto a «Ajustar al ritmo». Analiza las canciones (el mismo análisis de golpes que ya hay) y, en cada cambio de pista:
1. **El cruce empieza en un golpe** de la canción que sale: el inicio de la que entra se mueve al golpe más cercano.
2. **Los golpes de las dos coinciden** durante el cruce: se ajusta la fase de la que entra para que sus golpes caigan encima de los de la que sale.
- Cada pista se mueve **como mucho medio golpe** (unas décimas) respecto a donde estaba.
- Se mueven **todas**, también las de inicio fijo. Las de «tras la anterior» pasan a inicio fijo en su sitio nuevo, para que el ajuste no se pierda si luego cambia la anterior.
- El cambio se ve en el timeline y en el editor de la pista, y se puede retocar a mano después.
- **Cuándo no se cuadra un cruce** (y se dice en el mensaje del resultado): si alguna de las dos canciones no tiene ritmo claro, si los tempos son demasiado distintos (más de un 6 % de diferencia, contando como compatibles el doble y la mitad, p. ej. 70 y 140 ppm), si el cruce es un corte seco (0 s) o si falta el fichero.
- Mensaje al terminar: cuántos cruces se han cuadrado y cuáles no y por qué.
- No toca las duraciones de las fotos. Si se quiere que los cambios de foto también caigan en los golpes, se pulsa después «Ajustar al ritmo» (que usa las posiciones nuevas de las pistas).

Confirmada por el usuario («ok»).

### 2. Preguntas y respuestas
- **¿Se puede ajustar el paso de una pista a otra al ritmo?** → Se explicaron tres niveles (cruce en un golpe; golpes coincidentes; igualar tempo). El usuario elige el 2 (que incluye el 1).
- **¿Cuándo se cuadran?** → Con un botón que mueve de verdad las pistas (se ve en el timeline y se puede retocar).
- **¿Se pueden mover las pistas de inicio fijo?** → Sí, todas, como mucho medio golpe; las de «tras la anterior» pasan a inicio fijo.

### 3. Fuentes analizadas
- `CaobaCore/Audio/BeatDetector.swift` (`BeatTrack`: tempo, golpes en segundos del fichero, confianza, `isReliable`), `Slideshow/RhythmPlanner.swift` (`videoBeats`), `Audio/AudioPlan.swift` (cruces por orden de inicio), `Model/SlideshowDocument.swift` (`beatTracks`, `adjustToRhythm`, `rhythmMessage`), pestaña Música (`SlideshowInspector.swift`, grupo Ritmo).

### 4. Decisiones
- Plan aprobado («dale»). Sin commit: queda en el árbol de trabajo y en el CHANGELOG bajo «Sin publicar».
- Publicado después, a petición del usuario («publica»), en la versión 3.17.0 con release en GitHub.
- El cálculo es puro y está en el motor (`CrossfadeAligner`, fichero nuevo), con 6 tests; la app solo lo orquesta (`alignCrossfades`, `nextCrossfade`) y comparte con «Ajustar al ritmo» el análisis de golpes (`analyzePendingBeats`, sacado de `adjustToRhythm`).
- Para conseguir a la vez «el cruce empieza en un golpe» y «los golpes coinciden», además del inicio se mueve el **Desde** de la que entra (como mucho medio golpe): con mover solo el inicio no se pueden cumplir las dos cosas. Se avisó en el plan.
- Tolerancia de tempo del 6 % (doble y mitad compatibles) y fotos sin tocar: decididos por mí y aceptados en la confirmación.
- Comprobado sobre una copia de BOOK con dos pistas de clics a 120 ppm (A: 440 Hz desde 0; B: 1000 Hz desfasada 0,2 s, empezando en 24,15 s): tras «Cuadrar cruces», B queda en 23,998 s con Desde 0,197 s (lo esperado: 24,0 y 0,2) y, en la vista previa, sus clics caen a 0–12 ms de los de A durante el cruce (sin cuadrar, 150 ms). Captura del botón con «1 cruce cuadrado con el ritmo.». 159 tests en verde.

### 5. Alternativas descartadas
- Solo empezar el cruce en un golpe (nivel 1): el usuario quiere también que coincidan los golpes.
- Igualar el tempo acelerando o frenando la canción (nivel 3): cambia la velocidad de la canción y es mucho más trabajo.
- Ajuste automático al generar (sin tocar las pistas) o dentro de «Ajustar al ritmo»: el usuario prefiere un botón propio que mueva las pistas.
- Mover solo las de «tras la anterior».
- Cuadrar con el compás («el uno»): la app no detecta dónde empieza el compás.

### 6. Pendiente de comprobar
- Probado con clics sintéticos; con canciones reales el resultado depende de lo bien que el detector encuentre los golpes (en música sin batería marcada puede decir «sin ritmo claro» o cuadrar a contratiempo).
- Al mover el Desde de la que entra, cambia unas décimas lo primero que se oye de esa canción.

## 2026-10-24 — «Ajustar al ritmo» según las fotos de cada collage

### 1. La petición tal como se ha entendido
«Ajustar al ritmo», en modo collage, deja de dar a todos los collages la misma duración y tiene en cuenta cuántas fotos lleva cada uno:
- **Referencia por collage**: la duración que tendría sin ritmo, `0,5 s + Aparición × sus fotos + Mantener`. El ritmo la lleva al golpe más cercano (antes la referencia era la de un collage de 3 fotos para todos).
- **«Golpes por foto» en Auto**: para cada collage se elige, entre 1, 2, 4, 8, 16 y 32 golpes, el número que deja su duración más cerca de su referencia.
- **«Golpes por foto» con un número fijo**: se multiplica por las fotos del collage (con 2: 1 foto → 2 golpes; 5 fotos → 10 golpes).
- En ambos casos, si con esos golpes no cabe la aparición de todas sus fotos, se alarga al golpe siguiente que quepa; y si el golpe que toca no está dentro de los límites, se busca el que deje la duración más cerca de su referencia (hoy se busca el más cerca de los golpes elegidos).
- Lo demás no cambia: los collages con «Mantener» propio no se tocan, el modo fotos sigue igual (cada elemento es una foto) y portada, créditos y textos tampoco se tocan.

Confirmada por el usuario («si»).

### 2. Preguntas y respuestas
- **¿Qué duración de referencia usa el ritmo para cada collage?** → La que tendría sin ritmo (0,5 s + Aparición × fotos + Mantener).
- **Con un número fijo en «Golpes por foto», ¿cómo se aplica a los collages?** → Por cada foto del collage (se multiplica por sus fotos).

### 3. Fuentes analizadas
- `Model/SlideshowDocument.swift` (`applyRhythm`: un solo `target` = `0,5 + reveal × 3 + hold` para todos los collages; mínimo = la aparición de sus fotos), `CaobaCore/Slideshow/RhythmPlanner.swift` (`plan`: un `target` común, densidad automática entre potencias de dos, búsqueda de alternativa por cercanía a `densidad × periodo`; `RhythmItem`).

### 4. Decisiones
- Plan aprobado («dale»). Sin commit: queda en el árbol de trabajo y en el CHANGELOG bajo «Sin publicar».
- Publicado después, a petición del usuario («publica»), en la versión 3.18.0 con release en GitHub.
- `RhythmItem` gana `target` (referencia propia; `nil` = la general) y `photos` (1 por defecto): el modo fotos y lo que no es collage no cambian. Sin golpes a la vista, se usa la referencia propia acotada por los límites.
- Automático entre 1, 2, 4, 8, 16 y 32 golpes (`automaticDensities`); el selector sigue de 1 a 16. Decidido por mí: con Mantener alto o muchas fotos, 16 golpes se quedaban cortos.
- Si el golpe que toca no cabe: en fijo, el más cercano a los golpes pedidos (como antes); en automático, el más cercano a la referencia.
- Tests nuevos (`collageTargets`, `collagePerPhoto`); los de antes siguen igual. 161 tests en verde.
- Comprobado sobre una copia de BOOK (9 collages de 1 a 5 fotos, Aparición 1,5 s, Mantener 0) con una pista de clics a 120 ppm, «Ajustar al ritmo» con la 3.17.0 y con esta versión: los de 1 foto pasan de ~4 s a 2,5 s, los de 4 fotos de 6,5 s a 8 s, y los de 2, 3 y 5 se quedan como estaban (~4, 5,5 y 8,1 s).

### 5. Alternativas descartadas
- Un ajuste nuevo de «segundos por foto» como referencia (el usuario prefiere la duración que tendría sin ritmo).
- «Golpes por collage» igual para todos, como ahora.

### 6. Pendiente de comprobar
- Con una canción real (golpes menos regulares que los clics) no se ha probado; el reparto depende igual de que el detector encuentre los golpes.
- Las duraciones que ya se ajustaron al ritmo con la versión anterior no cambian solas: hay que volver a pulsar «Ajustar al ritmo».

## 2026-10-24 — Ver qué diapositivas tienen tiempo manual y que el inspector cuente como manual

### 1. La petición tal como se ha entendido
Dos cambios en el Slideshow:
- **Marca en el timeline**: en los bloques de fotos y collages, junto a la cifra de segundos, un icono de mano si la duración es manual y uno de metrónomo si la puso «Ajustar al ritmo». Las que siguen la duración general (o Mantener general), sin icono. Cada icono con su tooltip. Portada, créditos y textos, sin icono.
- **Recuento separado en el inspector general**: «N fotos con duración propia» / «N collages con duración propia» pasa a distinguir manuales y al ritmo (p. ej. «2 manuales · 5 al ritmo»). «Igualar duraciones» sigue quitando las dos.
- **Corrección**: cambiar la Duración de una foto o el Mantener de un collage desde su inspector cuenta como manual, igual que estirar el bloque en el timeline; así «Ajustar al ritmo» ya no lo pisa. Deshacer con la flecha la devuelve a la general (sin marca).

Confirmada por el usuario («si»).

Petición original: «¿tenemos forma de saber cuáles son los frames que tienen tiempo manual?». Tras explicar que hoy solo hay un recuento (que mezcla manuales y ajustadas al ritmo) y que un cambio desde el inspector no cuenta como manual para «Ajustar al ritmo», el usuario pide las dos cosas: marcarlas en el timeline y corregir el fallo del inspector.

### 2. Preguntas y respuestas
- **¿Cómo se marca en el timeline el tiempo de cada diapositiva?** → Icono junto a la duración: mano para las manuales, metrónomo para las ajustadas al ritmo; las que siguen la duración general, sin icono. Con tooltip.
- **¿Portada, créditos y textos llevan icono?** → No: solo fotos y collages, que son los que pueden seguir la general o el ritmo.
- **¿Se separa el recuento del inspector general?** → Sí: «N manuales · N al ritmo».
- **(Encontrado al probar) En modo collage, al reabrir la carpeta los collages reciben un identificador nuevo y se pierde cuáles ajustó el ritmo: salen como manuales y «Ajustar al ritmo» ya no los recalcula. ¿Se corrige aquí?** → Sí, guardándolo por posición en la secuencia (como ya se guarda su Mantener). Los proyectos ya guardados no se recuperan: hay que pulsar «Igualar duraciones» y luego «Ajustar al ritmo».

### 3. Fuentes analizadas
- `Model/SlideshowDocument.swift` (`rhythmItems`, `setDuration`, `setHold`, `applyRhythm`, guardado y carga del preset: `holdByRow` por posición, `SequenceItem` con `UUID()` nuevo al cargar), `Views/Modules/CollageView.swift` (`SequenceItem`), `Views/Modules/Slideshow/SlideshowInspector.swift` (recuentos de «duración propia», sliders Duración y Mantener que escribían directamente), `SlideshowTimelineView.swift` (bloque del timeline).

### 4. Decisiones
- Plan aprobado («si»). Sin commit.
- Publicado después, a petición del usuario («publica»), en la versión 3.18.0 con release en GitHub.
- `DurationSource` (`general`, `manual`, `rhythm`) sale de lo que ya se guardaba: tiempo propio + estar o no en `rhythmItems`. No hace falta guardar nada nuevo para las fotos.
- Iconos SF Symbols `hand.raised.fill` y `metronome`, con tooltip, en el timeline y en el recuento de Vídeo (`OwnDurationsRow`, compartido por los modos fotos y collage). El recuento cuenta solo las fotos marcadas del vídeo (antes contaba todas las entradas guardadas, también de fotos quitadas).
- `setPhotoDuration` y `setHold` sacan el elemento de `rhythmItems`; `applyRhythm` sigue escribiendo directo, así que el ritmo no se borra a sí mismo.
- Collages en el fichero como `collage:<posición>`; al cargar se traducen al identificador del collage. Los identificadores antiguos se descartan (no se pueden recuperar), así que esos collages salen como manuales.
- Comprobado sobre una copia de BOOK: «Ajustar al ritmo» guarda `collage:0…8`; tras quitar uno de la lista (manual) y otro con su Mantener (general) y reabrir, el timeline muestra la mano, los metrónomos y el collage general sin icono, y Vídeo dice «1 manual · 7 al ritmo».

### 5. Alternativas descartadas
- Marcar solo las manuales o usar colores en la cifra (el usuario prefiere los dos iconos).
- Icono también en portada, créditos y textos: siempre tienen tiempo propio, no aporta.
- Identificador estable para cada collage guardado en el fichero: más cambio para lo mismo; la posición ya es como se guarda su Mantener.
- Suponer que en los proyectos antiguos todos los collages con Mantener propio eran del ritmo: el usuario prefiere no suponerlo.

### 6. Pendiente de comprobar
- No se ha probado moviendo el slider del editor en la app (la corrección es una línea en `setPhotoDuration`/`setHold`).
- En bloques muy estrechos del timeline el icono quita sitio a la cifra (ya se partía antes).
- Tu BOOK real tiene la lista del ritmo con identificadores antiguos: saldrá con todos los collages como manuales hasta «Igualar duraciones» + «Ajustar al ritmo».

## 2026-10-24 — Saltos al estirar la duración de una diapositiva en el timeline

### 1. La petición tal como se ha entendido
Al arrastrar el asa del borde derecho de un bloque del timeline para alargar o acortar su duración, el bloque va dando saltos (adelante y atrás) mientras se mantiene pulsado el ratón. Debe seguir al ratón de forma estable, avanzando de 0,5 en 0,5 s como hasta ahora.

Causa encontrada en `SlideshowTimelineView.swift`: el arrastre mide cuánto se ha movido el ratón respecto al propio asa, y el asa se mueve con el borde del bloque al cambiar su duración. Cada cambio de anchura altera la medida del siguiente movimiento y el bloque rebota.

### 2. Preguntas y respuestas
- Ninguna: la causa se encontró en el código.

Confirmada por el usuario («si»), junto con la solución propuesta.

### 3. Fuentes analizadas
- `Views/Modules/Slideshow/SlideshowTimelineView.swift`: asa de duración de los bloques (`DragGesture` en coordenadas locales del asa, que se mueve con el borde), arrastre de pistas (`moveGesture`) y asas de recorte de pistas (mismo caso).

### 4. Decisiones
- `coordinateSpace: .global` en los tres arrastres: la ventana no se mueve, así que la distancia arrastrada es la real y no depende de la anchura que va tomando el bloque.
- Publicado después, a petición del usuario («publica»), en la versión 3.18.0 con release en GitHub.
- Se incluyen el arrastre y los recortes de las pistas de música aunque no se pidieron: es el mismo fallo (la pista o el asa se mueven bajo el ratón). Avisado al usuario.

### 5. Alternativas descartadas
- Un espacio de coordenadas con nombre en el contenido del timeline: también vale, pero el global basta porque solo se usan diferencias y el timeline no se desplaza mientras se arrastra.

### 6. Pendiente de comprobar
- No se ha podido probar arrastrando de verdad (no hay forma de simular el ratón desde aquí): compila, pero falta que el usuario lo pruebe.
- Si el timeline se desplazara solo mientras se arrastra (no lo hace hoy), la medida global no lo tendría en cuenta.

## 2026-10-24 — El timeline termina en el fin del vídeo

### 1. La petición tal como se ha entendido
El scroll del timeline del Slideshow acaba en la marca «Fin del vídeo», aunque alguna pista de música dure más: lo que pase de ahí no va a sonar.
- La regla, los bloques y los carriles de música se dibujan solo hasta el fin del vídeo; la parte de una pista que pase del final se corta (ya no se ve apagada como ahora).
- El «Hasta» de una pista que pase del final ya no se puede estirar en el timeline (su asa queda fuera): se ajusta desde el editor de la pista.
- Una pista con inicio fijo que empiece después del final no se verá en el timeline (sigue en la lista de Música).
- El texto «Fin del vídeo» pasa a la izquierda de la línea, para que quepa sin dejar hueco detrás.

### 2. Preguntas y respuestas
- **¿Qué se hace con la parte de las pistas que pasa del fin (y con su asa de Hasta)?** → Cortarla en el fin; el Hasta se ajusta desde el editor de la pista.

Confirmada por el usuario («si»).

### 3. Fuentes analizadas
- `Views/Modules/Slideshow/SlideshowTimelineView.swift` (anchura = `timelineExtent` = máximo entre vídeo y audio; hueco de 60 pt tras el contenido para el texto «Fin del vídeo»; `TrackBlock` con el tramo tras el fin apagado), `Model/SlideshowDocument.swift` (`audioExtent`, `timelineExtent`).

### 4. Decisiones
- Plan aprobado («dale»). Sin commit.
- Publicado después, a petición del usuario («publica»), en la versión 3.18.0 con release en GitHub.
- La anchura sale de `totalDuration`; los carriles se recortan con `.clipped()`. Se quitan `audioExtent`, `timelineExtent` y el sombreado del tramo que no suena (`videoEnd` de `TrackBlock`), que ya no se usaban o no se verían.
- El texto «Fin del vídeo» va a la izquierda de la línea y se quita el hueco de detrás. Las marcas de la regla (y de golpes) que caerían bajo el texto (80 pt) se omiten: en la captura el «0:50» se montaba con él. Decidido por mí.
- Comprobado con capturas sobre una copia de BOOK (dos pistas que pasan del final): las pistas se cortan en la línea y el texto ya no se monta con la regla.

### 5. Alternativas descartadas
- Dejar un margen de un par de segundos tras el fin para ver que la pista sigue (el usuario prefiere cortar justo en el fin).
- Fondo opaco detrás del texto para tapar las marcas: el panel es translúcido y el color no casaría igual en claro y oscuro.

### 6. Pendiente de comprobar
- No se ha probado arrastrando: una pista cuyo borde derecho queda fuera solo se recorta desde su editor.
- Una pista con inicio fijo después del final no aparece en el timeline (sí en la lista de Música).

## 2026-10-24 — Marcar en el timeline la parte de una pista que no suena porque entra otra

### 1. La petición tal como se ha entendido
En el timeline del Slideshow, el tramo del bloque de una pista que no se oye porque ya ha entrado la siguiente (desde el final de su cruce hasta su Hasta) se dibuja **rayado**:
- Rayas oscuras (negras semitransparentes), no rojas, para no confundirlo con una pista cuyo fichero no se encuentra (que ya va rayada en rojo).
- Sirve igual para cualquier tramo del bloque que no suene, también si una pista con inicio fijo corta a la anterior.
- El bloque sigue entero: se puede seleccionar, mover y estirar su Hasta como ahora.
- Lo que pase del fin del vídeo sigue cortado como en el cambio anterior.

Petición original: «¿podríamos marcar también de alguna forma la parte de pista que ya no va a sonar en el vídeo porque hay otra?» (captura: la primera pista sigue dibujada a todo color después del cruce con la segunda).

### 2. Preguntas y respuestas
- **¿Cómo se marca la parte que no suena?** → Rayada.

Confirmada por el usuario («si»).

### 3. Fuentes analizadas
- `Views/Modules/Slideshow/SlideshowTimelineView.swift` (`lanes`, `fillerRanges`, `TrackBlock`), `Views/Shared/Theme.swift` (`MissingStripes`), `Model/SlideshowDocument.swift` (`audioSegments`).

### 4. Decisiones
- Plan aprobado («si»). Sin commit.
- Publicado después, a petición del usuario («publica»), en la versión 3.18.0 con release en GitHub.
- Tramos sin sonar = el bloque principal menos los tramos de esa pista en `audioSegments` (incluido su cruce de salida), con 0,05 s de margen para no dibujar astillas.
- `Stripes` (color y opacidades) pasa a ser la base de `MissingStripes` (rojas) y de la nueva `SilentStripes` (negras), para no duplicar el dibujo.
- Las rayas van encima del bloque sin capturar el ratón: mover, seleccionar y estirar no cambian.
- Comprobado con capturas en claro y oscuro sobre una copia de BOOK: la primera pista sale rayada desde el final de su cruce con la segunda hasta el fin del vídeo.

### 5. Alternativas descartadas
- Oscurecer el tramo o recortar el bloque (el usuario prefiere rayado; recortar quitaría el asa del Hasta).
- Rayas rojas como las de fichero no encontrado: se confundirían.

### 6. Pendiente de comprobar
- Con «Repetir la lista» o pistas que se repiten, solo se raya el bloque principal; las vueltas atenuadas siguen como estaban.

## 2026-10-27 — El fundido final de la música, al acabar el vídeo aunque la pista dure más

### 1. La petición tal como se ha entendido
Revisar que el fundido final de la música (Música → Opciones, «Fundido al final») se haga al acabar el vídeo, aunque la pista que suena dure más.

Revisión hecha:
- **Caso normal (bien)**: la última pista que suena se corta en el fin del vídeo y baja en los últimos segundos indicados. Medido sobre una vista previa de una copia de BOOK (52,4 s, fundido 3 s): −11 / −13 dB hasta el segundo 49, −15 dB en el 50, −23 dB en el 51 y −35 dB en el 52.
- **Fallo encontrado**: si hay una pista con inicio fijo que empieza en el fin del vídeo o después (por ejemplo, porque se acortó el vídeo), el fundido final se le asigna a esa pista (que no llega a sonar) y la que de verdad suena al final se corta en seco. Además, a esa última se le quita su fundido porque «la siguiente no llega a entrar».

Propuesta de corrección (en `AudioPlan.build`):
- Las pistas que empiezan en el fin del vídeo o después no cuentan para los cruces ni para el fundido final (no suenan).
- El fundido final se aplica a todas las que estén sonando al acabar el vídeo (si una ya estaba saliendo en un cruce más largo, se queda con el más largo).
- Test nuevo con estos casos.

### 2. Preguntas y respuestas
- Ninguna por ahora: la revisión responde a lo pedido y la corrección es la consecuencia directa.

Confirmada por el usuario («si»), junto con la corrección propuesta.

### 3. Fuentes analizadas
- `CaobaCore/Audio/AudioPlan.swift` (`build`: el fundido final solo iba al último segmento, que podía ser uno de duración 0 que luego se descartaba), `CaobaCore/Audio/AudioMuxer.swift` (rampas: la de salida termina en el `end` del segmento, que ya es el fin del vídeo), configuración de BOOK (dos pistas con inicio fijo, fundido 3 s, lista en bucle).

### 4. Decisiones
- Sin commit.
- Publicado después, a petición del usuario («publica»), en la versión 3.18.1 con release en GitHub.
- Se descartan las pistas que empiezan a 0,05 s o menos del fin (mismo margen con el que ya se quitaban los tramos diminutos), antes de calcular los cruces.
- El fundido final va a todos los tramos que llegan al fin, con `max(su salida, fundido final)`.
- Test nuevo («Fundido final al acabar el vídeo aunque una pista con inicio fijo empiece después»); 162 tests en verde.
- Comprobado con una copia de BOOK a la que se añadió una tercera pista con inicio en 70 s (vídeo de 52,4 s): con la 3.18.0 el final se queda en −12/−13 dB hasta el último segundo (corte en seco); con la corrección baja a −15, −23 y −35 dB en los segundos 50, 51 y 52.

### 5. Alternativas descartadas
- Avisar en la app de las pistas que empiezan después del fin en lugar de corregir el cálculo: el timeline ya no las enseña, y el fundido debe salir bien igualmente.

### 6. Pendiente de comprobar
- Nada más en el caso normal (ya funcionaba y se midió).

## 2026-10-28 — «Segundos por foto» con tiempos más pequeños

### 1. La petición tal como se ha entendido
En Slideshow, modo Fotos, se podrán poner tiempos por foto mucho más cortos, igual que se hizo con «Aparición» en collage:

- **Segundos por foto** (pestaña Vídeo): mínimo 0,1 s en lugar de 1 s, con pasos de 0,1 s. El máximo sigue en 15 s.
- **Duración de cada foto**:
  - En el inspector: mínimo 0,1 s y pasos de 0,1 s. El máximo sigue en 30 s.
  - Al estirar la foto en el timeline: lo mismo, mínimo 0,1 s y pasos de 0,1 s.
  - Portada, créditos, textos y collages mantienen sus mínimos de ahora.
- **Ajustar al ritmo**: una foto puede quedarse en 0,1 s en lugar de 1 s. Así, con «1 golpe por foto», la foto cambia de verdad en cada golpe. Nunca se corta a mitad de golpe.
- **Transiciones**: al generar el vídeo y la vista previa, la transición de entrada de una foto se acorta sola si dura más que lo que se ve esa foto. Los ajustes guardados no cambian. Así no hay saltos cuando la siguiente foto entra antes de que esta termine de aparecer.

### 2. Preguntas y respuestas
- **¿Hasta qué mínimo debe bajar «Segundos por foto»?** (hoy 1 s, pasos de 0,5) → 0,1 s, igual que «Aparición».
- **¿Bajar también a 0,1 s la duración de cada foto (inspector y estirar en el timeline)?** (hoy 0,5 s, pasos de 0,5) → Sí: mínimo 0,1 s y pasos de 0,1 en los dos sitios.
- **Si la transición dura más que la foto (p. ej. 0,2 s de foto con 1 s de fundido), ¿qué se hace?** → Acortarla sola al generar: la transición de entrada de una foto nunca dura más que lo que se ve esa foto. Los ajustes del usuario no cambian.
- **¿Bajar también el mínimo de «Ajustar al ritmo» (hoy 1 s)?** → Sí, a 0,1 s, para que «1 golpe por foto» cambie de foto en cada golpe.

Confirmada por el usuario («sí, publica al finalizar»): se publica al acabar.

Plan aprobado por el usuario («dale»).

### 3. Fuentes analizadas
- `Views/Modules/Slideshow/SlideshowInspector.swift` (deslizadores «Segundos por foto», 1–15 en pasos de 0,5, y «Duración» de la foto, 0,5–30 en pasos de 0,5), `Model/SlideshowDocument.swift` (`setDuration`: mínimo 0,5 y redondeo a medios segundos para todo; `applyRhythm`: mínimo 1 s por foto), `CaobaCore/Slideshow/SlideshowSpec.swift` (`SlideshowTimeline.init(durations:transitions:)`: no comprobaba que la transición cupiera en la foto), `CaobaCore/Slideshow/RhythmPlanner.swift` (densidad mínima 1 golpe; sin música usa el objetivo acotado al mínimo).

### 4. Decisiones
- Sin commit hasta acabar; el usuario pidió publicar al finalizar.
- Publicado después, a petición del usuario («publica al finalizar»), en la versión 3.19.0 con release en GitHub.
- Deslizadores a `0.1...15` y `0.1...30`, paso 0,1.
- `setDuration`: las fotos redondean a décimas con mínimo 0,1 s; portada, créditos, textos y collages siguen con 0,5 s y medios segundos (no se pidió y en ellos un tiempo tan corto no tiene sentido).
- `applyRhythm`: mínimo 0,1 s por foto. Arregla también el caso sin música, donde un valor general de 0,3 s subía a 1 s.
- El recorte de la transición va en `SlideshowTimeline.init` (`min(transición, duración)`): de ahí salen el vídeo, la vista previa y el timeline de la app, así que todo cuadra con un solo cambio. Los ajustes guardados no cambian.
- Tests nuevos: «Fotos más cortas que su transición…» (Transiciones) y «Fotos muy cortas: con mínimo de 0,1 s…» (RhythmPlanner). 164 tests en verde.
- Comprobado generando una vista previa de una copia de BOOK con 0,2 s por foto y fundido de 1 s: las fotos cambian cada 0,2 s con fundidos cortos y sin saltos (hoja de contactos a 10 fps).

### 5. Alternativas descartadas
- Avisar en el inspector cuando la transición dura más que la foto, sin tocarla: el usuario prefirió que se acorte sola.
- Bajar solo el valor general y dejar la foto suelta en 0,5 s: no podría ponerse a mano lo mismo que el valor general.
- Mantener el mínimo de 1 s en el ritmo: «1 golpe por foto» seguiría saliendo cada 2 golpes a 120 ppm.
- Corte seco (0 s) como mínimo: igual que con «Aparición», se queda en 0,1 s.

### 6. Pendiente de comprobar
- `RhythmPlanner` calcula dónde cae cada corte con la transición sin recortar; con fotos más cortas que su transición, el corte puede quedar unas centésimas desplazado del golpe.
- En el timeline, una foto de 0,1 s mide 4 puntos y es difícil de pulsar o estirar.

## 2026-10-28 — Previsualización de fotos a pantalla grande con Anterior/Siguiente y casilla

### 1. La petición tal como se ha entendido
Se cambia la previsualización de la lista de fotos, la que se abre con el botón de cada fila. Como esa lista es la misma en todos los módulos, el cambio llega a todos: Slideshow (modo Fotos), Procesador, Marca de agua, Contact Sheet, Renombrar, Collage y Metadatos.

- **Tamaño**: la hoja se abre ocupando toda la ventana de CAOBA, con un margen pequeño. No es una pantalla completa aparte.
- **Foto original**: se ve la foto a su resolución real, ajustada al espacio. Ya no es una miniatura de 2000 px como máximo.
- **Anterior / Siguiente**: dos botones para recorrer todas las fotos de la lista, en su orden y con el filtro de orientación aplicado. También pasa por las desmarcadas. En la primera foto, «Anterior» queda desactivado; en la última, «Siguiente».
- **Casilla**: marca o desmarca la foto de la selección directamente. Es lo mismo que la casilla de su fila, y la lista se actualiza al momento.
- **Información**: el nombre del fichero y la posición («3 de 24»).
- **Teclado**: ← y → para ir a la anterior y la siguiente, espacio para marcar o desmarcar y Esc para cerrar.

### 2. Preguntas y respuestas
- **¿Solo en Slideshow (modo Fotos) o en todos los módulos que usan la lista de fotos?** (la previsualización es de la lista compartida `FileListView`) → En todos.
- **¿Hasta dónde llega «el mayor espacio posible»?** → Toda la ventana de CAOBA (la hoja toma el tamaño de la ventana menos un margen pequeño), no pantalla completa aparte.
- **¿Qué fotos recorren Anterior/Siguiente?** → Todas las de la lista (en su orden y con el filtro de orientación), también las desmarcadas, para poder volver a marcarlas.
- **¿Atajos de teclado?** → Sí: ← / → para anterior y siguiente, espacio para marcar o desmarcar la foto, Esc para cerrar.

Confirmada por el usuario («sí, publica al finalizar»): se publica al acabar.

Plan aprobado por el usuario («si»).

### 3. Fuentes analizadas
- `Views/Shared/FileListView.swift` (lupa de cada fila → `PhotoPreviewSheet`: hoja de 700×500 mínimo, miniatura de 2000 px, solo nombre y «Cerrar»; la lista la usan Slideshow, Collage, Contact Sheet, Procesador, Marca de agua, Renombrador y Metadatos), `Model/AppState.swift` (`files` ya filtrado por orientación y en el orden de la lista, `excludedNames`, `toggle`, `--state` y capturas con `capture.sheets`), `CaobaCore/Thumbnails/ThumbnailProvider.swift` (`makeThumbnail` con orientación EXIF; con un máximo enorme da la foto a su resolución real).

### 4. Decisiones
- Sin commit hasta acabar; el usuario pidió publicar al finalizar.
- `PhotoViewerSheet` nuevo en `Views/Shared/PhotoViewerSheet.swift` sustituye a `PhotoPreviewSheet` (borrada: nadie más la usaba).
- Tamaño medido al abrir (`PhotoViewerTarget`): contenido de la ventana principal menos 40 puntos, con un mínimo de 700×500.
- Carga en dos pasos (1600 px y luego la original) con `.task(id:)`: al pasar de foto se cancela la carga anterior y nunca se queda en blanco.
- La casilla y los botones leen y cambian `AppState` directamente, así que la lista de fondo y el contador cambian a la vez.
- Espacio con un botón oculto con atajo: marca o desmarca aunque el foco esté en otro control.
- `--state preview.photo=N` para capturas (abre el visor un segundo después de tener la lista: pedido antes, la hoja se perdía).
- Comprobado con capturas en oscuro (foto 3, horizontal) y claro (foto 1, vertical, «Anterior» desactivado): la hoja ocupa la ventana y la foto llena el alto.

### 5. Alternativas descartadas
- Solo en Slideshow: la lista es compartida y el visor sirve igual en todos los módulos.
- Pantalla completa aparte: el usuario prefirió la ventana de CAOBA.
- Recorrer solo las marcadas: no se podría volver a marcar una desmarcada por error.
- Cargar solo la original: con fotos grandes, al pasar rápido se quedaría un momento vacío.

### 6. Pendiente de comprobar
- Teclado (← → espacio Esc) y clics en Anterior, Siguiente y la casilla: no se pueden simular aquí (sin permiso de accesibilidad para enviar teclas).
- Memoria con fotos muy grandes (p. ej. 50 MP, unos 200 MB descomprimida mientras se ve).
- Con el visor abierto, la app de pruebas no se cerraba sola tras la captura (igual que pasaba con la hoja anterior); revisar si ⌘Q con el visor abierto funciona.
