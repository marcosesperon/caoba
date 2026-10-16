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
- Publicar la primera release `v3.0.0` cuando el usuario lo indique; comprobar que la landing enlaza el DMG.

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

