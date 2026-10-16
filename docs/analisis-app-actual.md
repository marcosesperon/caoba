# Análisis de la app actual: CAOBA Foto Utils v2.9.0 (Electron)

Fuente analizada: `/Users/marcosesperon/Documents/GITs/caoba-foto-utils`, commit `51fc210` (v2.9.0, 29-07-2026).
Objetivo del documento: tener una foto fiel de lo que hay hoy para decidir, funcionalidad a funcionalidad, qué se migra a Tauri + Rust ahora, qué se simplifica y qué se deja para más adelante.

---

## 1. Resumen ejecutivo

| Dato | Valor |
|---|---|
| Stack | Electron 39 + Node 22, UI HTML/JS vanilla, TailwindCSS 4 + daisyUI |
| Líneas de código propias | ~22.000 (de ellas ~3.500 son `meBlip.js` y ~1.800 son plantillas de collage) |
| Módulos visibles | 9: Slideshow, Collage, Contact Sheet, Procesador, Marca de agua, Metadatos, Renombrador, QR, Shutter Count |
| Módulo "fantasma" | Conversor (backend y JS de UI existen, pero la sección se retiró; ver §6) |
| Instaladores publicados | DMG arm64 301 MB, DMG x64 340 MB, EXE 275 MB |
| `node_modules` | 1,3 GB |
| Tests / lint | Ninguno |
| Idiomas | ES / EN (i18next en frontend, `t()` propio en backend) |

El peso de los instaladores viene casi en su totalidad de dependencias nativas: Electron (271 MB), TensorFlow.js (286 MB en `node_modules`), ffprobe-static (335 MB, todas las plataformas), ffmpeg-static (44 MB), face-api (23 MB), napi-canvas (25 MB), exiftool (21 MB), sharp/libvips (16 MB).

---

## 2. Arquitectura actual

### 2.1 Tres capas de Electron

- **`main.js`** (1.161 líneas): proceso principal. Registra ~50 handlers IPC, mantiene el estado global y orquesta los módulos de `src/`.
- **`preload.js`** (68 líneas): `contextBridge` que expone `window.api.*` (50 métodos). Es el contrato real entre UI y backend. Listado completo en §2.3.
- **Renderer** (`index.html` + `assets/js/*`): single-page con secciones por módulo. Cada módulo es un objeto `MODULO = { DOM, VARS, FN }`.

### 2.2 Estado global del proceso principal

```js
CAOBA = { mainWindow, isCancelled, currentFolderRoot, currentSortedFiles }
```

Punto clave para la migración: **el backend es stateful**. La UI llama a `scanAndSortFiles(folder, sortMode, orientation)` y el backend se guarda la carpeta y la lista ordenada. Después, los `*Generate` NO reciben la lista de archivos: la leen de `CAOBA.currentSortedFiles`. Con los checkboxes de inclusión/exclusión, la UI llama antes a `setSortedFiles(checkedFiles)` para sobrescribir esa lista. Excepción: el conversor sí recibe `files` explícitamente.

La cancelación es un flag global `isCancelled` que los bucles consultan vía `isCancelledFn()`, más `killCurrentProcess()` que mata el FFmpeg en curso (SIGKILL / taskkill).

El progreso viaja siempre por un único evento `conversion:progress` con `{ percent, file, phase }`. Fases usadas: `analyzing_audio`, `generating_kenburns`, `encoding_video`, `normalizing_audio`, `processing_images`, `watermarking`, `writing_metadata`, `batch_renaming`, `reading_metadata`, `generating_contactsheet`, `generating_collage`, `generating_collage_frames`, `converting`, `resizing`.

### 2.3 Contrato IPC completo (`window.api`)

| Grupo | Métodos |
|---|---|
| Diálogos | `selectFolder`, `selectFile` (mp3), `selectImage` (jpg/png), `slideshowSelectWatermark` (png), `saveFile` (mp4), `saveImage` (jpg), `selectPhotoForAnalysis` (jpg+RAW) |
| Utilidades | `scanAndSortFiles`, `setSortedFiles`, `getThumbnail`, `getPhotoAspects`, `getAudioDuration`, `computeFocusPoints`, `isDirectory`, `getVersion`, `getLanguage`, `setLanguage`, `toggleDevTools` |
| Config por carpeta | `readCaobaConfig`, `writeCaobaConfig(folder, section, data)`, `deleteCaobaConfig` |
| Shell | `shellOpenPath`, `shellOpenURL` |
| Slideshow | `slideshowGenerate`, `slideshowPreview`, `collageSlideshowGenerate`, `cancelGeneration` |
| Collage | `collageGetTemplates`, `collageGenerate` |
| Contact sheet | `contactsheetGenerate` |
| Procesador | `imageprocessorGenerate`, `imageprocessorPreview` |
| Marca de agua | `watermarkPreview`, `watermarkGenerate` |
| Metadatos | `metadataRead`, `metadataWrite`, `metadataWritePerFile` |
| Renombrador | `renamerPreview/Generate`, `autofixPreview/Generate`, `searchReplacePreview/Generate`, `prefixSuffixPreview/Generate` |
| QR | `qrPreview`, `qrGenerate` |
| Conversor | `converterGenerate` |
| Shutter count | `shutterCountRead` |
| Eventos | `onProgress(cb)` → `conversion:progress` |

### 2.4 Dependencias nativas y para qué se usan

| Dependencia | Uso real | Peso aprox. |
|---|---|---|
| `sharp` (libvips) | Todo el procesado de imagen: resize Lanczos3, extract, composite, rotate EXIF, SVG a raster (textos, bordes, máscaras redondeadas), blur (sombras), `withMetadata`, `strategy.attention` (smart crop), encode JPEG/PNG/WebP/AVIF/TIFF | 16 MB |
| `ffmpeg-static` + `ffprobe-static` | Slideshow (filtergraph complejo) y duración de MP3 | 44 + 335 MB |
| `exiftool-vendored` (Perl) | Lectura de EXIF/MakerNotes: fechas, cámara, objetivo, GPS, shutter count | 21 MB |
| `exif-parser` | Solo extraer el thumbnail embebido del JPEG (128 KB de cabecera) | pequeño |
| `heic-convert` (libheif WASM) | Decodificar HEIC/HEIF para thumbnails y conversor | 0,7 MB |
| `qrcode` | Generar QR a PNG | pequeño |
| `@tensorflow/tfjs` + `tfjs-backend-wasm` + `@vladmandic/face-api` + `@napi-rs/canvas` | Detección de caras (modelo SSD MobileNet v1, 5,6 MB en `assets/models`) | ~335 MB |
| `i18next` | i18n en frontend | pequeño |

---

## 3. Transversales (afectan a todos los módulos)

### 3.1 Escaneo y orden de carpeta (`src/exif.js`)
- Extensiones aceptadas: jpg, jpeg, png, webp, tiff, tif, avif, heic, heif. Ignora ocultos (`.`) y temporales (`_caoba_`).
- Orden por nombre (`localeCompare` insensible a mayúsculas) o por fecha (EXIF `DateTimeOriginal`/`CreateDate` vía exiftool, fallback a `birthtime`/`mtime`).
- Filtro de orientación (horizontal / vertical / todas) leyendo dimensiones con sharp y corrigiendo por orientación EXIF 5-8.
- No es recursivo.

### 3.2 Thumbnails (`main.js`)
- Devuelve **data URL base64 JPEG** por IPC. Caché en memoria `Map` clave `ruta:tamaño`.
- JPG: lee solo 128 KB de cabecera y saca el thumbnail EXIF (160x120) con `exif-parser`; si no hay, decodifica entero con `sequentialRead`.
- Limitador de concurrencia = nº de CPUs. HEIC en cola secuencial aparte.
- Rendimiento medido en CHANGELOG: 484 fotos en 2,7 s.

### 3.3 Configuración por carpeta `.caoba`
JSON `{ version: 1, <seccion>: {...} }` en la propia carpeta de fotos. Lectura/escritura/borrado por sección. Lo usan Slideshow, Collage y Contact Sheet (campos exactos en la sección frontend).

### 3.4 Ficheros temporales **dentro de la carpeta de origen**
FFmpeg se ejecuta con `cwd = carpeta de fotos` y se escriben ahí: `temp_filter_script.txt`, `_caoba_chunk_filter_N.txt`, `_caoba_segment_N.mp4`, `_caoba_concat_list.txt`, `_caoba_kb_<ts>/photo_N/frame_00000.jpg` (frames Ken Burns), `_caoba_cover_*`, `_caoba_credits_*`. Para sobrescritura: `temp_*`, `temp_wm_*`, `temp_meta_*`, `temp_imgproc_*`, `_caoba_rename_temp_*`, etc.
Consecuencia: falla en carpetas de solo lectura (tarjetas SD, discos de red sin permiso) y deja basura si se mata el proceso. Smart crop de slideshow y collage slideshow sí usan `os.tmpdir()`.

### 3.5 i18n
- Backend: `src/i18n.js` propio, detecta idioma del sistema, `t('backend.xxx')` para mensajes de error y títulos de diálogos.
- Frontend: i18next con `locales/{es,en}/translation.json` (417 líneas cada uno).
- Los mensajes de éxito de los backends están en español hardcodeado (`"Se han procesado N imagenes"`).

### 3.6 Diálogos nativos
Filtros fijos por tipo: carpeta; MP3; imagen jpg/png; logo PNG; guardar MP4 con nombre `caoba_slideshow_<timestamp>.mp4`; guardar JPG `contact_sheet_<timestamp>.jpg`; guardar QR PNG; foto para análisis (jpg, png, tiff, webp, heic + RAW nef, cr2, cr3, arw, orf, rw2, raf, dng, pef).

### 3.7 Otros
- Versión desde `package.json`; comprobación de nueva versión contra GitHub al arrancar (frontend).
- DevTools ocultos (5 clics en la versión).
- Instancia única de ExifTool (proceso Perl persistente) cerrada en `will-quit`.
- Logging `[Modulo] ... (Nms)` por consola en todo el backend.

---

## 4. Análisis por módulo

Para cada módulo: qué hace, cómo lo hace, dependencias, complejidad de portar a Rust y observaciones. La "dificultad" es una primera estimación para la conversación posterior, no una decisión.

### 4.1 Slideshow (`src/ffmpeg.js` 843 líneas + `src/kenburns.js` 255 + handlers en `main.js`)

**Qué hace**
- Fotos → MP4 H.264 (yuv420p, BT.709, 25 fps) con 6 formatos: 16:9 (1920x1080), 9:16 (1080x1920), 4:5 (1080x1350), 5:4 (1350x1080), 2:3 (1280x1920), 3:2 (1920x1280).
- Duración por foto, portada y créditos con duración propia (se copian a la carpeta como `_caoba_cover_*`).
- Transición fade 1 s (`xfade`) opcional; sin transición usa `concat`.
- Marca de agua PNG: tamaño % del lado corto, 5 posiciones, opacidad vía `colorchannelmixer`.
- Audio: N pistas MP3, inicio automático (encadenado con crossfade 3 s) o manual (desde foto X), `acrossfade`, normalización EBU R128 en 2 pasadas (`loudnorm`, solo si hay >1 pista), fade-out 3 s. Pistas con `-stream_loop -1`.
- Smart crop previo (attention o caras) al aspect del vídeo, en carpeta temporal.
- **Ken Burns**: 10 efectos (zoom in/out, pan 4 direcciones + 4 diagonales), intensidad (4/7/12 % de margen), easing (linear, in, out, in-out), % de duración del efecto (20-100), delay inicial, puntos inicio/fin personalizados con zoom 1-2x y modo `contain`. Se implementa **pre-generando cada frame como JPEG con sharp** (extract + resize Lanczos3) y metiéndolos a FFmpeg con `-framerate 25 -i frame_%05d.jpg`. Para 4 s por foto son 125 JPEG por foto.
- **Chunked**: >100 fotos se procesa en bloques de 100 → segmentos MP4 → concat final con `xfade` entre segmentos (re-encode) o concat demuxer con `-c:v copy`.
- Vista previa: primeras 10 fotos a media resolución, `ultrafast`, se abre con el visor del sistema.
- Progreso parseando `time=HH:MM:SS.ss` del stderr de FFmpeg.

**Dependencias**: ffmpeg, ffprobe (duración MP3), sharp (frames KB, metadatos watermark), face-api opcional.

**Dificultad de migración**: ALTA. El generador del filtergraph es portable casi línea a línea a Rust (es construcción de strings), pero hay mucha superficie: 3 ramas (single-pass, chunked con xfade, chunked con copy) con lógica de audio duplicada en cada una. FFmpeg tendría que ir como *sidecar* de Tauri.

**Observaciones**
- `action:slide-preview` referencia `kenBurnsEffect` y `kenBurnsPerPhoto` sin haberlas desestructurado (lanzaría `ReferenceError`), pero la UI ya no invoca `slideshowPreview`: la vista previa de vídeo está muerta.
- `_unused_buildKenBurnsFilter` (100 líneas) es código muerto: el `zoompan` de FFmpeg se descartó por jitter.
- La lógica de audio (crossfade, loudnorm, fadeout) está copiada 3 veces.
- `ffprobe` solo se usa para la duración de MP3: en Rust se puede resolver con un crate de audio y eliminar 335 MB de dependencia.
- Ken Burns por frames es lento (sharp decodifica el buffer una vez, pero extract+resize+encode JPEG 125 veces por foto) y genera muchísimos ficheros en la carpeta de origen.

### 4.2 Collage (`src/collage.js` 1.819 líneas)

**Qué hace**
- ~570 plantillas (`TEMPLATES`): celdas normalizadas `{x,y,w,h}` en 0-1, `photos`, `aspect`, flag `overlap`. Generadas por `addVariants(id, nombre, nFotos, celdasH, celdasV, aspects)` para 6 aspectos + base 1:1. `getTemplates()` deduplica por aspecto+nFotos+celdas y devuelve también `cellAspects`.
- Agrupa la lista de fotos consumiéndolas secuencialmente; plantilla por grupo en modo `sequential` (cíclico) o `random`. Fotos sobrantes se descartan con aviso.
- `smartAssign`: asigna fotos a celdas por cercanía de aspect ratio (greedy, celdas más "extremas" primero).
- Por celda: recorte `cover` centrado, `attention` (libvips), `faceapi`, o por punto de foco `{fx, fy}` definido en el editor. Esquinas redondeadas vía máscara SVG `dest-in`. Plantillas overlap: marco blanco (2 % del lado menor, mínimo 3 px) + sombra (SVG negro con blur gaussiano, opacidad máx. 0,3 escalada por `shadowIntensity`).
- Fondo blanco/negro/gris, gap, título (SVG text sans-serif 24 px bold, altura 50 px), logo con posición/tamaño/opacidad, calidad JPEG.
- `outputSize` es el lado mayor. Límite 15.000 px.
- Salida: fichero o carpeta (`collage.jpg`, `collage_01.jpg`...).
- `generateCollageBuildupFrames`: para el slideshow de collage genera frame 0 (vacío) + un frame por foto añadida (acumulativo) como PNG en temp.

**Dependencias**: sharp (resize, extract, composite, SVG raster, blur, attention), face-api opcional.

**Dificultad**: MEDIA. Las plantillas son datos puros (portables 1:1, incluso a JSON compartido con el frontend). La composición es geometría sencilla. Lo que cuesta en Rust: rasterizar texto (sharp lo hace vía SVG/librsvg), blur rápido para sombras, y sobre todo el **smart crop `attention`** que es un algoritmo interno de libvips sin equivalente directo.

### 4.3 Contact Sheet (`src/contactsheet.js` 239 líneas)

- Layout `grid` (celdas = thumb + padding 10 px, etiqueta 20 px) o `masonry` (ancho fijo, altura proporcional, columna más corta). Límite 30.000 px.
- Título (40 px), numeración y/o nombre (truncados a 20-25 chars), borde (SVG rect), colores fondo blanco/negro/gris, modo recorte `contain`/`cover`, logo con posición/opacidad/tamaño. Salida JPEG q90.

**Dificultad**: BAJA-MEDIA. Mismo tipo de composición que collage; comparte `calculatePosition` con watermark.

### 4.4 Procesador de imágenes (`src/imageprocessor.js` 207 líneas)

- Pipeline por archivo: auto-rotate EXIF → recorte a ratio (ratio `[w,h]` + anclaje top/bottom/left/right/center) → resize lado máximo sin ampliar → `withMetadata()` → formato (jpeg/png/webp/avif/tiff) + calidad.
- Modo `new` (sufijo `_processed` si misma carpeta, nombre limpio si otra) u `overwrite` (temp + unlink + rename).
- Preview: antes/después a 800 px en base64 de la **primera** foto de la lista.

**Dificultad**: BAJA. Todo son operaciones básicas. El matiz es **preservar metadatos (EXIF, ICC, DPI)** al reescribir: el crate `image` los descarta y hay que reinyectarlos.

**Observación**: `src/resizer.js` es el antecesor y ya no se usa desde `main.js` (código muerto).

### 4.5 Marca de agua (`src/watermark.js` 295 líneas)

- Modo `single`: posición (5), tamaño % del **lado corto**, opacidad aplicada tocando el canal alfa en raw.
- Modo `tiled`: rejilla centrada con spacing en px o % del lado corto, rotación del tile, recorte de tiles en bordes, todo compuesto en un overlay PNG del tamaño de la imagen.
- Preview sobre una foto elegible (`fileIndex`) a 1.200 px.
- Salida **siempre JPEG q100 4:4:4** aunque el original sea PNG/WebP (mantiene la extensión original → fichero `.png` con contenido JPEG).

**Dificultad**: BAJA. Composición alfa + rotación de un PNG.

### 4.6 Metadatos (`src/metadata.js` 185 líneas)

- Lectura con exiftool: artista, copyright, descripción, `DateTimeOriginal` (raw string), make/model, dimensiones, ISO, exposición, f, focal, flash, software, objetivo, GPS lat/lon.
- Escritura **con sharp** (`withMetadata({ exif: { IFD0: {Artist, Copyright, ImageDescription}, IFD2: {DateTimeOriginal} } })`), por lote (mismos valores a todos) o por archivo (`metadataMap`). Opción `stripMetadata`: pasa por PNG intermedio para borrar todo y luego reescribe solo lo del usuario.
- **Re-encoda el JPEG** (calidad configurable, por defecto 95) en cada escritura: pérdida generacional. Solo escribe 4 campos. GPS no se escribe.

**Dificultad**: MEDIA. Leer es fácil; escribir EXIF sin recomprimir requiere manipular segmentos APP1 (en Rust hay crates puros para ello, y sería una mejora sobre lo actual).

### 4.7 Renombrador (`src/renamer.js` 518 líneas)

- 4 modos: patrón, auto-fix de numeración, buscar/reemplazar, prefijo/sufijo. Cada uno con preview + ejecución.
- Patrón: `{nombre}`, `{n}` (dígitos auto o fijos, inicio configurable), `{camara}`, `{objetivo}`, `{ancho}`, `{alto}`, `{orientacion}` (H/V/C), fecha `YYYY MM DD hh mm ss` (EXIF o mtime). Transformación de caso (lower/upper/capitalize) y saneado (acentos NFD, espacios → `_`, caracteres especiales).
- Auto-fix: detecta `prefijo + número + sufijo` común y rellena con ceros.
- Colisiones: sufijo `_2`, `_3`... Renombrado en dos pasadas (temp → final). Modo copia a otra carpeta.
- Solo lee EXIF/dimensiones si el patrón lo necesita.

**Dificultad**: BAJA. Lógica pura de strings + lectura de fecha/cámara EXIF.

**Observación**: `replace` de JS solo sustituye la primera ocurrencia de cada placeholder (`{n}` dos veces en un patrón no funciona). `MM` y `mm` se procesan en orden y pueden pisarse en patrones raros.

### 4.8 QR (`src/qr.js` 57 líneas)

- Texto → PNG con `qrcode` (tamaño, colores, nivel L/M/Q/H, margen) + logo centrado (`fit: contain`, % del tamaño) con sharp. Los 9 tipos de contenido (WiFi, vCard, etc.) se construyen en el **frontend**.

**Dificultad**: MUY BAJA.

### 4.9 Shutter Count (`src/shuttercount.js` 162 líneas)

- Con exiftool lee `ShutterCount`, `ImageCount`, `ShutterCount2/3`, `MechanicalShutterCount`, serie, firmware, objetivo, fecha y datos de la foto. Tabla de vida útil por modelo (~130 modelos Nikon/Canon/Sony/Pentax) con estimación genérica por marca. Acepta RAW.

**Dificultad**: ALTA si se quiere sin exiftool. El shutter count vive en los MakerNotes propietarios (Nikon en claro, Sony y Pentax **cifrados**, Canon no lo guarda en la mayoría de modelos). Reimplementar eso en Rust es un proyecto en sí; la alternativa es llevar exiftool como sidecar (en Windows va el `.exe` autocontenido; en macOS requiere Perl del sistema, que hoy sigue viniendo en `/usr/bin/perl`).

### 4.10 Conversor (`src/converter.js` 122 líneas + `caoba.converter.js` 202)

- JPG/PNG/WebP/HEIC → JPEG/PNG/WebP con calidad, auto-rotate, modo copia/sobrescribir (borra el original si cambia la extensión). HEIC decodificado con `heic-convert`.
- **Sigue activo**: botón "Conversor" en la barra lateral (texto fijo, sin i18n), sección y JS cargados. Lo que se eliminó en `d646014` fue la opción de formato dentro del Procesador. El CLAUDE.md del repo está desactualizado en este punto.
- Usa la lista compartida pero ignora sus checkboxes, y lee modo/carpeta de destino de una barra que está oculta para esta sección (hereda lo que dejó la sección anterior).

### 4.11 Detección de caras y smart crop (`src/facedetector.js` 130 líneas)

- Carga TF.js backend WASM + face-api SSD MobileNet v1 desde `assets/models`. Convierte la imagen a tensor RGB raw con sharp. Devuelve cajas; el punto de foco es el centro del bounding box que engloba todas las caras. Caché por ruta.
- `attention`: delega en `sharp.strategy.attention` (libvips: busca regiones con alta diferencia de luminancia/saturación/tono de piel).
- Se usa en: Collage (`smartCrop`), Collage slideshow, Slideshow (smart crop previo y foco Ken Burns), `computeFocusPoints` para el editor de enfoque.

**Dificultad**: ALTA. Es la dependencia más pesada (~335 MB en `node_modules`) y la que más complica un build Rust. Alternativas existen (detectores en Rust puro o vía ONNX Runtime) pero cambian el modelo y los resultados.

---

## 5. Mapa de dependencias por funcionalidad

| Funcionalidad | sharp | ffmpeg | ffprobe | exiftool | heic | face-api | qrcode |
|---|:-:|:-:|:-:|:-:|:-:|:-:|:-:|
| Escaneo + orden por fecha | ● | | | ● | | | |
| Thumbnails | ● | | | (exif-parser) | ● | | |
| Slideshow básico | ● | ● | ● (mp3) | | | | |
| Slideshow Ken Burns | ● | ● | | | | opc. | |
| Slideshow smart crop | ● | | | | | opc. | |
| Collage | ● | | | | | opc. | |
| Collage slideshow | ● | ● | ● | | | opc. | |
| Contact sheet | ● | | | | | | |
| Procesador | ● | | | | | | |
| Marca de agua | ● | | | | | | |
| Metadatos leer | | | | ● | | | |
| Metadatos escribir | ● | | | | | | |
| Renombrador | ● (dims) | | | ● (fecha/cámara) | | | |
| QR | ● (logo) | | | | | | ● |
| Shutter count | | | | ● | | | |
| Conversor | ● | | | | ● | | |

---

## 6. Deuda técnica y rarezas detectadas

1. **Preview de slideshow muerta y además rota**: `action:slide-preview` usa variables no definidas (`kenBurnsEffect`, `kenBurnsPerPhoto`), pero el frontend ya no llama a `slideshowPreview`. Es funcionalidad perdida por el camino.
2. **Código muerto**: `src/resizer.js`, `_unused_buildKenBurnsFilter` en `ffmpeg.js`, `assets/js/caoba.resizer.js` (no se carga y llama a un `resizerGenerate` que no existe), `_previewSequenceTemplate` en slideshow y collage, pools de plantillas ocultos.
3. **Temporales en la carpeta de origen** (§3.4): frames Ken Burns, segmentos MP4, scripts de filtro, copias de portada.
4. **Marca de agua y resizer fuerzan JPEG** aunque la extensión sea PNG/WebP.
5. **Escritura de metadatos recomprime** el JPEG y solo cubre 4 campos; el strip pasa por PNG en memoria (imágenes grandes = mucha RAM).
6. **Lógica de audio FFmpeg triplicada** en `generateSlideshow`.
7. **Backend stateful** (`currentSortedFiles`): los handlers de generación dependen de que la UI haya llamado antes a `scanAndSortFiles`/`setSortedFiles`. Con varias secciones abiertas es fácil que una pise a otra.
8. **Thumbnails como base64 por IPC**: funciona pero duplica memoria (buffer → string base64 → DOM). En Tauri hay vías más eficientes (protocolo `asset` o caché en disco).
9. **Mensajes al usuario mezclados**: los errores pasan por `t()`, los éxitos están en español fijo en el backend.
10. **Sin tests**: cualquier refactor o migración depende de pruebas manuales. Las partes puramente lógicas (plantillas, renombrador, cálculo de crops Ken Burns, filtergraph) serían fáciles de testear en Rust.
11. **Detección de caras**: `computeFocusPoints` en modo `attention` devuelve siempre el centro (0.5, 0.5); el attention real solo se aplica en generación. El editor de enfoque no muestra lo que luego se recorta.
12. Plantillas de collage: `getTemplates()` deduplica en cada llamada (barato, pero la lista final real no son "570+", son las únicas tras dedupe; el frontend filtra además las overlap para collage estático).

---

## 7. Inventario del frontend

### 7.1 Base técnica
- **Sin CDNs**: todo local. `style.css` es Tailwind 4.1.14 + daisyUI 5 ya compilado y minificado (456 KB), **congelado desde el primer commit** y sin build en `package.json`; hay clases usadas en el HTML que no existen en él. `liquid-glass.css` (1.318 líneas) es el tema Nothing con `data-glass="dark|light"`.
- **Accesos a internet en ejecución**: fuentes Google (Doto, Space Grotesk, Space Mono) en cada arranque; `api.github.com/.../releases/latest` para avisar de versión nueva (solo aviso + botón descargar); iframe de OpenStreetMap en Metadatos; enlaces a caobafoto.com, Google Maps y Buy Me a Coffee vía `shellOpenURL`.
- **`meBlip.js`** (3.560 líneas, 141 KB) es una librería propia del autor (v2.0.1, MIT) de notificaciones tipo Dynamic Island. CAOBA usa una fracción: `add`, `update`, `has`, `remove`, `setTheme`, con tipos loading/success/error/info, progreso, overlay bloqueante y botones de acción (Cancelar, Abrir, Descargar). El resto (undo, forms, scanner, mapa, confetti...) no se usa.
- **No hay `<canvas>`** en ningún sitio. Todo lo visual son SVG (`createElementNS`), `<img>` posicionados y CSS. Las animaciones (preview Ken Burns) van con `requestAnimationFrame` sobre estilos.
- **Imágenes**: todas las miniaturas llegan como data URL base64 desde `getThumbnail` (tamaños 64, 80, 120, 200, 400, 600, 800 según sitio; sin caché en frontend). La única carga por `file://` es el modal de previsualización de foto a tamaño completo.
- **Sin CSP** declarada y con `onclick`/`onchange` en línea en `index.html` y en HTML generado (pistas de audio).
- i18n: i18next con `data-i18n*` en atributos; `fetch('locales/..')` relativo. Sin traducir: QR, Conversor, Shutter Count, editor Ken Burns, "Todas/Ninguna", "Abrir"...

### 7.2 `caoba.js`: estado global y piezas compartidas
- `CAOBA.VARS`: `sourcePath`, `fileList`, `currentSection`, callbacks de cambio de carpeta (inmediatos y diferidos por sección), `sectionDirty`, y `dest` por sección: modo fichero (slideshow, contactsheet, collage) o carpeta con `new|overwrite` (imageprocessor, watermark, renamer). Metadatos, QR, conversor y shutter count no tienen barra de destino.
- **Selector de carpeta compartido** con historial de 5 recientes en `localStorage`, arrastrar y soltar, contador de fotos, destino por defecto `<origen>/caoba`, carga de `.caoba` con indicador "Configuración restaurada" y botón "Reiniciar".
- **Barra de destino compartida** en el footer; `data-dest-dialog` decide `saveFile` o `saveImage`.
- **`renderFileList`**: barra "Todas/Ninguna" + contador, filas con checkbox (desmarcada = opacidad 0,35), asa de arrastre en modo manual (llama a `setSortedFiles`), número, miniatura 40 px (clic abre preview) y nombre. HEIC muestra overlay de carga.
- Helpers de progreso: `showLoading/updateLoading/hideLoading`, `setProgressBar`, `setProgressPhase` (traduce `phase.*`), `setStatus` (mapea `alert-*` a tipos meBlip y detecta "cancelado").
- `renderTemplateSVG` y `renderTemplateSVGWithPhotos` (miniaturas de plantilla con fotos recortadas por `clipPath` y punto de foco).
- Tema (`caoba_theme`), idioma (`caoba-language`), modal de donación cada 7 días, DevTools con 5 clics.
- **Persistencia `.caoba`**: `saveCaobaConfig` con debounce de 2 s; **solo Slideshow se registra**. Collage y Contact Sheet no guardan nada (el CHANGELOG dice lo contrario).

### 7.3 Módulos de UI (resumen de lo que ve el usuario)

| Módulo | Líneas | Controles y editores | `window.api` que usa |
|---|---|---|---|
| **Slideshow** | 3.092 | Orden name/date/manual, filtro orientación, 6 formatos, modo photos/collage, duración, transición, portada/créditos con duración, marca de agua (posición/tamaño/opacidad), N pistas MP3 con inicio auto/manual, fade-out, normalizar. **Ken Burns**: timeline con tarjeta por foto (select de efecto, barra de duración, marcas de tiempo, carriles de audio), intensidad/easing/% duración, menú "Asignar" (random/attention/faceapi), **editor modal** con vistas Inicio/Fin arrastrables, zoom 100-200 %, fit cover/contain, copiar/intercambiar, delay 0-80 %, preview animada. **Collage slideshow**: modo random (checkboxes de plantillas con filtros) o sequential (secuencia horizontal drag&drop, "+N fotos", Componer con picker modal, Ajustar foco, timeline de segmentos, **editor de enfoque** modal con sidebar de plantillas), parámetros reveal/hold/bg/gap/radio/sombra | collageGetTemplates, scanAndSortFiles, setSortedFiles, getThumbnail, getPhotoAspects, computeFocusPoints, getAudioDuration, selectImage, selectFile, slideshowSelectWatermark, slideshowGenerate, collageSlideshowGenerate, shellOpenPath |
| **Collage** | 1.093 | Igual que collage slideshow (sequential/random, Componer, Ajustar foco, editor de enfoque, timeline) **excluyendo plantillas overlap**; lado mayor (3000), gap, fondo, radio, sombra, título, calidad, logo; estimación de dimensiones | collageGetTemplates, scanAndSortFiles, setSortedFiles, getThumbnail, computeFocusPoints, slideshowSelectWatermark, collageGenerate |
| **Contact Sheet** | 305 | Columnas, tamaño thumb, nombres, numeración, título, layout grid/masonry, fondo, recorte, borde (color/grosor), logo; estimación | scanAndSortFiles, setSortedFiles, slideshowSelectWatermark, contactsheetGenerate |
| **Procesador** | 293 | Tarjetas: autorrotar, recortar (7 ratios + custom, 5 anclas), redimensionar, calidad. Comparador antes/después con divisor arrastrable (`clip-path`). Sin lista de ficheros: procesa toda la carpeta | imageprocessorPreview, imageprocessorGenerate |
| **Marca de agua** | 223 | Imagen, modo single/tiled (spacing px/%, rotación 0/±30/±45), posición, tamaño, opacidad; preview inline con debounce y navegación por foto | slideshowSelectWatermark, watermarkPreview, watermarkGenerate |
| **Metadatos** | 317 | Lista propia con indicador de editado; ficha EXIF completa + mapa OSM iframe + enlace Google Maps; formulario artista/copyright/descripción/fecha, strip, calidad; aplicar a uno o a todos | getThumbnail, metadataRead, metadataWrite, metadataWritePerFile, shellOpenURL |
| **Renombrador** | 294 | 4 modos deducidos de qué campos tienen contenido; preview en vivo (máx. 30 filas); recarga carpeta al acabar | renamerPreview/Generate, autofixPreview/Generate, searchReplacePreview/Generate, prefixSuffixPreview/Generate |
| **QR** | 309 | 9 tipos con formulario propio; la cadena (WIFI:, vCard 3.0, mailto:, tel:, sms:, geo:, VEVENT) **se construye en el frontend**; tamaño, colores, corrección (auto Q con logo), margen, logo; preview con debounce; guardar abre diálogo desde backend | selectImage, qrPreview, qrGenerate |
| **Conversor** | 202 | Filtros por extensión de origen con contador; formato jpeg/png/webp; calidad | converterGenerate |
| **Shutter Count** | 153 | Selector de foto; cámara, disparos, barra de vida útil, datos de foto. Todo en español fijo | selectPhotoForAnalysis, shutterCountRead |

Reacción al cambio de carpeta: diferida (solo si la sección está activa) en slideshow, collage, contactsheet, metadata y converter; inmediata en imageprocessor, watermark y renamer.

### 7.4 Qué guarda Slideshow en `.caoba`
`mode`, `sortMode`, `orientationFilter`, `fileOrder`, `excludedFiles`, `videoFormat`, `durationPerPhoto`, `useTransition`, `cover{path,duration}`, `credits{path,duration}`, `watermark{path,position,size,opacity}`, `audio{fadeout,normalize}`, `musicTracks[{path,mode,startPhoto}]`, `kenBurns{intensity,easing,durationPct,perPhoto{idx:efecto},points{idx:{startFx,startFy,startZoom,endFx,endFy,endZoom,fit,delayPct}}}`, `collage{templateMode,revealDuration,holdDuration,bgColor,gap,borderRadius,shadowIntensity,focusPoints{fila:[{file,fx,fy,imgAspect}]}}`.
**No guarda la secuencia de plantillas** (cuáles y en qué orden), aunque sí sus puntos de foco por número de fila.

### 7.5 Fallos y deuda detectados en el frontend
- **Arrastrar una carpeta al selector no funciona**: usa `e.dataTransfer.files[0].path`, eliminado en Electron 32 (el proyecto usa Electron 39) y el preload no expone `webUtils.getPathForFile`.
- **`updateUIState()` no existe** en Contact Sheet ni Collage, pero se llama al marcar/desmarcar checkboxes: TypeError.
- **Destino de Collage incoherente**: declarado en modo fichero (diálogo `saveFile` de MP4), pero al generar usa la carpeta de salida oculta o la de origen.
- **Ken Burns indexado por posición**: timeline indexa sobre fotos marcadas, editor y "Asignar" sobre la lista completa; se desalinean con fotos excluidas. Reordenar por arrastre no actualiza `currentFileList`, y el orden manual restaurado se pisa al reescanear por nombre.
- **Opacidad de marca de agua** mezcla fracción (0,8) y porcentaje (80) entre estado, slider, restore y reset.
- **Comparación de versión** `latest > version` es de strings: "2.10.0" no avisaría.
- **Procesador**: el checkbox de autorrotar no tiene listener; marcar solo autorrotar no habilita el botón.
- **Renombrador**: nombres de fichero sin escapar en `innerHTML`.
- Tema de meBlip no cambia al pulsar el toggle (usa una constante del arranque).
- **Duplicación masiva Slideshow/Collage** (~800 líneas casi idénticas: fila de plantilla, picker de composición, autoCompose, ajustar foco, secuencia, previews, timeline, editor de enfoque). `scanPhotosInFolder`/`renderFilePreview` triplicados. Tabla de aspectos de vídeo repetida 3 veces. Lógica cover/contain + foco repetida en 4 sitios.

### 7.6 Mapa de eventos y cancelación
- Un único evento `conversion:progress` con `{percent, phase?, file?}`; fases traducidas con `phase.<clave>` o `PHASE_LABELS`.
- La cancelación es un `invoke` (`cancelGeneration`) desde el botón de meBlip; el frontend detecta el resultado por `result.cancelado`, por el texto de `backend.cancelledByUser` o por `error === 'Cancelado'` (QR). Tres convenciones distintas.

---

## 8. Consideraciones para Tauri + Rust (previas a decidir)

Esto NO son decisiones, son hechos del entorno que condicionan la conversación posterior.

- **Toolchain local**: cargo/rustc 1.94 instalados, Node 26. No hay Tauri CLI, ni ffmpeg ni libvips en el sistema; sí `exiftool` de Homebrew.
- **WebView**: Tauri usa WKWebView (macOS) y WebView2 (Windows), no Chromium. El HTML/JS/CSS actual es vanilla y en principio reutilizable, pero habrá que revisar CSS y APIs que Safari trate distinto.
- **Binarios externos**: Tauri permite *sidecars* (ffmpeg, exiftool). Lo que no se pueda hacer en Rust puro se puede seguir delegando.
- **Procesado de imagen en Rust**: el ecosistema (`image`, `fast_image_resize`, `imageproc`, codificadores JPEG/WebP/AVIF) cubre resize, crop, composite y codificación. Lo que no viene "gratis" respecto a sharp: rasterizar texto, SVG, blur rápido, smart crop por atención, HEIC (requiere libheif nativo), preservar EXIF/ICC al reescribir.
- **EXIF en Rust**: hay lectura madura y escritura pura sin recomprimir; no hay decodificación de MakerNotes propietarios (shutter count).
- **Tamaño esperado**: una app Tauri con sidecar ffmpeg estaría en el orden de 80-120 MB frente a los 275-340 MB actuales; sin ffmpeg, por debajo de 30 MB.
