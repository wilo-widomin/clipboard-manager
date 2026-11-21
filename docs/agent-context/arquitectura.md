---
actualizado: 2026-11-21
archivos:
  - Package.swift
  - src/ClipboardManager/App/AppDelegate.swift
  - src/ClipboardManager/App/AppInfo.swift
  - src/ClipboardManager/App/EditMenu.swift
  - src/ClipboardManager/App/Info.plist
  - Sources/ClipboardManagerKit/Persistence/JSONPersistenceService.swift
  - Sources/ClipboardManagerKit/Security/LocalKey.swift
  - Sources/ClipboardManagerKit/Security/FileCipher.swift
  - Sources/ClipboardManagerKit/Security/QuickLookTemporaryFiles.swift
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
`JSONPersistenceService` → `ClipboardStore` → `StatusItemController`. Espera a que
`store.load()` termine y, solo si `persistence.blockingError` es `nil`, arranca el
`Timer` de 1 Hz que llama a `ClipboardMonitor.tick()`. Si no, enseña un aviso y se
cierra sin escribir nada (ver «Datos cifrados en disco»).

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
                                        ↓  AES-256-GCM con la localKey (FileCipher)
                                       disco (también images/*, vía ImageStorage)
```

## Datos cifrados en disco

`store.json`, `groups.json` y cada archivo de `images/` se guardan cifrados. En
memoria todo va en claro: el cifrado vive solo en el borde con el disco
(`JSONPersistenceService` para los JSON, `ImageStorage` para las imágenes), así que
buscador, filas y editor no saben nada de él.

- **Formato** (`Security/FileCipher.swift`): `"CLPE"` (4 bytes) + versión (1 byte,
  hoy `0x01`) + `AES.GCM.SealedBox.combined` (nonce aleatorio de 12 bytes + cifrado +
  etiqueta de 16). La cabecera de 5 bytes va también como dato autenticado. El
  contenido descifrado es el mismo JSON o PNG de siempre.
- **Legado**: un archivo que no empieza por `"CLPE"` es el formato en claro anterior.
  Se sigue leyendo, y `load()` lo migra: cifra en un temporal oculto
  (`.store.json.migrating`) en la misma carpeta, lo relee, comprueba que descifra a
  los mismos bytes y solo entonces hace `rename` sobre el original. Morir a mitad deja
  el original intacto y la migración se repite. Las imágenes se migran todas (también
  las huérfanas) en el mismo `load()`; un fallo en una imagen no bloquea, se reintenta.
- **`localKey`** (`Security/LocalKey.swift`): 32 bytes aleatorios en el Keychain,
  contraseña genérica con servicio `com.widomin.clipboard-manager.local-key` y cuenta
  `localKey`, en el **llavero de sesión** (`kSecUseDataProtectionKeychain = false`).
  El llavero de protección de datos exige entitlements que en macOS solo valen con
  perfil de aprovisionamiento, y `build-release.sh` firma sin perfil. Se pide
  `kSecAttrAccessibleWhenUnlockedThisDeviceOnly`, pero el llavero de sesión no lo
  aplica: la llave está disponible con la sesión abierta, no va a iCloud y viaja en
  Time Machine dentro del llavero, cifrada con la contraseña de la sesión. Se cachea en
  memoria tras la primera lectura.
- **Nunca se crea una llave nueva** si el Llavero responde algo distinto de «no
  existe», ni si no existe pero ya hay algún archivo cifrado en disco: se lanza
  `LocalKeyError` y la persistencia se bloquea.
- **Bloqueo**: si un archivo existente no se puede leer (sin llave, descifrado que
  falla, versión de formato desconocida, JSON roto), `JSONPersistenceService` guarda
  el error en `blockingError` y desde ese momento todo `save` lanza
  `PersistenceError.writesBlocked`. No se escribe nunca en claro: sin llave, no se
  escribe. `ClipboardStore` además no persiste nada hasta que `load()` (o
  `adoptInitialState`) ha terminado, para no pisar el archivo con una lista a medio
  cargar.
- **Quick Look** necesita un archivo: `QuickLookTemporaryFiles` descifra una copia en
  `$TMPDIR/ClipboardManagerKit-QuickLook-<bundle id>/` (carpeta 0700, archivo 0600),
  la borra al terminar `qlmanage` y purga la carpeta entera en cada `load()`.
  `ClipboardItem.imageFileURL` apunta al archivo **cifrado**: no sirve para abrirlo
  fuera de la app.

**Qué protege y qué no**: protege el archivo (copias de seguridad, alguien que se
lleve el disco). No protege frente a quien tenga delante el Mac desbloqueado con la
sesión de Willy. Las copias de Time Machine y las instantáneas de APFS anteriores a la
migración siguen teniendo el historial en claro: cifrar ahora no las reescribe.

**Dos anfitriones, una carpeta.** `JSONPersistenceService()` e `ImageStorage` fijan
la ruta `~/Library/Application Support/ClipboardManager/` sin depender del bundle id,
y Widomin va sin sandbox precisamente para compartir esa carpeta con la app suelta.
Por eso el servicio del Keychain es fijo: los dos encuentran la misma llave. El
elemento lo crea quien arranque primero y su lista de acceso solo incluye esa app; la
otra recibe una vez el aviso del sistema y, con «Permitir siempre», queda autorizada.
Rechazarlo bloquea la persistencia de esa app (no crea otra llave). Un anfitrión debe
comprobar `blockingError` tras `load()` como hace `AppDelegate`.

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
  `groups.json` e `images/*.png`, **cifrados** (los `.png` conservan la extensión pero
  ya no son PNG en disco). `cat store.json` debe enseñar basura que empieza por `CLPE`.
- Una build firmada con otro certificado (o sin firmar) es «otra app» para el
  Llavero: macOS pide permiso para leer la llave. Rechazarlo cierra la app con aviso;
  no se pierde nada.
- Borrar a mano el elemento `com.widomin.clipboard-manager.local-key` del Llavero deja
  los datos ilegibles para siempre: la app se negará a arrancar en vez de crear otra.
- Preferencias sueltas en `UserDefaults`: `viewMode`, `popoverWidth`, `popoverHeight`.
