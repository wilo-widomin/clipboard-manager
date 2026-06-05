# Clipboard Manager — Diseño de Arquitectura (ADD)

## Justificación de tecnologías

| Decisión | Opción | Motivo |
|---|---|---|
| Interfaz de menú | AppKit NSStatusItem | Única forma de tener un icono persistente en la barra de menús de macOS |
| Listado dinámico | NSMenuItem + NSView personalizado | Misma técnica que menu-timer: permite vistas complejas (imagen, botones) dentro del menú |
| Submenú de vistas | NSMenu con items (submenu) | Mecanismo nativo de AppKit para cambiar entre Texto e Imágenes |
| Persistencia | JSON con Codable | Misma aproximación que menu-timer. Simple, sin dependencias, atómico |
| Monitorización | Polling NSPasteboard.changeCount | Única forma fiable en macOS. El coste es despreciable (comparar entero cada 1s) |
| Miniaturas | NSImage a 80×80 | Representación eficiente: se escala al capturar y se guarda en el JSON como Data (PNG) |
| Vista Previa | `qlmanage -p` via Process | Lanzador externo que no bloquea el menú |

## Patrones de diseño

- **MVVM**: ClipboardStore como ObservableObject, menú actualizado por binding
- **Strategy**: ClipboardMonitor protocol con implementación por polling
- **Repository**: PersistenceService protocol con JSONPersistenceService
- **Composite**: MenuBuilder que construye el menú dinámicamente

## Decisiones técnicas clave

### 1. Polling vs evento
No existe un callback nativo de "clipboard changed". El polling de `changeCount` cada 1s consume ~0% de CPU y es el estándar de facto (Maccy, Paste, CopyClip lo usan).

### 2. Formato de persistencia de imágenes
Las imágenes se convierten a `Data` (PNG) en el momento de la captura y se almacenan en el JSON como string base64. Esto evita archivos sueltos y mantiene la portabilidad. El tamaño se limita a 10MB por imagen para evitar bloat.

### 3. Sin confirmación al eliminar
A diferencia del menu-timer, eliminar un item del clipboard no tiene consecuencia destructiva (no es un timer corriendo). Se elimina directamente.

### 4. Submenú como selector de vista
El menú principal tiene un ítem "View" con submenú: "Text" / "Images". Al seleccionar, se reconstruye el menú con los items correspondientes.

## Estructura de carpetas

```
clipboard-manager/
├── docs/
│   ├── 01-vision.md
│   ├── 02-architecture.md
│   ├── 03-user-stories.md
│   └── 04-architecture-diagram.md
├── src/
│   └── ClipboardManager/       ← Proyecto Xcode
│       ├── App/
│       │   ├── AppDelegate.swift
│       │   └── Info.plist
│       ├── Models/
│       │   ├── ClipboardItem.swift
│       │   └── ClipboardStore.swift
│       ├── Monitor/
│       │   └── ClipboardMonitor.swift
│       ├── Persistence/
│       │   └── JSONPersistenceService.swift
│       ├── MenuUI/
│       │   ├── StatusItemController.swift
│       │   ├── MenuBuilder.swift
│       │   ├── TextRowView.swift
│       │   └── ImageRowView.swift
│       ├── Forms/
│       │   └── ViewSelectorView.swift
│       └── Resources/
│           ├── Assets.xcassets
│           └── menubar-icon.png
├── tests/
│   └── ClipboardManagerTests/
├── README.md
└── CLAUDE.md
```