# CAOBA

**CAOBA** es una aplicación nativa para macOS con utilidades rápidas para fotógrafos: slideshows en vídeo, collages, hojas de contacto, procesado por lotes, marca de agua, metadatos, renombrado, códigos QR y lectura del contador de disparos. Pensada para trabajar por carpetas y por lotes, sin complicaciones. Disponible en **español** e **inglés**.

[![Buy Me A Coffee](https://img.shields.io/badge/Buy%20Me%20A%20Coffee-ffdd00?style=for-the-badge&logo=buy-me-a-coffee&logoColor=black)](https://buymeacoffee.com/marcosesperon)
[![Descargar](https://img.shields.io/badge/Descargar-macOS%2014%2B-D71921?style=for-the-badge&logo=apple&logoColor=white)](https://github.com/marcosesperon/caoba/releases/latest)

## 👥 Acerca de

CAOBA es un proyecto del estudio de fotografía **[CAOBA](https://caobafoto.com/)**, especializado en fotografía profesional y herramientas para fotógrafos. Visita [caobafoto.com](https://caobafoto.com/) para conocer más sobre nuestro trabajo.

---

## ✨ Funcionalidades

La aplicación se organiza en **9 módulos** agrupados en dos categorías. Todos trabajan sobre una **carpeta de fotos compartida**: la eliges una vez, marcas qué fotos entran y cambias de módulo sin volver a empezar.

### Creadores

1. **Slideshow** — Vídeos MP4 a partir de fotos o collages, con música, fundidos y efectos Ken Burns
2. **Collage** — Collages fotográficos con 937 plantillas y editor de encuadre, y carruseles de Instagram
3. **Contact Sheet** — Hojas de contacto con las miniaturas de tus fotos

### Utilidades

4. **Procesador** — Procesado por lotes: rotar, recortar, redimensionar, calidad y formato
5. **Marca de agua** — Tu logo sobre todas las fotos de una carpeta
6. **Metadatos** — Lee y escribe EXIF, incluido GPS, sin recomprimir la imagen
7. **Renombrador** — Renombrado masivo con patrones, y con deshacer
8. **Código QR** — QR a partir de texto, URL, WiFi, contacto, email, teléfono, SMS, ubicación o evento
9. **Shutter Count** — Disparos del obturador y vida útil estimada de la cámara

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

### 🧩 Collage

- **937 plantillas** para 1 a 9 fotos en seis proporciones (16:9, 5:4, 3:2, 9:16, 4:5, 2:3) y 1:1, con filtros por número de fotos y proporción.
- **Secuencia** de collages: Componer al azar entre las plantillas elegidas, Añadir uno a uno, reordenar arrastrando.
- **Editor de encuadre**: arrastra cada foto dentro de su celda; cambia la plantilla sin perder las fotos.
- **Ajustar foco** automático por saliencia o por caras.
- Lado mayor configurable, separación, esquinas redondeadas, fondo, título, calidad y logo con posición y opacidad.
- Salida a carpeta con nombres automáticos (`collage_01.jpg`, `collage_02.jpg`…).

### 📇 Contact Sheet

- Rejilla o **masonry**, columnas y tamaño de miniatura configurables, con estimación del tamaño final.
- Título, nombres de archivo, numeración, borde con grosor, fondo blanco, negro o gris, recorte entero o rellenar.
- Logo con posición, tamaño y opacidad.

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

- **Patrón** con `{nombre}`, `{n}`, `{camara}`, `{objetivo}`, `{ancho}`, `{alto}`, `{orientacion}` y fecha de captura `YYYY MM DD hh mm ss`; dígitos e inicio del contador, mayúsculas, acentos, espacios y caracteres especiales.
- **Corregir numeración** (`Foto-1` → `Foto-001`), **buscar y reemplazar**, **prefijo y sufijo**.
- Vista previa en vivo y **deshacer**: cada renombrado en sitio queda registrado en la carpeta y se puede revertir, incluso varias operaciones hacia atrás.

### 📱 Código QR

- Nueve tipos: texto, URL, WiFi, contacto (vCard), email, teléfono, SMS, ubicación y evento.
- Tamaño de 256 a 2048 px, colores, nivel de corrección L/M/Q/H, margen y logo central (sube la corrección automáticamente).
- Vista previa en tiempo real y exportación a PNG.

### 📷 Shutter Count

- Lee el **contador de disparos** y muestra la vida útil estimada por modelo (Nikon, Canon, Sony, Pentax), número de serie, firmware, objetivo y datos de la foto. Acepta JPG y RAW.
- Usa **exiftool** empaquetado para leer todas las marcas; sin él, el contador de Nikon se lee de forma nativa.

---

## 🎨 Interfaz

- **Nativa de macOS** con los controles del sistema, modo claro y oscuro, tipografía Doto en los títulos y el acento rojo de CAOBA.
- **Carpeta de origen compartida** con historial de recientes, arrastrar y soltar, y la lista de fotos con casillas, orden por nombre o fecha y filtro de orientación.
- **Barra de destino compartida**: copias nuevas o sobrescribir, carpeta de salida por defecto `caoba` dentro de la de origen.
- **Progreso** con fase y fichero actual, cancelable.
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
- **XcodeGen** para el proyecto y **GitHub Actions** para la integración continua.

El motor (`CaobaCore`) es un paquete Swift sin interfaz, con más de 90 tests, independiente de la app.

---

## 🚀 Desarrollo

```bash
brew install xcodegen
Tools/fetch-exiftool.sh      # descarga exiftool para Shutter Count (opcional)
xcodegen generate            # crea CAOBA.xcodeproj (no se versiona)
open CAOBA.xcodeproj         # ⌘R para ejecutar
cd CaobaCore && swift test   # tests del motor sin abrir Xcode
Tools/make-release.sh        # binario universal (Silicon + Intel) y DMG en dist/
Tools/make-release.sh --publish   # además etiqueta la versión y crea la release en GitHub
```

Requiere Xcode 16 o superior. En `docs/` están la bitácora de decisiones y la documentación del motor.
