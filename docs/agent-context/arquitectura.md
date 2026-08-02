---
actualizado: 2026-08-02
archivos:
  - src/ClipboardManager/App/AppDelegate.swift
  - src/ClipboardManager/App/AppInfo.swift
  - src/ClipboardManager/App/Info.plist
  - src/ClipboardManager/Persistence/JSONPersistenceService.swift
  - ClipboardManager.xcodeproj/project.pbxproj
  - scripts/build-release.sh
---

# Arquitectura

## Stack

App de barra de menús para **macOS 13+**, Swift 5 (`SWIFT_VERSION = 5.0` en el
pbxproj, aunque el código usa idioms 5.9), AppKit + SwiftUI, sin dependencias
externas. `LSUIElement = YES`: agente sin Dock ni menú de aplicación.

## Capas

`AppDelegate` (entry point programático, sin storyboard) crea
`JSONPersistenceService` → `ClipboardStore` → `StatusItemController`, y arranca un
`Timer` de 1 Hz que llama a `ClipboardMonitor.tick()`.

```
NSPasteboard → ClipboardMonitor → ClipboardStore (@Published) → SwiftUI en NSPopover
                                        ↓
                       JSONPersistenceService (store.json / groups.json)
```

`ClipboardStore` es la única fuente de verdad: todo lo que sea mutación de datos va
directo al store desde las vistas. Solo lo que necesita AppKit (pegar, Quick Look,
abrir la ventana del editor) pasa por `PopoverActions`, un struct de callbacks que
`StatusItemController` inyecta en `PopoverRootView`.

## Convenciones

- Todo lo de UI y el store son `@MainActor`; la persistencia es `async` sobre una
  `DispatchQueue` propia con escritura `.atomic`.
- Los ficheros del proyecto se descubren por `fileSystemSynchronizedGroups`: añadir o
  borrar un `.swift` bajo `src/` **no requiere tocar el `.pbxproj`**.
- Textos de UI en español; comentarios y símbolos en inglés.
- Los campos nuevos de los modelos se declaran opcionales con valor por defecto para
  que un `store.json` de una versión anterior siga decodificando (ver
  `historial/_dominio.md`).

## Arrancar y probar

```bash
open ClipboardManager.xcodeproj                       # ⌘R
xcodebuild -project ClipboardManager.xcodeproj -scheme ClipboardManager build
./scripts/build-release.sh [version]                  # dist/ClipboardManager-<v>.dmg
```

**No hay suite de tests**: `tests/ClipboardManagerTests/` existe pero está vacía.
`PersistenceService` es un protocolo y `JSONPersistenceService` acepta un `fileURL`
propio precisamente para poder inyectarlo en tests cuando se escriban.

## Trampas

- El binario necesita permiso de **Accesibilidad** o el `Cmd+V` sintético se descarta
  en silencio (`PasteboardHelper.postCmdV` lo detecta y lanza el prompt del sistema).
- El `.dmg` se firma con "Apple Development" y **no se notariza**: en la máquina de
  destino hay que abrirlo la primera vez con clic derecho → Abrir.
- Datos de usuario en `~/Library/Application Support/ClipboardManager/`: `store.json`,
  `groups.json` y `images/*.png`. Todo en claro; no es un almacén de secretos.
- Preferencias sueltas en `UserDefaults`: `viewMode`, `popoverWidth`, `popoverHeight`.
