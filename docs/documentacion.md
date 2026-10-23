# Documentación de CAOBA (Swift)

## 1. Introducción

CAOBA es la reescritura nativa en Swift de *CAOBA Foto Utils* (Electron). La idea es sencilla: un **motor** que sabe hacer cosas con fotos y una **app** que solo pinta pantallas y llama al motor.

- **`CaobaCore`** (`CaobaCore/`): paquete Swift sin nada de interfaz. Usa ImageIO, Core Image, Core Graphics, Vision y AVFoundation, que existen igual en macOS y en iOS. Todo lo que hace está cubierto por tests (`swift test`), con imágenes generadas en el propio test.
- **App macOS** (`CaobaApp/`): SwiftUI con controles del sistema. Solo guarda estado de pantalla y delega en el motor.

Estado actual: **fases (a), (b), (c) y (d)** terminadas en cuanto a código: todos los módulos de la app antigua están migrados en macOS. Queda la fase (e), iOS.

### Cómo se trabaja

```bash
brew install xcodegen
xcodegen generate                 # genera CAOBA.xcodeproj desde project.yml
open CAOBA.xcodeproj              # desarrollar y ejecutar la app
cd CaobaCore && swift test        # motor: tests sin abrir Xcode
```

Si Xcode no está seleccionado como toolchain activo (`xcode-select -p` apunta a Command Line Tools), basta con:

```bash
export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
xcodebuild -project CAOBA.xcodeproj -scheme CAOBA -configuration Debug -destination 'platform=macOS' -derivedDataPath build/DerivedData build
```

### Componentes de interfaz comunes

- `.caobaPanel(padding:fill:border:borderWidth:)`: el estilo de bloque de toda la app (fondo tenue, borde de 1 px en el color de separador del sistema y esquinas de 8 px; se adapta solo a claro y oscuro). Cualquier grupo de controles, lista o barra va en uno, para que la ventana no parezca un montón de cosas sueltas. `.caobaDropPanel(isTargeted:)` es la variante de las barras donde se suelta algo (carpeta, foto): al arrastrar encima se tiñe de rojo y el borde se engorda. Ejemplo: `HStack { … }.caobaPanel()`.
- **Sin carpeta de origen** (módulos con `Module.usesSourceFolder`), `ContentView` deja el módulo (que incluye su barra de destino) con `.disabled` y al 45 % de opacidad: solo responden la barra de carpeta y la lateral. La barra de carpeta lleva el borde rojo (`caobaDropPanel(isTargeted:highlighted:)`) y «Empieza eligiendo o arrastrando una carpeta de fotos».
- **Barra inferior (`DestinationBar`)**: la pone cada módulo debajo de su vista, no `ContentView`, porque lleva el botón principal del módulo y solo él sabe qué hace. A la izquierda va el destino según `Module.destinationKind` (carpeta con copia/sobrescribir, carpeta de salida o fichero) y, tras una línea, las acciones que el módulo le pasa en el cierre: `DestinationBar(kind: .folder) { Button("Procesar") { run() } }`. Con `kind: .none` (Metadatos, QR) solo salen las acciones, pegadas a la derecha. Las acciones, «Guardar» y «Elegir…» no se encogen nunca; si falta sitio, se acorta la ruta por el medio. El Slideshow sigue con su propia barra (`SlideshowActionBar`).
- `BackgroundPicker(selection:)`: fondo de collage y contact sheet (Collage, Contact Sheet y collages del Slideshow): Blanco, Negro, Gris o «Personalizado», que enseña el `ColorPicker` de macOS sin transparencia. Trabaja con `CanvasColor` (motor): `.preset(CanvasBackground)` o `.custom(RGBColor)`; con un color propio, el texto y el borde salen claros u oscuros según su luminancia (`isDark`), y el relleno se crea en sRGB (`CGColor(srgbRed:…)`) para que salga el color elegido. Se guarda como antes para los tres de siempre («white») y como «#RRGGBB» para un color propio, así los presets y proyectos antiguos se leen igual. Las tarjetas de texto siguen con `CanvasBackground`.
- `HiddenSelectionNotice(selection:visible:)`: en las listas de plantillas con filtros y casillas (Componer del Collage y del Slideshow, «Aleatorias»), «N elegidas» y, si hay marcadas que los filtros esconden, «· M ocultas por los filtros» con «Desmarcar las ocultas». Componer usa todas las marcadas, también las ocultas.
- `OptionGroup(title:)`: bloque de opciones con cabecera: el título encima y los controles en un `.caobaPanel()`.
- `LabeledRow("Etiqueta") { control }` y `LabeledSlider(title:value:in:step:display:)`: etiqueta en una columna fija de 130 puntos, para que todos los controles de la app empiecen alineados. Cualquier selector, campo, stepper o deslizador con etiqueta debe usar uno de los dos. Un desplegable (`Picker` de menú) con ancho máximo lleva siempre `alignment: .leading` (`.frame(maxWidth: 220, alignment: .leading)`): en macOS no se estira hasta ese ancho y, sin alineación, SwiftUI lo centra y queda desplazado respecto a los demás controles.
- `StackedRow("Etiqueta") { control }`: la etiqueta encima de su control, para columnas estrechas (inspectores).
- `StackedSlider(title:value:in:step:onReset:display:)`: deslizador para columnas estrechas (inspectores). La etiqueta va arriba y debajo el deslizador, el valor y, si se pasa `onReset`, el botón de volver al valor global. En 300 puntos la fila de `LabeledSlider` dejaría el deslizador en nada.
- `TemplateView`, `CellPhotoView`, `TemplatePicker`, `TemplateFilters`: plantillas de collage y celdas con foto arrastrable.
- `FileListView`: lista de fotos de la carpeta con casilla general, orden y filtro de orientación, en su propio bloque. Con `allowsReorder` (Slideshow, Collage, Contact Sheet) cada fila lleva un asa ≡, el cursor pasa a mano abierta al pasar por encima y la cabecera dice «Arrastra para cambiar el orden». «Orden» ofrece Nombre, Fecha y **Manual**: arrastrar activa Manual (`AppState.isManualOrder`, con el orden en `manualNames`, que se vuelve a aplicar tras cada lectura de la carpeta: al abrirla, al cambiar el filtro…); elegir Nombre o Fecha desde Manual pide confirmación (`sortAutomatically(by:)`). Manual es solo de la app: el `SortMode` del motor (también el de «Ordenar por» del Renombrador) sigue con nombre y fecha. El orden manual se guarda en la carpeta en la sección común `fileOrder` del `.caoba` (`FileOrderSettings`, en el motor), que usan Slideshow, Collage y Contact Sheet: se lee al abrir la carpeta, se guarda al arrastrar o elegir Manual, se quita al volver a Nombre o Fecha y «Reiniciar» la borra. El Slideshow sigue guardando su `fileOrder` y `sortMode: "manual"`, pero manda la sección común; solo en proyectos de antes sin ella, su orden manual pasa a ser el común (`adoptManualOrder`). Cada fila tiene una lupa, visible al pasar el ratón, que abre la foto en grande; la miniatura no tiene clic, y el clic de selección de la fila solo se pone cuando la lista lo usa (Metadatos), para poder arrastrar desde cualquier sitio de la fila. Con `framed: false` va sin bloque, para quien ya la mete en uno (la pestaña Fotos/Collages del Slideshow, que es un solo bloque con el modo, las acciones y la lista).
- `CollageResultView(row:options:)`: el collage renderizado con el motor y las opciones reales, a resolución de pantalla (lado mayor 1600 px, o el que se pida con `side`), en segundo plano; se recalcula al cambiar la fila o las opciones. La separación y las esquinas se encogen en proporción (`CollageOptions.scaled(toLongestSide:)`), así que la versión pequeña se ve igual que la grande. `CollageViewModePicker` es el conmutador «Encuadre / Resultado» que la acompaña en el editor de foco de Collage y en el inspector de collage del Slideshow.
- **Pantalla de Collage**: arriba las opciones (izquierda) y la lista de fotos (derecha); abajo, a todo el ancho, el bloque de la secuencia. Entre las dos zonas hay un divisor propio (`BottomSplit`, porque `VSplitView` no respeta la altura inicial) que empieza con el bloque a 260 pt y recuerda dónde se deja (`collage.sequenceBlockHeight` en las preferencias).
- **Bloque de abajo** (`SequenceBlock`: título, cabecera con botones y recuento, y la tira). Une selección y previsualización: la tira (`CollagePreview`) dibuja cada collage con el motor real y las opciones de salida (`CollageResultView`, 900 px de lado mayor, uno por collage para que al tocar uno solo se redibuje ese), y sobre cada uno: clic → editor, arrastrar → cambia el orden (`SequenceItemActions`, `moveItem`), clic derecho → menú. Según el modo:
  - **Secuencia** (`CollageSequenceEditor`): Componer, Añadir, Ajustar foco, Vaciar y «N de M fotos asignadas · K collages»; menú «Editar enfoque» y «Quitar».
  - **Aleatorias**: «Otro reparto» y el recuento; mismas acciones. El reparto ya no se sortea al pulsar Generar: se sortea al entrar en Aleatorias y cada vez que cambian las fotos, las plantillas marcadas o el «Enfoque» (si no es «Centro», los focos se calculan en segundo plano y Generar espera a que acaben). Ese reparto (`randomSequence` en `CollageView`) es lo que se ve, lo que se retoca y lo que se genera; no se guarda en el `.caoba`, como la secuencia.
  - **Carrusel** (`CarouselEditor`): Componer, Añadir, Ajustar foco, Vaciar y «N de 10 diapositivas…». La tira se dibuja de una pieza (para que los cortes sean exactos, con `CarouselCuts`) y encima va una zona invisible por tramo que recoge clic, arrastre y menú («Editar encuadre», «Cambiar tramo…», «Quitar»). El «Formato» está en la columna de opciones.
- `CarouselFocusEditorSheet`: editor de encuadre de un tramo del carrusel. El tramo en grande con sus cortes (numerados como en el carrusel), cada foto se arrastra dentro de su celda, flechas para pasar de tramo, «Centrar celdas» y «Encuadre / Resultado».

### Changelog y novedades (`Changelog`, `WhatsNewSheet`)

`CHANGELOG.md` en la raíz del repo: una sección por versión (`## 3.1.0 — 2026-10-16`) con viñetas cortas en lenguaje de usuario, en español. Se incluye en la app como recurso. Al arrancar, si la versión guardada en `caoba.lastSeenVersion` es menor que la actual, se abre «Novedades» con las secciones de las versiones intermedias (en instalación nueva no sale nada); «Novedades de CAOBA» en el menú Ayuda enseña todo el historial. El script de release usa la sección de la versión como notas de la release y no publica si falta. **Antes de cada release hay que escribir la sección nueva.** Para probar: `--state demo.lastSeen=3.0.1`.

### Actualización dentro de la app (`Updater`)

Cuando hay una versión nueva, la banda ofrece «Actualizar ahora»: descarga el DMG de la release (progreso y cancelación), le quita la cuarentena, lo monta, comprueba que trae `CAOBA.app` con la versión anunciada y firma válida, sustituye la app instalada (copia junto a la actual, intercambio y borrado de la antigua), quita la cuarentena a la copia, desmonta y relanza. Si la app no está en una carpeta escribible, o corre desde un DMG o desde la carpeta de compilación, abre el DMG descargado para arrastrarla a mano. Ganchos de prueba: `--state update.force=1` (banda con la última release), `update.auto=1` (lanza la actualización) y `update.target=/ruta/CAOBA.app` (sustituye esa copia en lugar de la app en ejecución, sin relanzar).

### Releases

`Tools/make-release.sh` lee la versión de `MARKETING_VERSION` en `project.yml`, pasa los tests del motor, genera el proyecto, compila en Release un **binario universal** (`ARCHS="arm64 x86_64"`), lo firma ad hoc (sin Developer ID todavía), crea `dist/CAOBA-<versión>.dmg` con `hdiutil` y, con `--publish`, crea la etiqueta `v<versión>`, la sube y publica la release en GitHub con `gh` y notas generadas de los commits. Con `--publish`, antes de compilar comprueba que el email de git del repo es `marcosesperon@gmail.com` y que la cuenta activa de `gh` es `marcosesperon`, para que commits y releases queden siempre a nombre de la cuenta personal; si no, para y dice cómo arreglarlo (`git config user.email …` o `gh auth switch --user marcosesperon`). Para subir de versión: cambiar `MARKETING_VERSION` (y `CaobaCoreInfo.version`) y volver a lanzar el script. El DMG ocupa unos 12 MB con exiftool incluido.

**Firma Developer ID y notarización** (cuando haya cuenta de desarrollador): exportar el certificado «Developer ID Application» al llavero, guardar un perfil de notarización con `xcrun notarytool store-credentials caoba --apple-id <correo> --team-id <EQUIPO> --password <contraseña de app>` y lanzar el script con las variables `CAOBA_SIGN_IDENTITY="Developer ID Application: Nombre (EQUIPO)"` y `CAOBA_NOTARY_PROFILE=caoba`. El script firma con hardened runtime y timestamp, envía el DMG a Apple, espera el resultado y grapa el ticket. Sin esas variables sigue firmando ad hoc.

### Capturas de pantalla

La app admite argumentos de arranque pensados para generar las capturas de la landing (y para pruebas): `--folder <ruta>` abre una carpeta, `--module <id>` elige la sección (`slideshow`, `collage`, `contactSheet`, `processor`, `watermark`, `metadata`, `renamer`, `qr`, `shutterCount`), `--window <ancho>x<alto>` fija el tamaño de la ventana, `--state clave=valor` (repetible) deja un módulo con contenido (`collage.tab=random`, `collage.aspect=16:9`, `qr.text=https://…`, `watermark.png=/ruta/marca.png`, `renamer.pattern={YYYY}-{MM}-{DD}_{n}`) y `--screenshot <salida.png>` guarda la ventana pasados `--delay` segundos (8 por defecto) y cierra la app. La captura se hace de la propia ventana, así que no pide permiso de grabación de pantalla, y sale a la resolución de la pantalla (en Retina, el doble del tamaño pedido). Ejemplo:

```sh
open -n build/DerivedData/Build/Products/Debug/CAOBA.app --args \
  --folder "/ruta/a/las/fotos" --module slideshow --window 1440x900 \
  --screenshot /tmp/slideshow.png --delay 10
```

Las capturas de la landing están en `assets/screenshots/` a tamaño real (2880×1800) en PNG y WebP: la página usa `<picture>` con WebP y PNG de respaldo, los enlaces a la imagen completa y la imagen social (`og:image`) van en PNG.

### Reglas de la casa

- Lo temporal va siempre al directorio temporal del sistema (`TempFiles`), nunca a la carpeta de fotos.
- Los ficheros de salida se escriben primero en temporal y luego se mueven (`FileOperations.commit`), así nunca queda una foto a medias.
- Los trabajos largos son `async`, informan por `ProgressHandler` y se cancelan con la cancelación normal de `Task` (lanzan `CaobaError.cancelled`).
- Los errores del motor son casos de `CaobaError`; el texto para el usuario lo pone la app (`JobRunner.describe`).
- Comentarios en español; nombres de tipos y funciones en inglés.

---

## 2. Parametrización

### Formatos (`SupportedFormats`, `OutputFormat`)

| | Lectura | Escritura |
|---|---|---|
| JPEG, PNG, TIFF, HEIC/HEIF | sí | sí |
| WebP, AVIF | sí (macOS 13+) | no (decisión P9) |
| RAW (NEF, CR2, CR3, ARW, ORF, RW2, RAF, DNG, PEF) | sí, pero solo donde se pida (`includeRaw`) | no |

`OutputFormat.matching(extensionOf:)` decide el formato "mantener original": lo que no se puede escribir (WebP, AVIF, RAW) sale como JPEG.

### Escaneo de carpeta (`FolderScanner`)

- `scan(folder:sort:orientation:progress:)` → `[ScannedFile]` con URL, tamaño visible (ya girado por EXIF) y fecha de captura.
- `sort`: `.name` (orden natural, "img2" antes que "img10") o `.date` (EXIF `DateTimeOriginal`, si no hay, fecha de creación del fichero).
- `orientation`: `.all`, `.horizontal` (ancho ≥ alto), `.vertical`.
- Ignora ocultos, lo que empieza por `_caoba_`, subcarpetas y extensiones no soportadas. No es recursivo.

### Miniaturas (`ThumbnailProvider`)

Actor con caché (`NSCache`, 2000 entradas) y concurrencia limitada al número de núcleos. Usa el thumbnail EXIF embebido si existe, y aplica la orientación. `thumbnail(for:maxPixelSize:)` devuelve un `CGImage` o `nil`.

### Procesador (`ImageProcessor`, `ProcessingOperations`)

| Opción | Valores | Notas |
|---|---|---|
| `autorotate` | Bool | Aplica la orientación EXIF y la pone a 1 en la salida |
| `crop` | `(AspectRatio, CropAnchor)` | Anclas: center, top, bottom, left, right |
| `resizeMaxDimension` | Int | Lado mayor; nunca amplía |
| `quality` | 1-100 | Solo JPEG y HEIC |
| `format` | `OutputFormat?` | `nil` = mantener |

Modos de guardado (`SaveMode`): `.newCopy(outputFolder:)` (misma carpeta → sufijo `_processed`) o `.overwrite`. Al sobrescribir cambiando de formato se borra el original con la extensión antigua. EXIF, GPS y perfil de color viajan con la salida.

### Marca de agua (`Watermarker`, `WatermarkOptions`)

| Opción | Valores |
|---|---|
| `mode` | `.single` / `.tiled` |
| `position` | topLeft, topRight, center, bottomLeft, bottomRight (padding 10 px) |
| `sizePercent` | % del **lado corto** de la foto |
| `opacity` | 0-100 |
| `spacing` + `spacingUnit` | separación del mosaico en px o % del lado corto |
| `rotation` | grados por repetición (mosaico) |

La salida mantiene el formato del original (sufijo `_watermarked` si es copia en la misma carpeta).

### Metadatos (`MetadataService`, `PhotoMetadata`, `MetadataEdit`)

- `read(url)` devuelve artista, copyright, descripción, fecha, cámara, objetivo, dimensiones, ISO, exposición, f, focal, flash, software y GPS. Mira EXIF/TIFF primero y XMP de respaldo.
- `write(edit, to:, stripOthers:)` escribe **sin recomprimir**. En `MetadataEdit`, `nil` = no tocar, cadena vacía = borrar. `gps`: `.some(nil)` borra, `.some(coord)` fija, `nil` no toca. `stripOthers` deja solo lo indicado.
- `writeBatch` y `writePerFile` para lotes con progreso.
- Cómo lo hace por dentro (importante si algo falla): ImageIO solo admite metadatos XMP en este camino; artista = `dc:creator`, descripción = `dc:description`, copyright = `dc:rights`, fecha = `photoshop:DateCreated`, GPS = `exif:GPSLatitude/Longitude`. Los tags EXIF/TIFF clásicos se actualizan si existían pero no se crean. Tras escribir se relee el fichero y, si no coincide, se lanza `metadataWriteFailed`.

### Renombrador (`Renamer`)

Cuatro planes, todos devuelven `[RenameEntry]` (original → nombre nuevo) con colisiones resueltas con `_2`, `_3`…:

- `patternPlan(files:options:)` con `PatternRenameOptions`: patrón con `{nombre}`, `{n}`, `{camara}`, `{objetivo}`, `{ancho}`, `{alto}`, `{orientacion}` (H/V/C) y tokens `YYYY MM DD hh mm ss`; orden por nombre o fecha; dígitos (0 = automático, mínimo 2) e inicio del contador; mayúsculas (`TextCase`); saneado (`SanitizeOptions`: acentos, espacios, especiales). Solo lee EXIF o dimensiones si el patrón los usa.
- `autofixPlan(files:)`: `Foto-1` → `Foto-001` si todos comparten prefijo y sufijo.
- `searchReplacePlan(files:search:replace:)` y `prefixSuffixPlan(files:prefix:suffix:)`.

`execute(plan:saveMode:)`: `.newCopy` copia a la carpeta de salida; `.overwrite` renombra en sitio, pasando por nombres intermedios solo si algún nombre nuevo choca con uno viejo, y **registra la operación** en `RenameHistory`, que es la sección `renameHistory` del `.caoba` de la carpeta, para poder deshacerla. `RenameHistory.undoLast(in:)` devuelve los nombres anteriores de la última operación (saltando y avisando de los ficheros que ya no estén con el nombre nuevo) y la quita del registro; se puede repetir hacia atrás. En la app, el Renombrador muestra "Último renombrado: N archivos, fecha" con el botón Deshacer cuando la carpeta tiene historial.

### QR (`QRContent`, `QRGenerator`, `QROptions`)

- `QRContent` tiene los nueve tipos y `payload` da el texto: `WIFI:T:…;S:…;P:…;H:true;;`, vCard 3.0, `mailto:`, `tel:`, `sms:…?body=…`, `geo:lat,lon`, `VEVENT`.
- `QROptions`: `size` (64-4096 px), `foreground`/`background` (`RGBColor`, con `init?(hex:)`), `correction` L/M/Q/H, `marginModules`, `logoPercent` (5-50).
- `QRGenerator.make(text:options:logo:)` → `CGImage` nítido (sin interpolar); `png(...)` → `Data`. La app sube la corrección a Q cuando hay logo.

### Plantillas de collage (`CollageTemplate`, `CollageTemplates`)

- 1049 plantillas (112 superpuestas rectas, reservadas para el slideshow; 70 redondas; 77 giradas, 49 de ellas tarjetas con marco; 112 en diagonal y polígonos) en `Collage/templates.json`, un JSON compacto en una sola línea. Las 570 primeras se exportaron tal cual de la app antigua con Node (`getTemplates()` ya deduplicado); en la 3.9.0 se añadieron 220 más, de 36 diseños nuevos (tiras de 5 a 9 bandas, rejillas de 7 a 9 fotos, tiras + foto grande, ladrillo y escalera, fondo con tarjetas), cada una tras las de su mismo número de fotos. Para añadir plantillas se edita ese JSON, manteniendo el formato compacto; el test `CollageTemplatesTests.catalog` vigila las cuentas, que no haya identificadores repetidos y que las celdas caigan dentro del lienzo. Prueba: `--state collage.photos=9` abre «Aleatorias» filtrado por ese número de fotos.
- **Celdas redondas** (3.10.0): `CollageCell.shape = .circle` (opcional en el JSON; las demás no lo llevan). El círculo va en el cuadrado centrado dentro de su celda (`CollageRenderer.squareInside`), así es perfecto aunque haya título, y va el último de su plantilla para dibujarse encima. El motor pinta antes un aro del color del fondo (`ringWidth`: la separación, con un mínimo) y luego la foto recortada en redondo; `TemplateView` hace lo mismo en el selector, el editor de encuadre y el timeline (`ringColor`). Tipo propio `TemplateType.round` («Redondas», `CollageTemplate.isRound`): sale también sin pedir superpuestas, así que aparece en Collage y en el Slideshow, y el selector «Tipo» sale ahora siempre (Básicas, Superpuestas solo en el Slideshow, Redondas). Prueba: `--state collage.type=round`.
- **Fotos giradas** (3.11.0): `CollageCell.rotation` en grados (positivo hacia la derecha, alrededor del centro; `angle` = 0 si no lleva). El encuadre se calcula sobre la celda sin girar y el motor gira el contexto alrededor del centro de la celda antes de dibujar marco, sombra y foto. Tipo `TemplateType.rotated` («Giradas», `CollageTemplate.isRotated`): manda sobre los demás y sale siempre, también en Collage aunque sea de marco y sombra (`overlap` decide el estilo: tarjetas con marco o rejilla girada sin marco). `TemplateView` gira cada celda con `rotationEffect`, y `CellPhotoView(rotation:)` mide el arrastre en coordenadas de la ventana y lo gira al revés que la celda, así la foto se mueve hacia donde se arrastra. El test `rotatedCells` comprueba que ninguna celda girada se salga del lienzo.
- **Diagonales y polígonos** (3.13.0): `CollageCell.points` (esquinas en 0-1 sobre el lienzo, en orden; `polygon`), con `x, y, w, h` como la caja que lo contiene, así el encuadre, el reparto y el Slideshow siguen usando la caja. Solo piezas convexas. El motor pasa la pieza a píxeles y la encoge (`CollageRenderer.polygonInPixels` / `insetPolygon`): cada lado se desplaza la mitad de la separación, o la entera si va por el borde del lienzo, y cada esquina nueva es el cruce de los dos lados desplazados, así el hueco mide igual en todas las direcciones. La foto se encuadra sobre la caja de la pieza encogida (`boundingBox`) y se recorta con su forma; las esquinas redondeadas no se aplican. `TemplateView` hace lo mismo con `PolygonShape`. Tipo `TemplateType.polygon` («Diagonales», `isPolygon`), en Collage y en el Slideshow. Tres familias: cortes inclinados, abanicos y figura central (rombo, hexágono). Los tests comprueban que cada pieza es convexa, que entre todas cubren el lienzo y que el hueco de una diagonal mide la separación.
- Cada plantilla: `id`, `name`, `photos`, `aspect` (`[16, 9]`), `overlap`, `cells` con `x y w h` normalizados (0-1).
- `CollageTemplates.filter(photos:aspectLabel:includeOverlap:)`, `template(id:)`, `aspectLabels` (de más apaisada a más vertical). `canvasSize(longestSide:)` da el lienzo.

### Punto de foco (`FocusDetector`, `FocusMode`)

- Modos: `.center`, `.saliency`, `.faces`. Devuelve `FocusResult` con un punto normalizado (origen arriba-izquierda) y si hubo caras.
- `.saliency` usa Vision "objectness" (dónde está el sujeto; centro ponderado por confianza) y, si no detecta objetos, el centroide del mapa de atención. Se eligió objectness porque la atención tiene sesgo al centro y localiza peor para recortar.
- `.faces` usa el centro del rectángulo que engloba todas las caras; sin caras cae a saliencia.
- Trabaja sobre una versión de 1024 px de la foto y cachea por fichero y modo. Es un `actor`; `FocusDetector.detect(image:mode:)` es la parte estática testeable.

### Collage (`CollageRenderer`, `CollageOptions`, `CollageRow`)

| Opción | Valores | Notas |
|---|---|---|
| `longestSide` | 100-15.000 px | Lado mayor del lienzo |
| `gap` | px | Medio gap entre celdas vecinas, gap entero contra el borde |
| `background` | white / black / gray | Color de texto y borde a juego |
| `cornerRadius` | px | Máscara redondeada por celda |
| `shadowIntensity` | 0-100 | Solo plantillas overlap (marco blanco + sombra) |
| `title` | texto | Franja superior proporcional al ancho (5 %, mínimo 50 px). La app antigua usaba 50 px fijos, que en 3000 px era ilegible |
| `logo` | `LogoOptions` | Posición, % del ancho, opacidad |

- `group(files:templates:mode:)` reparte las fotos en filas consumiéndolas en orden: `.sequential` cicla las plantillas; `.random` elige al azar entre las que caben en lo que queda. Devuelve también cuántas fotos sobran.
- `assignByAspect(photoAspects:cellAspects:)` empareja fotos y celdas por proporción (celdas más extremas primero). `reorderByAspect(row)` lo aplica a una fila.
- `render(row, options)` compone un collage; `generate(rows:options:outputFolder:)` escribe `collage.jpg` o `collage_01.jpg`, `collage_02.jpg`…
- Las fotos se decodifican ya reducidas al tamaño de su celda (`PhotoLoader`) para no cargar originales de 50 MP enteros.


### Carrusel de Instagram (`Carousel`, `CarouselFormat`, `CarouselTemplates`)

Tercera opción de «Plantillas» en Collage (Secuencia, Aleatorias, **Carrusel**; `CollageMode` en la app). Un carrusel es una tira ancha de hasta 10 diapositivas (`Carousel.maxSlides`, el máximo de Instagram) que se exporta cortada.
- **Formatos** (`CarouselFormat`): 4:5 (1080×1350), 1:1 (1080×1080) y 3:4 (1080×1440); cada diapositiva mide 1080 px de ancho (`Carousel.slideWidth`).
- **Tramos**: catálogo propio en `Collage/carousel_templates.json` (30 tramos, sin formato: `id`, `name`, `slides` de 1 a 5 y `cells` en 0-1 sobre el tramo entero). `CarouselTemplates` los ofrece en los tres formatos como plantillas normales (`carousel_<formato>_<id>`, con `slides` y `aspect` = slides × proporción); no salen en los selectores de collage, pero `CollageTemplates.template(id:)` los encuentra, así la secuencia (`SequenceItem`) sirve igual. Las celdas de fondo van primero; las de encima, después: sin marco (como en los carruseles de referencia) o con `framed: true` (marco blanco y sombra; `CollageCell.framed` manda sobre el `overlap` de la plantilla).
- **Encadenar y cortar**: `Carousel.combine` une los tramos en una plantilla de N diapositivas; `renderPanorama` la dibuja con `CollageRenderer` a `N × 1080` px de ancho (sin título); `slices` la corta en diapositivas exactas; `generate` escribe en una subcarpeta nueva de la carpeta de salida (`carrusel`, `carrusel_2`…) `01.jpg`…`NN.jpg` (orden de subida) y `panoramica.jpg`. `limited` recorta a 10 diapositivas.
- **Pantalla**: el formato en la columna de opciones y, en el bloque de abajo (`CarouselEditor`), Componer (al azar o según el contenido, con los tramos marcados y hasta 10 diapositivas), Añadir, Ajustar foco, Vaciar, «N de 10 diapositivas» y el carrusel dibujado de verdad con los cortes en rojo y el número de cada diapositiva. Clic en un tramo abre su editor de encuadre (`CarouselFocusEditorSheet`); arrastrar lo cambia de sitio; clic derecho para editar, cambiar o quitar. Al cambiar de formato cada tramo pasa al mismo tramo del formato nuevo.
- **Se guarda por carpeta** (sección `collage`, `CarouselSettings`): formato, modo de Componer, reordenar y tramos marcados (sin formato). La secuencia, como la del Collage, no se guarda.
- Pruebas: `--state collage.tab=carousel`, `carousel.compose=1` (compone al azar en cuanto hay fotos), `carousel.editor=1` (abre además el editor del primer tramo) y `collage.run=1` (pulsa «Generar»).

### Reparto por contenido (`PhotoProfile`, `ContentComposer`)

Al componer una secuencia de collages, además del reparto aleatorio, se puede pedir «Según el contenido»: la app analiza cada foto marcada (caras y, si no hay, objetos salientes, con Vision sobre una miniatura y con caché) y el motor decide, para cada grupo de fotos consecutivas, qué plantilla permitida les sienta mejor, cuántas fotos entran en el grupo y qué foto va en cada celda.

- `PhotoProfile`: proporción, caja del sujeto (normalizada, origen arriba‑izquierda) y número de caras. `focusPoint` es el centro del sujeto y se usa como foco del recorte.
- `ContentComposer.score(photo:cell:in:)`: cuánto del sujeto sobrevive al recorte de la celda (mismo recorte que el render) y si casa la orientación, con bonificación por poner caras y sujetos grandes en celdas grandes y penalización por meter grupos (3 o más caras) en celdas pequeñas.
- `ContentComposer.compose(profiles:templates:allowReorder:)`: programación dinámica sobre la posición y la plantilla del grupo anterior, manteniendo el orden; penaliza repetir plantilla (o tamaño de grupo) y las plantillas de una foto salvo para fotos que destacan; al final una pasada de variedad cambia las plantillas que ya salieron en los tres grupos anteriores por otra del mismo tamaño si pierde poca puntuación. Con `allowReorder` intercambia fotos entre collages vecinos mientras mejore. Devuelve `ComposedRow` (plantilla, índice de foto por celda, focos) y las fotos sobrantes. Los pesos están como constantes al principio del tipo (`repeatPenalty`, `singlePenalty`, `varietyWindow`…).

En la app (`ContentComposition`) el resultado se convierte en un nuevo orden de las fotos marcadas (`AppState.reorderCheckedFiles`) y una secuencia con el foco ya puesto. Es una propuesta: luego se edita igual que cualquier secuencia. Para probarlo desde línea de comandos: `--state collage.autocompose=content` (y `collage.reorder=1`); para capturar la hoja, `--state collage.compose=content --state capture.sheets=1`.

### Contact Sheet (`ContactSheetRenderer`, `ContactSheetOptions`)

| Opción | Valores |
|---|---|
| `columns`, `thumbSize` | Columnas y lado de miniatura (grid) o ancho de columna (masonry) |
| `layout` | grid (celdas con padding 10 px) o masonry (sin huecos, columna más corta) |
| `cropMode` | contain (foto entera centrada) o cover (rellena la celda); masonry siempre rellena |
| `showFilenames`, `showNumbering` | Etiqueta bajo la miniatura, acortada a 20-25 caracteres |
| `title` | Franja de 40 px arriba |
| `background`, `showBorder`, `borderWidth`, `logo`, `quality` | |

`estimatedSize(fileCount:options:)` para avisar del tamaño antes de generar (solo grid); límite 30.000 px por lado. `render(files:options:)` y `generate(files:options:output:)`.

### Slideshow (`SlideshowSpec`, `SlideshowRenderer`)

**Cómo funciona por dentro.** El vídeo se escribe fotograma a fotograma con `AVAssetWriter` (H.264 por hardware, 25 fps, etiquetas de color BT.709). Cada fotograma se compone en Core Image: la foto escalada entera sobre negro (sin Ken Burns) o el recorte Ken Burns del instante (que llena el lienzo), el fundido con la siguiente foto (`CIDissolveTransition`) y la marca de agua. No se escriben fotogramas a disco ni hay límite de fotos. Si hay música, el vídeo se escribe primero sin audio en temporal y después `AudioMuxer` lo copia tal cual (sin recodificar) añadiendo la mezcla en AAC.

| Pieza | Qué es |
|---|---|
| `VideoFormat` | Los seis formatos (`169_h`, `916_v`, `45_v`, `45_h`, `23_v`, `23_h`) con su resolución. Mismos identificadores que la app antigua |
| `SlideshowPhoto` | Foto (o portada/créditos) con duración, efecto Ken Burns resuelto y puntos |
| `SlideshowSpec` | Fotos, formato, fps, transición (fundido de 1 s), marca de agua, audio, ajustes Ken Burns, salida y modo preview (lado mayor de 640 px, `previewLongestSide`, misma proporción y píxeles pares) |
| `SlideshowTimeline` | Cuándo entra y sale cada foto. Con transición, la foto i+1 empieza a entrar cuando a la i le queda 1 s, igual que el `xfade` antiguo: duración total = suma de duraciones + 1 s |
| `VideoWriter` | Escritura de vídeo; `composeFrame(at:)` es la parte testeable píxel a píxel |
| `AudioPlan` | Dónde empieza y acaba cada pista: automático (al acabar la anterior menos su cruce) o en un segundo del vídeo; fundidos de entrada/salida en segundos (`AudioSegment.fadeInSeconds` / `fadeOutSeconds`), ganancia y `trackID`. Cada cambio es un cruce que dura lo que diga la pista que entra (`AudioTrack.crossfade` o, si es `nil`, el general `AudioOptions.crossfade`, 3 s por defecto, 0 = corte seco): la que entra sube en ese tiempo y la que sale sigue sonando lo mismo mientras baja. Los cruces se calculan **por orden de inicio en el vídeo**, no por el de la lista (una pista con inicio fijo puede ir más abajo y empezar antes). El fundido final dura `AudioOptions.fadeOutDuration` (3 s por defecto). Cada `AudioTrack` admite `trimStart` y `trimEnd` (segundos de la canción): se salta la intro, se corta en el "Hasta" y la última pista repite ese tramo hasta el final del vídeo. Con `loopPlaylist` (por defecto) y más de una pista, al acabar la lista se vuelve a la primera con su cruce. `AudioMuxer.makeComposition` (pública) monta la mezcla con las rampas; la usa el vídeo y la app para escuchar un cruce |
| `LoudnessMeter` | BS.1770-4: filtro K, bloques de 400 ms, gating absoluto y relativo. `measure(url:)` devuelve LUFS; `gain(from:to:)` la ganancia hacia -16 LUFS. Verificado con el tono de referencia de EBU Tech 3341 (-23 dBFS → -23 LUFS) |
| `AudioMuxer` | `AVMutableComposition` + `AVMutableAudioMix` (rampas de volumen) → AAC 192 kbps; vídeo en passthrough |
| `VideoMetadata` | Etiquetas del MP4 (`spec.metadata`): descripción (la app pone «Creado con CAOBA — https://caobafoto.com», traducida), fecha de exportación y, si hay autor en Ajustes, autor e intérprete. Las escriben `VideoWriter` y `AudioMuxer`, así que van en todos los vídeos, con música o sin ella |
| `KenBurns` | Geometría: `cropRect(imageSize:targetSize:effect:t:intensity:focus:)` para los 10 efectos automáticos, `customCropRect` para inicio/fin con zoom, `progress(...)` con retardo, porcentaje y easing. Misma matemática que `kenburns.js` |
| `CollageSlideshow` | Modo collage: renderiza cada collage con 0, 1, 2… fotos visibles en JPEG temporales y los convierte en `SlideshowPhoto` con duraciones (0,5 s el lienzo vacío, `reveal` por foto, `hold` al final) |
| `SlideshowPreset` | Sección `slideshow` del `.caoba`, con las claves v1 de la app antigua más `kenBurns.byFile`/`pointsByFile` (por nombre de fichero, en vez de por índice) y `collage.sequence` |

**Pantalla del Slideshow (rediseño de 16-10-2026).** Funciona como un editor de vídeo sencillo:
- Pestañas arriba: **Fotos** (o Collages): modo, lista de fotos de la carpeta y "Asignar efectos" (o Componer, Añadir, Ajustar foco y Vaciar); **Vídeo**: formato, ritmo, fundido y Ken Burns global (o aspecto de los collages); **Portada y marca**: portada, créditos y marca de agua; **Música**: pistas y opciones. Al seleccionar algo en el timeline se abre una pestaña contextual (Foto, Pista, Collage, Portada o Créditos) y al deseleccionar se vuelve a la anterior.
- Timeline a toda la anchura en la parte inferior, con cabecera (duración total y zoom) y regla de tiempo. Cada tarjeta (portada, foto o collage, créditos) tiene la anchura de su duración. Clic selecciona; arrastrar reordena; el asa del borde derecho estira la duración de esa foto (las fotos sin duración propia siguen el valor global); la casilla que aparece al pasar el ratón quita la foto del vídeo; Suprimir y flechas funcionan con el teclado.
- Carriles de música bajo las tarjetas, en la misma escala: cada bloque se arrastra para fijar su inicio (con imán a los inicios de foto, al final de la pista anterior y al 0) y se estira por los bordes para el recorte Desde/Hasta. Las repeticiones de la lista se dibujan atenuadas. Al añadir una pista se coloca "tras la anterior". Clic derecho en el bloque: «Cambiar fichero…» y «Quitar pista».
- **Cambiar el fichero de una pista** («Cambiar fichero…» en su editor, en su fila de la pestaña Música y en el clic derecho del timeline; helper `chooseTrackFile(for:doc:)`): abre el selector en la carpeta del fichero actual y `SlideshowDocument.replaceTrackFile(_:with:)` cambia solo esa pista, conservando inicio, recorte y orden. Si la canción nueva es más corta que el recorte, «Hasta» pasa a «hasta el final» y «Desde» se adelanta lo justo para que suene al menos 1 s; lo ajustado se cuenta en una alerta (`trackFileNotice`). Si no se puede leer el fichero, no cambia nada y lo avisa. A diferencia de «Localizar…» (`relocate`), no toca otras referencias a la misma ruta. Prueba: `--state slideshow.replaceTrack=/ruta.m4a` (cambia la primera pista; guarda la configuración de la carpeta, así que mejor sobre una copia).
- **Reordenar pistas**: en la pestaña Música cada fila (con asa ≡) se arrastra y se suelta sobre otra (`moveTrack(_:onto:)`, que usa el `moveItem` compartido con la tira de Collage). Cada pista conserva su forma de empezar: las de segundo fijo no se mueven en el vídeo y las de «tras la anterior» se encadenan según el orden nuevo, que también es el de «Repetir la lista».
- **Cruces entre pistas**: en Opciones de la pestaña Música, «Cruce entre pistas» (0–10 s de 0,5 en 0,5; 0 = «Corte seco») y «Fundido de salida» con su duración (1–10 s). En el editor de una pista, «Entrada (cruce con la anterior)» con valor propio y vuelta al general; solo sale si algún tramo de esa pista entra tras otro. Se guardan en el preset (`audio.crossfade`, `audio.fadeoutDuration`, `musicTracks[].crossfade`); sin ellos, 3 s. En el timeline cada tramo dibuja su volumen (`VolumeRamps`: zona oscurecida por encima y una línea en la rampa), también en las repeticiones y el fundido final; `TimelineFades.seconds` recorta las rampas igual que el mezclador. En la Preescucha, «Escuchar entrada» / «Escuchar salida» (`CrossfadeListen` con `MixPreviewPlayer`) suenan la mezcla real del vídeo desde 5 s antes hasta 5 s después del cruce, sin generar nada; si cambia la música mientras suena, se para.
- **Cuadrar cruces** (botón en Música → Ritmo, `SlideshowDocument.alignCrossfades()`): en cada cambio de pista, el cruce empieza en un golpe de la que sale y la que entra arranca en uno de sus golpes, para que los golpes de las dos caigan juntos (como un DJ, sin cambiar la velocidad de ninguna). El cálculo está en el motor, `CrossfadeAligner.align(_:)`: lleva el inicio de la que entra al golpe más cercano de la que sale (buscándolo en la vuelta que toque si la que sale repite su tramo) y su Desde a su propio golpe más cercano, como mucho medio golpe cada uno. No cuadra si alguna no tiene ritmo claro, si los tempos difieren más de un 6 % (`tempoTolerance`; el doble y la mitad cuentan como compatibles), si es un corte seco o si no queda al menos 1 s antes del Hasta. La app reutiliza el análisis de «Ajustar al ritmo», va en el orden en que suenan, solo toca la primera vez que suena cada pista (las repeticiones se colocan solas), deja la pista con inicio fijo y recalcula los tramos tras cada ajuste. El resultado sale en `crossfadeMessage`. No toca las fotos: para que sigan los golpes, «Ajustar al ritmo» después. Prueba: `--state slideshow.alignCrossfades=1`.
- Editores (al pulsar un elemento del timeline): foto (efecto, duración, encuadre de inicio y fin con "Enfocar caras" y previsualización); portada o créditos (imagen y duración); pista (inicio en el vídeo, Desde/Hasta, quitar y «Preescucha»: un reproductor del tramo Desde → Hasta con play/pausa y barra de posición, `TrackPreviewPlayer` sobre `AVAudioPlayer`, sin fundidos ni normalización; si cambia Desde mientras suena salta allí, si cambia Hasta para al llegar, al llegar a Hasta vuelve a Desde y se para al cerrar el editor o pasar a otro elemento). Los campos de tiempo (`TimecodeField`) guardan con Intro, al perder el foco y al cerrar el editor, pero solo si el texto ha cambiado (guardar lo mismo redondearía a segundos enteros); collage (encuadre por celda, cambio de plantilla, quitar).
- Barra inferior con destino del vídeo, duración total, Vista previa y Generar vídeo.
- Estado y lógica en `SlideshowDocument` (modelo `@Observable`); las vistas son `SlideshowView` (pestañas y barra de acción), `SlideshowTimelineView`, las pestañas de `SlideshowInspector.swift` (`SourceTab`, `VideoTab`, `ExtrasTab`, `MusicTab`) y `SelectionEditor` y `KenBurnsFramingView`.
- **Editar un elemento del timeline:** un clic en una foto, collage, texto, portada, créditos o pista lo selecciona y su editor (`SelectionEditor`) tapa la parte de arriba del módulo (título, pestañas y su contenido) dentro de un bloque con borde rojo; el timeline y las barras siguen visibles, y pulsar otro elemento cambia lo que se edita. Cada editor empieza con `EditorHeader(doc:kind:name:actions:)`: «Editando · tipo · nombre», sus acciones y «Cerrar» (también Esc), que deja `doc.selection = .none` y vuelve a enseñar la pestaña que estaba abierta (no se cambia de pestaña al seleccionar). Prueba: `--state slideshow.select=collage|photo|text|track`.
- Editores de Texto, Collage y Foto: cabecera con el nombre y las acciones y, debajo, `InspectorSplit(previewWidth:preview:settings:)`. La vista toma solo el ancho que necesita para llenar el alto disponible con su proporción (cada inspector pasa la cuenta alto → ancho) y los ajustes se quedan con el resto, sin bajar de `minSettingsWidth` (300 por defecto; si no cabe, encoge la vista). Los grupos de ajustes van en `BalancedColumns`, un `Layout` que los reparte en 1, 2 o 3 columnas de al menos 280 puntos, en orden y en tramos seguidos, con el corte que deja la columna más alta lo más baja posible; si no caben en alto, la zona se desplaza. Collage: Tiempo (Mantener), Transición y Pie; «Cambiar» abre las plantillas en un popover. Foto: primero los controles y a la derecha la previsualización animada (`InspectorSplit(previewOnTrailingSide: true, maxPreviewFraction: 1/3, …)`, como mucho un tercio del ancho). En columnas fijas (`balancesSettings: false`): a la izquierda Efecto, Tiempo, Transición y Pie; en el centro, solo con el efecto «Personalizado» (el único que usa Inicio y Fin), el grupo Encuadre con Inicio y Fin en pequeño, uno encima del otro (hasta 260 puntos), y Ajuste, caras, Inicio → Fin, Intercambiar, Restablecer y Retardo. La columna del Encuadre tiene ancho fijo, el justo para los paneles más el margen del bloque; la de la izquierda mide al menos 280 puntos y se lleva lo que sobre. Cada una se desplaza por su cuenta (`InspectorScroll`); si no hay sitio, encoge la previsualización. Para eso `KenBurnsFramingView(doc:url:leading:trailing:)` mete los grupos de quien llama (a la izquierda) y monta el Encuadre y la previsualización. Ya no hay hoja «Ampliar»: el encuadre se hace solo aquí. `TransitionOverrideRow` y `CaptionOverrideRow` tienen `stacked: true` para ir en columna. Prueba: `--state slideshow.select=collage|photo|text|track` selecciona el primer collage, foto, tarjeta de texto o pista.

**Etiquetas del vídeo.** Un detalle que conviene saber: en un `.mp4`, `AVAssetWriter` solo guarda las etiquetas 3GPP (`dscp` descripción, `auth` autor, `perf` intérprete, `date`) y descarta sin avisar las demás (el software `©swr`/`©too`, los comentarios de iTunes…). Por eso no hay campo «Software» y el nombre de CAOBA con la web va en la descripción. Para verlas: `exiftool -G1 -a video.mp4 | grep UserData`.

Detalles de la app:
- Los efectos y puntos Ken Burns se guardan **por nombre de fichero**, así excluir una foto no desalinea el resto (fallo conocido de la app antigua).
- "Asignar efectos → Automático / Caras" elige zoom o barrido según la proporción de cada foto frente al vídeo y pone el foco con Vision.
- Editar los puntos en el editor cambia el efecto a "Personalizado"; con los efectos automáticos el encuadre de Inicio marca el foco. El botón "Enfocar caras" del editor pone inicio y fin en las caras de esa foto.
- En el modo Collages del Slideshow se ofrecen también las plantillas superpuestas (marco blanco y sombra); en el Collage estático no, igual que en la app antigua.
- Al cargar un `.caoba` v1, los efectos por índice se traducen a nombres usando el `fileOrder` guardado, y el inicio de pista "en la foto N" se convierte a segundos del vídeo (`startTime`). Las duraciones propias se guardan en `durations` por nombre de fichero.
- La vista previa es **el vídeo entero** (todas las fotos o collages, portada, créditos, textos, marca de agua y música, con las duraciones y transiciones de verdad), pero pequeño: 640 px de lado mayor (640×360 en 16:9), a los mismos fps que el final y sin normalizar el audio. Sale rápido porque todo se carga ya reducido: las fotos, a lo que pide el lienzo (`PhotoLoader`), y los pasos de cada collage se dibujan a 640 px (`collageOptionsForPreview`, con `CollageOptions.scaled(toLongestSide:)`). La calidad usa la misma fórmula que el vídeo final (`VideoWriter.bitrate(for:)`, proporcional a los píxeles): antes iba a la cuarta parte y en un iMac Intel la app se cerraba al empezar la vista previa. Se reproduce en una ventana de la app. Como referencia, BOOK (24 fotos en collages, 50 s) sale en unos 9 s en un M2 Pro y en 15 s en Rosetta.

### Transiciones (`TransitionKind`, `Transitions`)

Cada foto entra con una transición: fundido cruzado, fundido a negro, corte, deslizar (izquierda, derecha, arriba, abajo), zoom cruzado o barrido (izquierda, derecha). `SlideshowPhoto.transition` / `transitionDuration` la fijan por foto; `SlideshowSpec.defaultTransition` / `defaultTransitionDuration` valen para las que no la traen (`transition: false` en el spec equivale a corte por defecto). `SlideshowTimeline(durations:transitions:)` lleva la duración de entrada de cada foto y `Transitions.compose(from:to:kind:progress:size:)` compone el fotograma. En los collages del vídeo, el primer paso entra con la transición del collage y la aparición de cada foto con un fundido suave. En la app: pestaña Vídeo (por defecto y duración 0,25–2 s, con «Aleatorio») e inspectores de foto, collage, portada y créditos (propias). Se guardan en el preset (`transitionKind`, `transitionDuration`, `transitionsByItem`, `transitionDurationsByItem`); los proyectos antiguos migran desde `useTransition`.

### Texto sobre el vídeo (`TextStyle`, `TextRenderer`, `TextOverlay`)

`TextStyle` define fuente (familia instalada o sistema), negrita, tamaño en % del alto, color, una de nueve posiciones (`TextAnchor`) y fondo (`TextBackdrop`: nada, sombra o banda). `TextRenderer.layer(lines:style:canvas:)` dibuja una capa transparente del tamaño del vídeo y `card(lines:style:background:canvas:)` una tarjeta de título. `SlideshowPhoto.caption` es un pie fijo (con `SlideshowSpec.captionStyle`) y `SlideshowPhoto.overlay` un `TextOverlay` que se ve unos segundos (con desfase y retardo opcionales); el escritor los compone dentro del fotograma de la foto. Cada estilo lleva la entrada (`animation`, `animationDuration`), la salida (`exitAnimation`: `mirror` = inversa de la entrada, `none` = se queda, o cualquier otra; `exitDuration`) y opcionalmente `holdSeconds` (tiempo mostrándose; `nil` = hasta el final). `TextPhase.at(_:total:style:)` da el punto de entrada o salida y `TextRenderer.animated` compone la capa en ese punto (la máquina de escribir vuelve a dibujar con `render(visibleCharacters:)`). El pie entra al empezar la foto y sale antes de la transición a la siguiente; en las tarjetas de título y cierre el texto entra tras la transición de la tarjeta. Con los empalmes (`titleCarryOver`, `closingCarryOver`) el mismo texto va también en la foto contigua sin animación en la unión, así se queda quieto mientras la tarjeta y la foto se funden. En la app, la pestaña «Portada y texto» tiene, por este orden, Portada y créditos, Marca de agua y Pies de foto (con la vista previa del pie). **Cada tarjeta de texto lleva su propio estilo** (`TextCard.style`): no hay estilo común. Al abrir un proyecto antiguo, las tarjetas sin estilo reciben una copia del `text.titleStyle` que tuviera guardado (que ya no se vuelve a escribir); una tarjeta nueva copia el estilo de la tarjeta de texto anterior en el timeline, o de la siguiente, o `TextStyle.title`; `SlideshowDocument.applyStyleToAllCards(from:)` copia el de una a todas («Aplicar estilo a todas», con confirmación). Inspector de la tarjeta: vista previa (`TextPreviewPanel(content: .card)`) y columna con Contenido, Pantalla y tiempo, Letra, Colocación, Animación y Empalmes (solo con pantalla propia); `TextStyleEditor(style:parts:stacked:)` enseña solo las partes pedidas (`.letter`, `.placement`, `.animation`) y en columna; el «fondo» del texto (nada, sombra o banda) se llama «Realce» para no confundirlo con el de la pantalla. Las **tarjetas de texto** (`TextCard`) se añaden con «Añadir texto» bajo el Timeline (tras el elemento seleccionado, o al final; queda seleccionada) o con el clic derecho de un elemento (antes o después), y se editan pulsándolas en el timeline. Son colocables en cualquier punto del timeline, con ancla `start`, `end` o el id del elemento ante el que van; cada una con texto y subtítulo, fondo negro, blanco o gris (o ninguno: entonces se superpone al elemento siguiente; el «Negro» es negro puro, 0,0,0, igual que en Collage y Contact Sheet), duración o segundos mostrándose, transición, empalmes con el siguiente o el anterior y estilo propio opcional (si no, el estilo de títulos). Patrón de pies con `{nombre} {n} {total} {fecha} {camara} {objetivo}` y pie propio o sin pie por elemento. Mientras se codifica, el progreso enseña cada tarjeta con fondo como «Texto · <primera línea>» (su fondo es una imagen temporal). Se guardan en `text.cards` del preset; los proyectos con título y cierre fijos migran a tarjetas al cargar. Pruebas: `--state text.demo=card|overlay` (las tarjetas de prueba llevan `TextStyle.title`) (con `text.carry=1`, `text.section=1`, `text.animation=<tipo>`) y `slideshow.generate=/ruta.mp4`.

### Ritmo de la música (`BeatDetector`, `RhythmPlanner`)

Opcional, bajo el botón «Ajustar al ritmo» de la pestaña Música del Slideshow: sin pulsarlo nada cambia.

- `AudioDecoder.read(url:block:)`: lectura PCM común (la usan el medidor de sonoridad y el detector).
- `BeatDetector.analyze(url:)` → `BeatTrack` (tempo, golpes en segundos del fichero, confianza; `isReliable` a partir de 0,12 y 8 golpes). Envolvente de ataques por energía con banda de graves, tempo por autocorrelación (60–200 ppm, preferencia por 120) y seguimiento de golpes. Unos 8 s por canción de 3 minutos.
- `RhythmPlanner.videoBeats(segments:tracks:)`: pasa los golpes de cada pista al tiempo del vídeo con los segmentos de `AudioPlan`; en el crossfade manda la pista que entra. `plan(beats:items:target:beatsPerCut:transition:)` da la duración de cada elemento para que el centro de cada transición caiga en un golpe, con densidad automática por tramo (`automaticDensity`) o fija (1, 2, 4, 8, 16), límites de 1–15 s y respeto de los fijos.
- En la app, `SlideshowDocument.adjustToRhythm()` analiza las pistas que falten, hace dos pasadas y escribe las duraciones en fotos y collages; `rhythmItems` recuerda cuáles puso el ritmo para respetar las que el usuario cambie a mano. `beatsPerCut` y `rhythmItems` se guardan en el preset. Para probar desde línea de comandos: `--state slideshow.rhythm=1`.

### Shutter Count (`ShutterCountReader`, `ShutterLife`)

- `read(url)` devuelve `ShutterCountResult` con la fuente usada, la cámara (marca, modelo, serie, firmware, objetivo), el obturador (disparos, mecánicos, vida útil estimada, porcentaje, si es estimación genérica) y datos de la foto.
- **Con exiftool** (empaquetado en la app o instalado con Homebrew): lee los MakerNotes de todas las marcas, JPG y RAW. `locateExifTool()` busca primero `Resources/exiftool` dentro de la app (se lanza con `/usr/bin/perl -I lib`), luego `/opt/homebrew/bin/exiftool` y `/usr/local/bin/exiftool`.
- **Sin exiftool**: ImageIO, que expone el contador solo para Nikon (`kCGImagePropertyMakerNikonShutterCount`); el resto de datos se leen igual y la vista avisa de la limitación.
- `ShutterLife.expectancy(make:model:)`: tabla de unos 130 modelos (Nikon, Canon, Sony, Pentax) con estimación genérica por marca si no hay coincidencia. Algunos Canon guardan el modelo con nombre corto («Canon EOS R6m2»); `expandCanonShortName` lo convierte en «canon eos r6 mark ii» antes de buscar en la tabla.
- **CR3 de Canon**: el contador no está en los MakerNotes, sino en la pista de metadatos temporizados (CTMD) del fichero. Por eso exiftool se lanza con `-fast` y no con `-fast2`, que se salta esas pistas (cuesta lo mismo, unos 0,12 s). El firmware viene en `CanonFirmwareVersion` como «Firmware Version 1.6.0» y se limpia a «1.6.0».
- **exiftool empaquetado**: `Tools/fetch-exiftool.sh` descarga la versión fijada (13.59) del espejo de SourceForge, comprueba la suma SHA-256 y la deja en `CaobaApp/Vendor/exiftool` (ignorado por git, unos 20 MB). El proyecto la copia como carpeta opcional a `Resources/exiftool`; si no está, la app se compila y funciona igual. La CI ejecuta el script antes de compilar. Requiere el Perl del sistema (`/usr/bin/perl`), presente en macOS.

### Configuración por carpeta (`CaobaConfig`)

Fichero `.caoba` en la carpeta de fotos, mismo formato que la app antigua: `{ "version": 1, "<seccion>": {...} }`. `readSection(_:as:from:)`, `writeSection(_:value:in:)` y `removeSection(_:in:)` con cualquier `Codable`; todas las escrituras pasan por un cerrojo para que dos módulos no se pisen. Hay **secciones protegidas** (`protectedSections`, hoy solo `renameHistory`): `hasSettings(in:)` no las cuenta como configuración y `resetSettings(in:)` (el botón Reiniciar) borra el resto y las conserva; si no queda nada, elimina el fichero. En la app, el botón «Reiniciar» de la barra de carpeta pide antes confirmación, con lo que se borra (montaje del Slideshow, ajustes de «Componer» del Collage, orden manual) y lo que no (fotos, presets, historial del Renombrador). Secciones hoy: `slideshow`, `collage`, `fileOrder` y `renameHistory`.

Ficheros de fuera de la carpeta que recuerda el Slideshow (pistas, portada, créditos, marca de agua): si al abrir el proyecto ya no están en su sitio, se cargan igual con todos sus ajustes y se marcan (`SlideshowDocument.missingFiles`, `isMissing`): rayados en rojo con ⚠︎ en el timeline (una pista que falta se dibuja hasta su Hasta o hasta el final del vídeo, `timelineDuration(of:)`) y «No se encuentra el fichero» con «Localizar…» en su editor y en el bloque de la marca de agua (`MissingFileNotice`). Localizar cambia solo la ruta y busca en esa carpeta los demás que falten con el mismo nombre (`relocate(_:to:)`, que devuelve cuántos más ha encontrado). Lo que falta no entra en el vídeo; Generar y Vista previa avisan antes («Faltan N ficheros: se generará sin ellos»).

Secciones que escribe la app: `fileOrder` (orden manual de las fotos, común a Slideshow, Collage y Contact Sheet), `slideshow` (todo el preset del Slideshow, incluida `collage.compose` con los ajustes de la hoja Componer), `collage` (`CollageFolderSettings`: `compose` con reparto, reordenar, filtros de fotos / proporción / tipo y plantillas marcadas) y `renameHistory` (protegida: sobrevive a «Reiniciar»). Los ajustes de Componer se restauran al abrir la carpeta y se guardan al cambiar cualquiera de ellos, así la hoja aparece como se dejó. Para abrir la hoja desde línea de comandos tal como esté guardada: `--state collage.compose=open` o `--state slideshow.compose=open` (con `capture.sheets=1` para capturarla).

### App: presets y última configuración

Procesador, Marca de agua y Collage llevan un menú «Preset» junto al título: lista los presets guardados (globales de la app), los aplica, y ofrece «Guardar como…», «Actualizar», «Eliminar» y «Valores por defecto». El menú muestra el nombre del preset cuyos ajustes coinciden con los actuales; en cuanto se toca algo, «Sin preset». Cada módulo además arranca con la última configuración usada. Las rutas del PNG de la marca y del logo van dentro del preset; si faltan al aplicarlo, se avisa. En Ajustes, «Exportar…» e «Importar…» mueven todos los presets en un JSON. Claves: `caoba.presets.<módulo>` y `caoba.lastSettings.<módulo>`. Para probar desde línea de comandos: `--state processor.demo=1`, `--state presets.export=/ruta.json`, `--state presets.import=/ruta.json`.

### App: preferencias

- Idioma (`caoba.language`): sistema / español / inglés. Se aplica al vuelo con `environment(\.locale)`; los textos fuera de vistas usan `L("…")`.
- Apariencia (`caoba.appearance`): sistema / claro / oscuro.
- Carpetas recientes (`caoba.recentFolders`): máximo 5.
- Último módulo (`caoba.lastModule`): la app arranca en el último módulo de la barra lateral que se usó (Procesador la primera vez). En modo captura (`--screenshot`) no se guarda.
- Pie de la barra lateral: «CAOBA · versión» y, debajo, en una fila, «caobafoto.com» a la izquierda y «Donación» a la derecha, los dos en el color de acento.
- Autor (`caoba.author`): nombre del fotógrafo o estudio. Se guarda como autor en los vídeos del Slideshow (vacío = el vídeo sale sin autor) y, en Metadatos, se propone en «Artista» cuando la foto no trae uno; el botón «Usar mi autor» lo pone aunque la foto tenga otro. Nada se escribe en las fotos hasta pulsar «Escribir metadatos».
- Aviso de versión: al arrancar consulta `releases/latest` de GitHub y compara como semver. Si hay una más nueva, enseña una banda roja (color de acento, texto blanco) sobre el contenido con «Actualizar ahora» o «Descargar» y cierre. La × solo la oculta hasta cerrar la app: en el siguiente arranque vuelve a salir mientras no se actualice. No hay enlace en la barra lateral.
- Donativo: botón «Hacer donación» en el pie de la barra lateral (abre Buy Me a Coffee) y una hoja al arrancar, un segundo después de abrir la app, en el primer arranque y luego como mucho cada 7 días (`caoba.donation.lastShown` guarda la última vez, en segundos desde 1970). Para verla sin esperar: borrar esa preferencia con `defaults delete com.marcosesperon.caoba caoba.donation.lastShown`.
- Ni la hoja ni la banda salen cuando la app arranca en modo captura (`--screenshot`). Para capturarlas a propósito: `--state demo.donation=1` y `--state demo.update=3.1.0`. Para capturar la ventana de Ajustes: `--state demo.settings=1` (la abre con el «Ajustes…» del menú, porque en macOS 14 SwiftUI no atiende `showSettingsWindow:`).

---

## 3. Ejemplos de uso del motor

```swift
import CaobaCore

// Escanear y procesar una carpeta
let folder = URL(fileURLWithPath: "/Users/yo/Fotos/Boda")
let files = try await FolderScanner().scan(folder: folder, sort: .date, orientation: .horizontal)
let ops = ProcessingOperations(crop: (.r3x2, .center), resizeMaxDimension: 2048, quality: 85, format: .jpeg)
let summary = try await ImageProcessor().process(
    files: files.map(\.url), ops: ops,
    saveMode: .newCopy(outputFolder: folder.appendingPathComponent("caoba")),
    progress: { print($0.phase, $0.fraction ?? 0, $0.currentFile ?? "") }
)
print("\(summary.processed) procesadas, \(summary.failures.count) errores")

// Marca de agua en mosaico
let opts = WatermarkOptions(mode: .tiled, sizePercent: 15, opacity: 35, spacing: 20, spacingUnit: .percent, rotation: -30)
_ = try await Watermarker().process(files: files.map(\.url), watermark: logoURL, options: opts, saveMode: .overwrite)

// Metadatos sin recomprimir
let edit = MetadataEdit(artist: "Marcos Esperón", copyright: "© CAOBA", gps: .some(GPSCoordinate(latitude: 42.88, longitude: -8.54)))
try MetadataService.write(edit, to: files[0].url)
print(MetadataService.read(files[0].url).artist ?? "-")

// Renombrar con patrón y vista previa
let plan = Renamer.patternPlan(files: files.map(\.url), options: PatternRenameOptions(pattern: "YYYY-MM-DD_boda_{n}", sortBy: .date))
plan.forEach { print($0.oldName, "→", $0.newName) }
_ = try await Renamer().execute(plan: plan, saveMode: .overwrite)

// QR de WiFi con logo
let qr = try QRGenerator.png(
    text: QRContent.wifi(ssid: "Estudio", password: "secreta", security: .wpa, hidden: false).payload,
    options: QROptions(size: 1024, foreground: RGBColor(hex: "#D71921")!, correction: .quartile),
    logo: try ImageIOHelpers.loadImage(from: logoURL)
)
try qr.write(to: URL(fileURLWithPath: "/tmp/wifi.png"))

// Collage: componer al azar con plantillas de 3 fotos en 3:2 y foco automático
let templates = CollageTemplates.filter(photos: 3, aspectLabel: "3:2")
var (rows, leftover) = CollageRenderer.group(files: files.map(\.url), templates: templates, mode: .random)
let detector = FocusDetector()
for i in rows.indices {
    for (cell, url) in rows[i].files.enumerated() {
        rows[i].focusPoints[cell] = await detector.focus(for: url, mode: .faces).point
    }
}
let (collageSummary, outputs) = try await CollageRenderer.generate(
    rows: rows, options: CollageOptions(longestSide: 3000, gap: 12, title: "Boda"),
    outputFolder: folder.appendingPathComponent("collages"))

// Contact sheet en masonry
let sheetOptions = ContactSheetOptions(columns: 4, thumbSize: 300, layout: .masonry, showNumbering: true, title: "Selección")
_ = try await ContactSheetRenderer.generate(files: files.map(\.url), options: sheetOptions, output: folder.appendingPathComponent("hoja.jpg"))

// Slideshow con dos pistas, marca de agua y Ken Burns automático
let detector = FocusDetector()
var photos: [SlideshowPhoto] = []
var rng = SystemRandomNumberGenerator()
for file in files {
    let aspect = file.size?.aspectRatio ?? 1
    let effect = KenBurns.suggestedEffect(imageAspect: aspect, videoAspect: VideoFormat.landscape16x9.aspectRatio, generator: &rng)
    let focus = await detector.focus(for: file.url, mode: .faces).point
    photos.append(SlideshowPhoto(url: file.url, duration: 4, kenBurns: effect, points: KenBurnsPoints(startFocus: focus, endFocus: focus)))
}
let spec = SlideshowSpec(
    photos: photos, format: .landscape16x9, transition: true,
    watermark: VideoWatermark(url: logoURL, position: .bottomRight, sizePercent: 25, opacity: 70),
    audio: AudioOptions(tracks: [AudioTrack(url: song1), AudioTrack(url: song2, startMode: .atPhoto(12))], fadeOut: true, normalize: true),
    kenBurns: KenBurnsSettings(intensity: .normal, easing: .easeInOut, durationPercent: 60),
    output: folder.appendingPathComponent("slideshow.mp4"))
try await SlideshowRenderer.generate(spec) { print($0.phase, $0.fraction ?? 0) }

// Shutter Count
let analysis = try await ShutterCountReader.read(URL(fileURLWithPath: "/Users/yo/Fotos/DSC_0001.NEF"))
print(analysis.camera.displayName ?? "-", analysis.shutter.count ?? 0, analysis.shutter.lifeExpectancy ?? 0, analysis.source)

// Cancelar un trabajo
let task = Task { try await ImageProcessor().process(files: urls, ops: ops, saveMode: .overwrite) }
task.cancel()   // el motor lanza CaobaError.cancelled en la siguiente iteración
```
