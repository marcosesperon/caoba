# Análisis: varias ventanas, cada una con su sesión

*20 de noviembre de 2026 · CAOBA 3.26.0 (commit `4a3ac49` + cambios sin subir del bloqueo de origen)*

**La pregunta:** ¿se puede trabajar con varias sesiones a la vez, cada una en su ventana, para lanzar trabajos largos en paralelo? Por ejemplo, generar el vídeo de una boda mientras se procesan las fotos de otra.

**Respuesta corta:** sí, es viable y encaja bien con macOS. Pero no es «abrir otra ventana» y ya: hoy toda la app comparte **un único estado**, así que dos ventanas serían dos vistas de lo mismo. Hay que separar lo que es de cada ventana de lo que es de toda la app. Calculo **entre 5 y 8 días de trabajo** en 4 fases. La fase 1 es la grande y no cambia nada visible.

---

## 1. Cómo está hoy

### Un solo estado para todo

`CaobaApp` crea **un** `AppState` y se lo da a la ventana (`WindowGroup` + `.environment(appState)`). Ahí dentro vive todo:

| Qué | Dónde | ¿De la ventana o de la app? |
|---|---|---|
| Módulo activo, carpeta de origen, lista de fotos, marcas, orden | `AppState` | De la ventana |
| Destino (carpeta o fichero) | `AppState` | De la ventana |
| Trabajo en curso (`JobRunner`) | `AppState.jobRunner` | De la ventana |
| Montaje del Slideshow (`SlideshowDocument`) | `@State` en `SlideshowView`, ligado a `AppState` | De la ventana |
| Sesión activa | `StudioSessions.active` y la preferencia `caoba.sessions.active` | De la ventana (hoy, una para toda la app) |
| Estructura de sesiones (Ajustes) y lista de sesiones | `StudioSessions` | De la app |
| Tarjetas y discos conectados | `ExternalDiskMonitor` | De la app |
| Descargar tarjeta, Recuperar fotos | `CardImportSession`, `RecoverySession` | De la app (la tarjeta es una sola) |
| Presets | `PresetStore.shared` | De la app (ya lo es) |
| Dónde se abren los diálogos | `DialogFolders` (estático) | De la ventana |
| Recientes | `AppState.recentFolders` y la preferencia | De la app |
| Aviso de versión, donativo, novedades, actualizar | `AppState`, `Updater.shared` | De la app, una sola vez |

El menú «Nueva ventana» está quitado a propósito (`CommandGroup(replacing: .newItem) {}`). Si se volviera a poner sin más, las dos ventanas enseñarían la misma carpeta y el mismo trabajo, y cambiar de sesión en una la cambiaría en las dos.

### Los trabajos largos bloquean la ventana

- **Slideshow, Collage, Contact Sheet, Procesador, Marca de agua, Metadatos, Renombrador y «Ordenar por fecha» de Recuperar fotos** van por `JobRunner`. Solo admite **un trabajo a la vez** (`guard !isRunning`) y lo enseña con una **hoja modal** (`jobPresentation` en `ContentView`): mientras se genera el vídeo, la ventana no se puede usar.
- **Descargar tarjeta** y **la búsqueda de Recuperar fotos** van por su cuenta y **no bloquean**. Ya hoy se puede descargar una tarjeta mientras se trabaja en otro módulo. Cambiar de sesión durante la descarga no la toca (`changeDestination` no hace nada con una descarga en marcha).

Por eso, lo que de verdad se pide es poder lanzar **un trabajo de `JobRunner` en una sesión y seguir trabajando en otra**.

### Lo bueno para el cambio

- Las 26 vistas que usan el estado lo reciben por `@Environment(AppState.self)`, no por un objeto global. Si cada ventana inyecta el suyo, las vistas apenas cambian.
- Los trabajos ya capturan sus datos al lanzarse: las rutas y los ajustes se copian antes de `jobRunner.run`. El motor (`CaobaCore`) no tiene estado global y puede ejecutar dos trabajos a la vez sin cambios.
- Lo que se guarda en cada carpeta (`.caoba` del Slideshow, orden manual, historial del Renombrador) es **por carpeta**, así que dos sesiones distintas no se pisan.

---

## 2. Qué habría que cambiar

1. **Partir `AppState` en dos.**
   - `AppModel`, uno para toda la app: estructura y lista de sesiones, discos, Descargar tarjeta, Recuperar fotos, recientes, versión, donativo y novedades.
   - `WindowState`, uno por ventana: módulo, sesión de la ventana, origen, fotos, destino, `JobRunner` y carpeta de los diálogos.
   - Es la pieza grande. Es mecánica, pero toca casi todas las vistas.
2. **Ventanas con su sesión**, usando `WindowGroup(for:)` con la ruta de la sesión como valor. A cambio, macOS da sin código extra:
   - ⌘N para una ventana nueva;
   - el menú Ventana;
   - las **pestañas** de macOS (Ventana › Combinar todas las ventanas), que para «varias sesiones» quizá sean más cómodas que ventanas sueltas;
   - que al volver a abrir CAOBA se recuperen las ventanas con sus sesiones.
3. **Una sesión, una ventana.** Si ya está abierta en otra ventana, se trae esa al frente en lugar de abrirla dos veces. Así no hay dos montajes del mismo Slideshow guardando a la vez el mismo `.caoba`. Lo mismo para «Sin sesión» con la misma carpeta.
4. **`DialogFolders` por ventana**, que hoy es estático.
5. **La sesión «recordada» al arrancar** ya no es una sola. La recuperan las ventanas restauradas, y la preferencia `caoba.sessions.active` queda para la primera ventana.
6. **Descargar tarjeta y Recuperar fotos siguen siendo de la app**, porque el lector es uno.
   - Si se abren en dos ventanas, las dos enseñan la misma descarga.
   - El destino por defecto es el `RAW` de la sesión de la ventana desde la que se lanza.
7. **Avisos al terminar.** Si un trabajo acaba en una ventana que no está delante:
   - sale una notificación del sistema (Descargar tarjeta ya usa `UserNotifications`);
   - y la hoja de resultado espera en esa ventana.
8. **Al salir con trabajos en marcha**, se pide confirmación diciendo cuáles se cortarían.

---

## 3. Riesgos

- **Misma sesión en dos ventanas.** Es el riesgo más serio: dos montajes del Slideshow se pisarían el `.caoba`. Se evita con la regla «una sesión, una ventana» del punto 3.
- **Dos trabajos pesados a la vez.**
  - Dos vídeos comparten el codificador por hardware, la GPU y la memoria. Funcionan, pero cada uno va más lento, y no ganas tiempo total respecto a hacerlos seguidos.
  - Dos Collages o Procesadores de muchas fotos grandes pueden subir mucho la memoria.
  - Lo útil de verdad es **no esperar**: lanzar el vídeo y mientras tanto procesar o renombrar.
  - Al principio no limitaría nada. Si se ve que va mal, se puede poner una cola de «uno pesado a la vez» que no bloquee.
- **Preferencias que se escriben desde varias ventanas** (último módulo, presets «últimos usados»): gana la última, que es lo esperable.
- **Alcance de la fase 1.** Al tocar casi todas las vistas, cualquier sitio que lea algo «de la app» desde el estado de ventana, o al revés, es un fallo posible. Hay que repasar módulo a módulo con las capturas de siempre.

---

## 4. Alternativas más baratas

| Alternativa | Qué da | Por qué no basta |
|---|---|---|
| **Abrir una segunda copia de la app** (`open -n -a CAOBA`) | Hoy mismo, sin código: dos procesos, cada uno con su sesión y su trabajo. | Comparten preferencias: la sesión activa, el último módulo y los presets los pisa la última copia que escribe, y se puede perder un preset guardado en las dos a la vez. Las dos vigilan la misma tarjeta. Vale para probar la idea, no para el día a día. |
| **Trabajo en segundo plano en la misma ventana**: barra de progreso pequeña en vez de hoja modal | Seguir trabajando mientras se genera el vídeo. Alrededor de 1–2 días. | El vídeo va ligado a la carpeta y al montaje abiertos: al terminar se refresca el Slideshow, se recarga la carpeta… Para cambiar de sesión con un trabajo en marcha hay que desligarlo de la ventana, que es casi lo mismo que la fase 1, pero con peor resultado: una sola sesión a la vista. |
| **Cola de trabajos** («generar después») | Encadenar trabajos de varias sesiones. | Mismo problema de desligar los trabajos, y sigues sin ver dos sesiones. Tiene sentido después, encima de las ventanas, no en su lugar. |

**Recomendación:** ir a ventanas por sesión. La alternativa de la segunda copia sirve para probar ya si te compensa trabajar así antes de invertir los días.

---

## 5. Plan por fases

| Fase | Qué | Esfuerzo | Se nota |
|---|---|---|---|
| **1. Separar el estado** | `AppModel` (app) y `WindowState` (ventana), vistas adaptadas, `DialogFolders` por ventana. Sigue habiendo una sola ventana. | 2–3 días | Nada: la app hace lo mismo. Se comprueba con la batería de capturas y los tests. |
| **2. Ventanas por sesión** | `WindowGroup(for:)`, ⌘N, «Abrir en ventana nueva» en la lista de sesiones, una sesión por ventana, restaurar ventanas al abrir, pestañas de macOS. | 1–2 días | Ya se trabaja con varias sesiones y se lanzan trabajos en paralelo. |
| **3. Herramientas de la app** | Descargar tarjeta y Recuperar fotos compartidas entre ventanas, destino según la ventana que lanza, avisos en la ventana correcta. | 1 día | Sin sorpresas con la tarjeta y varias ventanas. |
| **4. Pulido** | Notificación al terminar con la ventana detrás, confirmación al salir con trabajos en marcha y, si hace falta, límite de trabajos pesados a la vez. Documentación y capturas. | 1–2 días | Cómodo para el día a día. |

**Total: 5–8 días.** Cada fase se puede entregar por separado. Hasta la 2 no hay nada nuevo que enseñar.
