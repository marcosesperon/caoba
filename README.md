# CAOBA

**CAOBA** es una aplicación nativa para macOS con utilidades rápidas para fotógrafos, organizadas por **sesiones**: descarga de tarjetas, slideshows en vídeo, collages, hojas de contacto, procesado por lotes, marca de agua, metadatos, renombrado, códigos QR, lectura del contador de disparos y recuperación de fotos borradas de tarjetas. Pensada para trabajar por sesiones (o por carpetas sueltas) y por lotes, sin complicaciones. Disponible en **español** e **inglés**.

[![Buy Me A Coffee](https://img.shields.io/badge/Buy%20Me%20A%20Coffee-ffdd00?style=for-the-badge&logo=buy-me-a-coffee&logoColor=black)](https://buymeacoffee.com/marcosesperon)
[![Descargar](https://img.shields.io/badge/Descargar-macOS%2014%2B-D71921?style=for-the-badge&logo=apple&logoColor=white)](https://github.com/marcosesperon/caoba/releases/latest)

## 👥 Acerca de

CAOBA es un proyecto del estudio de fotografía **[CAOBA](https://caobafoto.com/)**, especializado en fotografía profesional y herramientas para fotógrafos. Visita [caobafoto.com](https://caobafoto.com/) para conocer más sobre nuestro trabajo.

---

## ✨ Funcionalidades

La aplicación se organiza en **11 módulos** agrupados en tres secciones, como en su barra lateral. Casi todos trabajan sobre la **sesión activa** (o una carpeta de fotos cualquiera): la eliges una vez, marcas qué fotos entran y cambias de módulo sin volver a empezar.

### Creadores

1. **Slideshow** — Vídeos MP4 a partir de fotos o collages, con música, fundidos y efectos Ken Burns
2. **Collage** — Collages fotográficos con 1049 plantillas y editor de encuadre, y carruseles de Instagram
3. **Contact Sheet** — Hojas de contacto con las miniaturas de tus fotos

### Utilidades

4. **Descargar tarjeta** — De la tarjeta al RAW de la sesión, por sesiones, sin repetir nada y con cada copia comprobada
5. **Procesador** — Procesado por lotes: rotar, recortar, redimensionar, calidad y formato
6. **Marca de agua** — Tu logo sobre todas las fotos de una carpeta
7. **Metadatos** — Lee y escribe EXIF, incluido GPS, sin recomprimir la imagen
8. **Renombrador** — Renombrado masivo con patrones (también con el nombre y la fecha de la sesión), y con deshacer

### Otras herramientas

9. **Código QR** — QR a partir de texto, URL, WiFi, contacto, email, teléfono, SMS, ubicación o evento
10. **Shutter Count** — Disparos del obturador y vida útil estimada de la cámara
11. **Recuperar fotos** — Recupera fotos y vídeos borrados de tarjetas de memoria

---

### 🗂️ Sesiones

Todo gira alrededor de la **sesión** con la que trabajas, que se elige en el sitio del título de la ventana (nombre y fecha; «CAOBA» si no hay ninguna):

- **Lista de sesiones** de la carpeta raíz, con buscador, **Nueva sesión…** (crea la carpeta con su fecha y sus subcarpetas) y **Sin sesión** (vuelve a carpetas sueltas y vacía los módulos).
- Al elegirla, cada módulo sabe de dónde salen las fotos (su `JPG`) y dónde deja lo que hace: las descargas en su `RAW`, y el vídeo, los collages, la hoja de contacto o las copias dentro de la misma sesión, con su nombre. Los diálogos de abrir y guardar empiezan en ella.
- **Ajustes › Sesiones**: carpeta raíz, una carpeta por año, 16 formatos de fecha delante o detrás del nombre, subcarpetas (`RAW`, `JPG`, `Lightroom`… las que quieras), dónde van las descargas y las fotos finales, y el nombre de la salida de cada módulo con `{sesion}` y `{fecha_sesion}`.
- Por defecto para cada sesión: una **plantilla del Slideshow** (se aplica sola si aún no hay montaje), un **preset del Contact Sheet** y uno del **Renombrador** (si no, `{fecha_sesion} {sesion} {n}`).
- Las herramientas que no van con una sesión (Código QR, Shutter Count, Recuperar fotos) no la tocan: allí el título dice solo «CAOBA».
- **Varias ventanas, cada una con su sesión**: con ⌘N (Archivo › Nueva ventana) o «Abrir en ventana nueva» en la lista abres otra ventana y cada una va a lo suyo, por ejemplo generando el vídeo de una boda mientras haces los collages de otra. Una sesión (o una carpeta suelta) no se abre en dos ventanas: en la lista sale en gris. Al volver a abrir CAOBA vuelven todas, cada una con su sesión y su módulo.
- **Trabajos en paralelo**: los vídeos se generan de uno en uno (el siguiente espera «En cola» y empieza solo); al terminar un trabajo que no estás viendo (CAOBA detrás u otra ventana delante) sale una **notificación** que, al pulsarla, trae su ventana. Cerrar una ventana o salir de CAOBA con trabajos en marcha pide confirmación, con la lista de lo que se cancelaría.

---

### 🎬 Slideshow

Convierte una colección de fotos en un vídeo con música, montado en un **timeline** como el de un editor de vídeo:

- **Seis formatos**: 16:9 (TV, YouTube), 9:16 (Historias, Reels, TikTok), 4:5 (feed de Instagram), 5:4, 2:3 y 3:2.
- **Timeline a toda la anchura**: cada foto es una tarjeta con la anchura de su duración. Se reordena arrastrando, se estira para darle más tiempo y se excluye con una casilla.
- **Efectos Ken Burns**: zoom y barridos en diez direcciones, con velocidad, curva y porcentaje de duración. Un editor de encuadre con puntos de inicio y fin, zoom hasta 2x, retardo, modo entera o rellenar y previsualización animada. Asignación automática por saliencia o por **detección de caras** (Vision de Apple, sin descargar modelos).
- **Portada y créditos** con duración propia.
- **Marca de agua** PNG con posición, tamaño y opacidad.
- **Música**: varias pistas con crossfade de 3 s, arrastrables sobre el timeline y con recorte Desde/Hasta estirando los bordes; repetición de la lista si el vídeo es más largo; fundido de salida; **normalización EBU R128** a -16 LUFS.
- **Modo Collages**: cada collage aparece foto a foto, con tiempos de aparición y mantenimiento, y las 84 plantillas superpuestas (marco y sombra) además de las normales.
- **Vista previa** en una ventana de la app con las primeras fotos a media resolución.
- Codificación H.264 por **hardware** (VideoToolbox), sin fotogramas temporales en disco. La configuración se guarda en la carpeta (`.caoba`) y se restaura al volver.
- **Plantillas**: guardan todo menos las fotos (formato, transiciones, música, portada, créditos y los textos del principio y del final) para usarlo en otra sesión. Los textos con `{sesion}` y `{fecha_sesion}` se rellenan solos al aplicarla.

### 🧩 Collage

- **1049 plantillas** para 1 a 9 fotos en seis proporciones (16:9, 5:4, 3:2, 9:16, 4:5, 2:3) y 1:1, con filtros por número de fotos y proporción.
- **Secuencia** de collages: Componer al azar entre las plantillas elegidas, Añadir uno a uno, reordenar arrastrando.
- **Editor de encuadre**: arrastra cada foto dentro de su celda; cambia la plantilla sin perder las fotos.
- **Ajustar foco** automático por saliencia o por caras.
- Lado mayor configurable, separación, esquinas redondeadas, fondo, título, calidad y logo con posición y opacidad.
- Salida a carpeta con nombres automáticos (`collage_01.jpg`, `collage_02.jpg`…).

### 📇 Contact Sheet

- Rejilla o **masonry**, columnas y tamaño de miniatura configurables, con estimación del tamaño final.
- Título, nombres de archivo, numeración, borde con grosor, fondo blanco, negro o gris, recorte entero o rellenar.
- Logo con posición, tamaño y opacidad.
- Título con `{sesion}` y `{fecha_sesion}`, y **presets** con nombre (uno puede ser el de las sesiones).

### 📥 Descargar tarjeta

- Reconoce la tarjeta al meterla (lector SD o cámara) y enseña sus **sesiones**: las fotos agrupadas por hora (huecos de 15 min a 8 h, o por día), con miniaturas, para marcar solo las que quieres.
- **JPG, RAW, HEIC o vídeo**, cada uno con sus acompañantes (`.XMP`, `.WAV`, `.THM`, `.LRF`); todo junto o por fecha (`AAAA/MM-DD`).
- Cada copia se **relee y se compara** (SHA-256) con la de la tarjeta antes de darla por buena. Lo ya descargado se salta, nada se sobrescribe (los nombres repetidos de otra cámara van con `_2`) y la tarjeta solo se lee.
- Destino en el `RAW` de la sesión de la ventana de delante (sin sesión, la carpeta elegida en esa ventana), o **Crear sesión…** en el momento; avisa si las fotos no son del día de la sesión. Durante una descarga el destino no cambia.
- Pausa, vigilancia del espacio libre, expulsar al terminar y **siguiente tarjeta** con los mismos ajustes.

### 🖼️ Procesador

- **Autorrotar** según EXIF, **recortar** a 1:1, 4:5, 5:4, 3:2, 2:3, 16:9, 9:16 o proporción personalizada con anclaje, **redimensionar** por lado mayor sin ampliar, **calidad** y **formato** de salida (JPEG, PNG, HEIC, TIFF).
- Entrada: JPG, PNG, TIFF, HEIC, WebP, AVIF y RAW.
- **Comparador antes/después** con divisor arrastrable.
- Conserva EXIF, GPS y perfil de color. Copias nuevas o sobrescribir.

### 💧 Marca de agua

- PNG propio, modo **suelto** (cinco posiciones, tamaño como porcentaje del lado corto) o **mosaico** (separación en px o %, giro).
- Opacidad ajustable y **vista previa** sobre cualquier foto de la carpeta.
- Respeta el formato original de cada foto.

### 📋 Metadatos

- Ficha por foto: artista, copyright, descripción, fecha, cámara, objetivo, ISO, apertura, exposición, focal, software y **mapa** si hay GPS.
- Edita por foto o aplica a todas las marcadas. Puede escribir y borrar **coordenadas GPS**.
- La imagen **no se recomprime**: solo cambian los metadatos.

### ✏️ Renombrador

- **Patrón** con `{nombre}`, `{n}`, `{camara}`, `{objetivo}`, `{ancho}`, `{alto}`, `{orientacion}` y fecha de captura `{YYYY} {MM} {DD} {hh} {mm} {ss}` (entre llaves, para que un texto fijo como «EMMA» no se confunda con el mes); dígitos e inicio del contador, mayúsculas, acentos, espacios y caracteres especiales.
- Variables de la sesión `{sesion}` y `{fecha_sesion}` (con el formato de fecha de Ajustes); con fotos de una sesión empieza con `{fecha_sesion} {sesion} {n}` o el preset elegido en Ajustes. Presets con nombre.
- **Corregir numeración** (`Foto-1` → `Foto-001`), **buscar y reemplazar**, **prefijo y sufijo**.
- Vista previa en vivo y **deshacer**: cada renombrado en sitio queda registrado en la carpeta y se puede revertir, incluso varias operaciones hacia atrás.

### 📱 Código QR

- Nueve tipos: texto, URL, WiFi, contacto (vCard), email, teléfono, SMS, ubicación y evento.
- Tamaño de 256 a 2048 px, colores, nivel de corrección L/M/Q/H, margen y logo central (sube la corrección automáticamente).
- Vista previa en tiempo real y exportación a PNG.

### 📷 Shutter Count

- Lee el **contador de disparos** y muestra la vida útil estimada por modelo (Nikon, Canon, Sony, Pentax), número de serie, firmware, objetivo y datos de la foto. Acepta JPG y RAW.
- Usa **exiftool** empaquetado para leer todas las marcas; sin él, el contador de Nikon se lee de forma nativa.

### 💾 Recuperar fotos

- Recupera **fotos y vídeos borrados** de tarjetas SD y discos externos: JPG, RAW de todas las marcas (CR2, CR3, NEF, ARW, DNG, RAF, ORF, RW2…), HEIC y vídeo (MOV, MP4, MTS…), y opcionalmente cualquier otro tipo de fichero.
- Solo **lee** la tarjeta: nunca escribe en ella. Busca en el espacio libre (lo normal tras borrar) o en toda la tarjeta (formateadas o dañadas).
- Lo encontrado va saliendo mientras busca, en **bloques** (carpetas de hasta 500 ficheros de PhotoRec): se puede ir eliminando lo que no interesa, suelto o por bloques, para no llenar el disco.
- Cuadrícula con miniaturas y vista previa de lo recuperado, filtros por tipo y **ordenar por fecha** de captura en `AAAA/MM-DD/AAAA-MM-DD_HHMMSS`, copiando sin tocar los originales.
- Pide la contraseña de administrador al empezar: leer la tarjeta en bruto lo exige. Solo se usa para abrirla; la búsqueda corre con tu usuario.
- Usa **[PhotoRec](https://www.cgsecurity.org/wiki/PhotoRec)** de TestDisk (GPL), empaquetado dentro de la app.

---

## 🎨 Interfaz

- **Nativa de macOS** con los controles del sistema, modo claro y oscuro, tipografía Doto en los títulos y el acento rojo de CAOBA.
- **Origen compartido**: la sesión activa (con sesión, el origen es siempre su `JPG`; si aún no existe, «Crear carpeta JPG» la crea), o «Elegir sesión…» / «Elegir carpeta…»; sin sesión, historial de recientes con la sesión o la carpeta de encima delante del nombre. Arrastrar y soltar, y la lista de fotos con casillas, orden por nombre o fecha y filtro de orientación. Botón «Recargar», y aviso antes de lanzar un proceso si alguien ha borrado, renombrado o añadido fotos en la carpeta desde que se leyó.
- **Barra de destino compartida**: copias nuevas o sobrescribir y carpeta de salida. Las copias necesitan una carpeta de destino, que nunca puede ser la de las fotos (una subcarpeta sí). Con una sesión, cada módulo rellena el destino dentro de ella; sin sesión, el destino se vacía al cambiar de carpeta de origen y al cambiar de sección, que además vuelve a «Copias nuevas».
- Lo que no se puede usar todavía porque depende de otra cosa (sin tarjeta, sin PNG, sin música…) sale **atenuado**.
- **Progreso** con fase y fichero actual, cancelable, y aviso de macOS al terminar si no lo estás viendo.
- **Español e inglés**, con selector en Preferencias.
- **Aviso de nueva versión** comprobando las releases de GitHub. Sin cuentas, sin telemetría: la app no envía nada; solo consulta esa página y, en Metadatos, el mapa.

---

## ⬇️ Instalación

1. Descarga el DMG de la [última release](https://github.com/marcosesperon/caoba/releases/latest).
2. Arrastra **CAOBA** a Aplicaciones.
3. Requiere **macOS 14 Sonoma** o posterior.

Si macOS avisa de que no puede comprobar el desarrollador, abre la app con clic derecho → **Abrir** la primera vez.

---

## 🛠️ Tecnologías

- **Swift 6 y SwiftUI**: app nativa de macOS.
- **ImageIO y Core Image**: decodificación (JPG, PNG, TIFF, HEIC, WebP, AVIF, RAW), escalado, composición y escritura con metadatos.
- **AVFoundation y VideoToolbox**: codificación de vídeo por hardware, composición de audio y mezcla.
- **Vision**: detección de caras y saliencia para encuadres automáticos.
- **Core Text y MapKit**: textos en collages y mapa de metadatos.
- **exiftool** (Perl, distribución oficial) empaquetado solo para Shutter Count.
- **PhotoRec 7.2** (TestDisk, GPL v2+) compilado desde el código fuente como programa aparte para Recuperar fotos, con **DiskArbitration** para las tarjetas y **QuickLook** para las miniaturas.
- **XcodeGen** para el proyecto y **GitHub Actions** para la integración continua.

El motor (`CaobaCore`) es un paquete Swift sin interfaz, con más de 180 tests, independiente de la app.

---

## 🚀 Desarrollo

```bash
brew install xcodegen
Tools/fetch-exiftool.sh      # descarga exiftool para Shutter Count (opcional)
Tools/build-photorec.sh      # compila PhotoRec para Recuperar fotos (obligatorio para publicar)
xcodegen generate            # crea CAOBA.xcodeproj (no se versiona)
open CAOBA.xcodeproj         # ⌘R para ejecutar
cd CaobaCore && swift test   # tests del motor sin abrir Xcode
Tools/make-release.sh        # binario universal (Silicon + Intel) y DMG en dist/
Tools/make-release.sh --publish   # además etiqueta la versión y crea la release en GitHub
```

Requiere Xcode 16 o superior. En `docs/` están la bitácora de decisiones y la documentación del motor.

## 📄 Licencias de terceros

- **PhotoRec** (TestDisk), © Christophe Grenier, con licencia [GNU GPL v2 o posterior](https://www.gnu.org/licenses/old-licenses/gpl-2.0.html). Va dentro de la app como programa aparte (`CAOBA.app/Contents/Resources/photorec`, con su licencia y versión). El código fuente exacto que se usó, con el script de compilación, está adjunto a cada [release](https://github.com/marcosesperon/caoba/releases).
- **libjpeg** del Independent JPEG Group, enlazada dentro de PhotoRec: «This software is based in part on the work of the Independent JPEG Group».
- **ExifTool**, © Phil Harvey, con la licencia de Perl.
