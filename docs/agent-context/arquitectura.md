---
actualizado: 2026-08-21
archivos:
  - Package.swift
  - src/ClipboardManager/App/AppDelegate.swift
  - src/ClipboardManager/App/AppInfo.swift
  - src/ClipboardManager/App/EditMenu.swift
  - src/ClipboardManager/App/Info.plist
  - Sources/ClipboardManagerKit/Persistence/JSONPersistenceService.swift
  - Sources/ClipboardManagerKit/UI/PopoverActions.swift
  - ClipboardManager.xcodeproj/project.pbxproj
  - scripts/build-release.sh
---

# Arquitectura

## Stack

App de barra de menús para **macOS 13+**, Swift 5 (`SWIFT_VERSION = 5.0` en el
pbxproj, aunque el código usa idioms 5.9), AppKit + SwiftUI, sin dependencias
externas. `LSUIElement = YES`: agente sin Dock ni menú de aplicación.

## Paquete y app: una sola copia

Casi todo el código vive en el Swift Package **ClipboardManagerKit**
(`Sources/ClipboardManagerKit/`, declarado en `Package.swift`). Lo consumen dos
anfitriones:

- **La app suelta de este repo.** Su target compila el directorio del paquete
  directamente, mediante un segundo `fileSystemSynchronizedGroup` en el `.pbxproj`.
  No enlaza el paquete: compila las mismas fuentes dentro de su módulo, así que no
  lleva `import ClipboardManagerKit`.
- **Widomin**, que sí lo consume como dependencia SPM remota y por tanto es quien
  valida de verdad la frontera pública del paquete.

Nunca dupliques un archivo para "adaptarlo" a un anfitrión: lo que varía entre uno y
otro se inyecta (ver `PopoverActions` y el flag `ownsWindow` más abajo).

En `src/ClipboardManager/` solo queda lo que exige ser dueño de la barra de menús:
`AppDelegate`, `StatusItemController` (foco y pegado), About y `AppInfo`.

## Capas

`AppDelegate` (entry point programático, sin storyboard) instala el menú principal
mínimo de `EditMenu` y crea
`JSONPersistenceService` → `ClipboardStore` → `StatusItemController`, y arranca un
`Timer` de 1 Hz que llama a `ClipboardMonitor.tick()`.

**El menú principal existe aunque no se vea.** Siendo una app `.accessory` no hay
barra de menús, pero AppKit resuelve los atajos de teclado estándar recorriendo
`NSApp.mainMenu`: sin él, Cmd+C / Cmd+V / Cmd+X / Cmd+A / Cmd+Z no funcionan dentro
de ningún campo de texto de la app (editor de item, renombrado de grupo). `EditMenu`
instala un menú «Edición» invisible solo para que esos key equivalents lleguen al
first responder. No lo quites por «no se usa».

```
NSPasteboard → ClipboardMonitor → ClipboardStore (@Published) → SwiftUI en NSPopover
                                        ↓
                       JSONPersistenceService (store.json / groups.json)
```

`ClipboardStore` es la única fuente de verdad: todo lo que sea mutación de datos va
directo al store desde las vistas. Solo lo que necesita AppKit (pegar, Quick Look,
abrir la ventana del editor) pasa por `PopoverActions`, un struct de callbacks que
el anfitrión inyecta en `PopoverRootView` — aquí `StatusItemController`, en Widomin
su adaptador de módulo.

Esa es la costura entre anfitriones, y hay solo dos cosas que varían:

- **`PopoverActions`** — la app suelta captura la app que tenía el foco antes de
  abrir su popover y la reactiva para hacer el `Cmd+V`; un anfitrión que ya es dueño
  del popover no tiene foco que restaurar.
- **`PopoverRootView(store:actions:ownsWindow:)`** — con `ownsWindow: true` (el
  valor por defecto, el de la app suelta) la vista fija su propio tamaño y dibuja los
  tiradores de redimensión. Con `false` se limita a llenar el espacio que le den,
  porque el tamaño lo manda el anfitrión.

## Convenciones

- Todo lo de UI y el store son `@MainActor`; la persistencia es `async` sobre una
  `DispatchQueue` propia con escritura `.atomic`.
- Los ficheros del proyecto se descubren por `fileSystemSynchronizedGroups`: añadir o
  borrar un `.swift` bajo `src/` o bajo `Sources/ClipboardManagerKit/` **no requiere
  tocar el `.pbxproj`**.
- Lo que el paquete expone a sus anfitriones va marcado `public`. Compilando solo la
  app suelta ese `public` no se comprueba (todo cae en un módulo): quien detecta que
  falta uno es el build de Widomin.
- Textos de UI en español; comentarios y símbolos en inglés.
- Los campos nuevos de los modelos se declaran opcionales con valor por defecto para
  que un `store.json` de una versión anterior siga decodificando (ver
  `historial/_dominio.md`).

## Arrancar y probar

```bash
swift build                                           # solo el paquete (rápido)
open ClipboardManager.xcodeproj                       # ⌘R
xcodebuild -project ClipboardManager.xcodeproj -scheme ClipboardManager build
./scripts/build-release.sh [version]                  # dist/ClipboardManager-<v>.dmg
```

`swift build` compila el paquete aislado y es la forma más rápida de comprobar que la
frontera pública sigue en pie sin arrancar Xcode.

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
