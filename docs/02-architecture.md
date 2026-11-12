# Clipboard Manager — Diseño de Arquitectura (ADD)

## Justificación de tecnologías

| Decisión | Opción | Motivo |
|---|---|---|
| Icono de barra de menús | AppKit `NSStatusItem` | Única forma de tener un icono persistente en la barra de menús de macOS |
| Contenedor de la UI | `NSPopover` + `NSHostingController` (SwiftUI) | Un `NSMenu` con vistas personalizadas no recibe de forma fiable clics, botones, clic derecho ni menús anidados. En un popover, SwiftUI gestiona todo eso |
| Comportamiento del popover | `.applicationDefined` + monitor global de clic-fuera | Un popover `.transient` no puede volverse *key* en una app `LSUIElement` inactiva y se cierra al instante; por eso se cierra manualmente al detectar un clic fuera |
| Menú de escape (clic derecho) | `NSMenu` mínimo (Abrir / About / Quit) | Único `NSMenu` que queda en la app; da acceso a acciones globales sin ocupar espacio en el popover |
| Selector de vista | `Picker` segmentado SwiftUI | Cambia entre Texto / Imágenes / Grupos sin reconstruir la UI a mano |
| Persistencia de datos | JSON con Codable (`store.json` + `groups.json`) | Simple, sin dependencias, escritura atómica |
| Persistencia de imágenes | PNG individual en disco | El modelo solo guarda el nombre del fichero; evita inflar el JSON con base64 |
| Monitorización | Polling de `NSPasteboard.changeCount` | Única forma fiable en macOS; comparar un entero cada 1s tiene coste despreciable |
| Pegar en la app activa | Copiar + reactivar target + `Cmd+V` sintético | Al mostrar el popover se activa la app, por eso el target se captura *antes* de mostrarlo |
| Quick Look | `qlmanage -p` vía `Process` | Lanzador externo que no bloquea el popover |
| Editor del item | Ventana propia y redimensionable (`DetailEditorWindowController`) | Un editor dentro del popover se lo cargaría al tomar el foco; y el texto capturado puede ser largo, así que necesita áreas multilínea que crezcan con la ventana |
| Clic derecho en las filas | `RightClickCatcher` (`NSViewRepresentable`) superpuesto | Su `hitTest` solo reclama `.rightMouseDown`, de modo que clics izquierdos, botones y hover siguen llegando a la fila SwiftUI |
| Tira de chips de filtro | Desplazamiento propio por flechas, no `ScrollView` | Con pocos chips no se ve ningún control; el paginado por `‹`/`›` es más legible en 30pt de alto que una barra de scroll horizontal |

## Patrones de diseño

- **MVVM**: `ClipboardStore` como `ObservableObject` (única fuente de verdad); las vistas SwiftUI lo observan y se repintan solas
- **Strategy**: `ClipboardMonitor` con implementación por polling
- **Repository**: `JSONPersistenceService` para la persistencia (items + grupos)

## Decisiones técnicas clave

### 1. Popover SwiftUI en vez de NSMenu
La primera versión metía vistas personalizadas dentro de un `NSMenu` en tracking, pero esas vistas no reciben clics/botones/clic-derecho de forma fiable. Se migró a un `NSPopover` que hospeda una vista SwiftUI (`NSHostingController`), donde toda la interacción funciona con normalidad.

### 2. Polling vs evento
No existe un callback nativo de "clipboard changed". El polling de `changeCount` cada 1s consume ~0% de CPU y es el estándar de facto (Maccy, Paste, CopyClip lo usan).

### 3. Persistencia de imágenes en disco
Al capturar, la imagen se convierte a PNG (con TIFF crudo como fallback si la conversión falla) y se guarda como fichero individual en la carpeta de imágenes de la app. El `ClipboardItem` solo referencia el nombre del fichero, manteniendo `store.json` ligero.

### 4. Límite por tipo
El límite se aplica **por tipo**: 50 textos y 20 imágenes, nunca un máximo global. Añadir una imagen no puede expulsar textos ni viceversa. Y cuenta **solo los no favoritos**: los favoritos son ilimitados y no consumen cupo. Al desbordar se descarta el no favorito más antiguo de ese tipo (y al caer una imagen se borra su PNG). Al re-copiar un item existente se deduplica en lugar de crear una copia.

### 5. Grupos sobre favoritos
Un item solo puede pertenecer a un grupo, y asignarle grupo lo auto-favorita (así sobrevive al límite por tipo). Des-favoritar lo saca del grupo. El filtro afecta a **todos** los items, no solo a los agrupados.

### 6. El filtro de grupos funciona como chips OR
La selección vive en `isFilterEnabled` de cada grupo más `store.showUngrouped`, y la comparten dos UIs: los chips sobre las listas y los checkboxes de la vista Grupos. Con **nada seleccionado el filtro está inactivo y se ve todo** (`isGroupFilterActive` / `passesGroupFilter`); marcando chips, un item pasa si su grupo está marcado o —si no tiene grupo, lo que incluye a todos los no favoritos— si lo está "Sin grupo". La selección **no se persiste**: `load()` limpia el flag de cada grupo, de modo que la app siempre abre mostrando todo.

### 7. Desplazamiento de los chips por flechas
La tira se maqueta a su ancho intrínseco (`fixedSize`) dentro de un `GeometryReader`, se desplaza con un `offset` y se recorta. Las flechas `‹`/`›` pasan ~80% del ancho visible, se ocultan cuando ese lado se agota y desaparecen ambas si todos los chips caben. Como `clipped()` no recorta el *hit-testing*, hace falta `contentShape(Rectangle())` para que los chips fuera de vista no roben los clics de las flechas.

### 8. Editor del item: texto capturado + nota, sin autenticación
El clic derecho abre un editor con dos áreas: el **texto capturado** (`textContent`, editable solo en items de texto) y una **nota libre** (`ClipboardItem.detail`, opcional). Guardar el texto en blanco se rechaza —dejaría una fila fantasma— y el botón Guardar aparece deshabilitado en ese caso; editar no toca `createdAt` ni el orden, para que un retoque no salte al principio de la lista. Una versión anterior exigía autenticarse con `LocalAuthentication` (Touch ID / contraseña de macOS) para abrir el editor; se retiró porque la nota se guarda **en claro** en `store.json` y cualquiera con acceso al disco la lee sin pasar por la app: el diálogo aportaba fricción, no seguridad. Volver a poner una barrera solo tendría sentido junto con cifrado de la nota (o guardarla en el Keychain).

### 9. Confirmación solo en el borrado masivo
Eliminar un item suelto es directo (🗑, sin confirmación): la pérdida es mínima. Vaciar los no-favoritos de una vista entera sí pide confirmación, e indica que los favoritos se conservan.

## Estructura de carpetas

```
clipboard-manager/
├── docs/
│   ├── 01-vision.md
│   ├── 02-architecture.md
│   ├── 03-user-stories.md
│   └── 04-architecture-diagram.md
├── src/
│   └── ClipboardManager/            ← Proyecto Xcode
│       ├── App/
│       │   ├── AppDelegate.swift    ← @main, LSUIElement, timer de tick
│       │   ├── AppInfo.swift
│       │   └── Info.plist
│       ├── Models/
│       │   ├── ClipboardItem.swift  ← texto/imagen, favorito, groupID, detail
│       │   ├── ClipboardGroup.swift ← id, nombre, filtro
│       │   └── ClipboardStore.swift ← ObservableObject, 50/20 no favoritos por tipo, grupos
│       ├── Monitor/
│       │   └── ClipboardMonitor.swift
│       ├── Persistence/
│       │   └── JSONPersistenceService.swift  ← store.json + groups.json
│       ├── MenuUI/
│       │   ├── StatusItemController.swift    ← NSStatusItem + NSPopover
│       │   ├── PopoverRootView.swift         ← vistas, filas y chips de filtro
│       │   ├── PasteboardHelper.swift        ← copiar + Cmd+V
│       │   ├── DetailEditorWindowController.swift ← editor de nota + RightClickCatcher
│       │   ├── AboutView.swift
│       │   └── AboutWindowController.swift
│       └── Resources/
│           └── Assets.xcassets      ← AppIcon
├── scripts/
│   └── build-release.sh
├── README.md
└── CLAUDE.md
```
