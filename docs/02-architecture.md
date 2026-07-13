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
El máximo de 100 items se aplica **por tipo** (texto e imágenes por separado). Añadir una imagen no puede expulsar textos ni viceversa. Al re-copiar un item existente se deduplica en lugar de crear una copia.

### 5. Grupos sobre favoritos
Un item solo puede pertenecer a un grupo, y asignarle grupo lo auto-favorita (así sobrevive al límite por tipo). Des-favoritar lo saca del grupo. Los checkboxes de la vista Grupos filtran qué items aparecen en las listas de texto/imágenes (incluida la fila fija "Sin grupo").

### 6. Sin confirmación al eliminar
Eliminar un item del historial no tiene consecuencia destructiva. Se elimina directamente.

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
│       │   ├── ClipboardItem.swift  ← texto/imagen, favorito, groupID
│       │   ├── ClipboardGroup.swift ← id, nombre, filtro
│       │   └── ClipboardStore.swift ← ObservableObject, máx 100, grupos
│       ├── Monitor/
│       │   └── ClipboardMonitor.swift
│       ├── Persistence/
│       │   └── JSONPersistenceService.swift  ← store.json + groups.json
│       ├── MenuUI/
│       │   ├── StatusItemController.swift    ← NSStatusItem + NSPopover
│       │   ├── PopoverRootView.swift         ← vistas y filas SwiftUI
│       │   ├── PasteboardHelper.swift        ← copiar + Cmd+V
│       │   ├── AboutView.swift
│       │   └── AboutWindowController.swift
│       └── Resources/
│           └── Assets.xcassets      ← AppIcon
├── scripts/
│   └── build-release.sh
├── README.md
└── CLAUDE.md
```
