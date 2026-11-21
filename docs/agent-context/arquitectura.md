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
  - Sources/ClipboardManagerKit/Security/ProtectedKey.swift
  - Sources/ClipboardManagerKit/Security/ProtectedTextCipher.swift
  - Sources/ClipboardManagerKit/UI/PopoverActions.swift
  - Sources/ClipboardManagerKit/Sync/DeviceIdentity.swift
  - Tests/ClipboardManagerKitTests/SyncMergeVectorTests.swift
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
`JSONPersistenceService` → `ClipboardStore`. Espera a que `store.load()` termine y,
solo si `persistence.blockingError` es `nil`, crea el `StatusItemController` (el
icono y el popover), el `ClipboardMonitor` y el `Timer` de 1 Hz que llama a
`tick()`. Antes no hay icono: lo que se creara durante la carga (un grupo, una
contraseña a mano) no se guardaría y `load()` lo sustituiría. Si hay error, enseña un
aviso y se cierra sin escribir nada (ver «Datos cifrados en disco»).

**El menú principal existe aunque no se vea.** Siendo una app `.accessory` no hay
barra de menús, pero AppKit resuelve los atajos de teclado estándar recorriendo
`NSApp.mainMenu`: sin él, Cmd+C / Cmd+V / Cmd+X / Cmd+A / Cmd+Z no funcionan dentro
de ningún campo de texto de la app (editor de item, renombrado de grupo). `EditMenu`
instala un menú «Edición» invisible solo para que esos key equivalents lleguen al
first responder. No lo quites por «no se usa».

```
NSPasteboard → ClipboardMonitor → ClipboardStore (@Published) → SwiftUI en NSPopover
                                        ↓
                       JSONPersistenceService (store.enc / groups.enc)
                                        ↓  AES-256-GCM con la localKey (FileCipher)
                                       disco (también images/*, vía ImageStorage)
```

## Datos cifrados en disco

`store.enc`, `groups.enc` y cada archivo de `images/` se guardan cifrados. En
memoria todo va en claro —salvo el texto de los items protegidos, ver la sección
siguiente—: el cifrado vive solo en el borde con el disco (`JSONPersistenceService`
para los JSON, `ImageStorage` para las imágenes), así que buscador, filas y editor no
saben nada de él.

- **Formato** (`Security/FileCipher.swift`): `"CLPE"` (4 bytes) + versión (1 byte,
  hoy `0x01`) + `AES.GCM.SealedBox.combined` (nonce aleatorio de 12 bytes + cifrado +
  etiqueta de 16). La cabecera de 5 bytes va también como dato autenticado. El
  contenido descifrado es el mismo JSON o PNG de siempre.
- **Nombres nuevos a propósito**: lo cifrado va en `store.enc` y `groups.enc`, nunca
  en `store.json`/`groups.json`. Una versión anterior de la app (sin cifrado) que se
  abra después de migrar trataba un `store.json` ilegible como corrupto, arrancaba
  vacía y lo pisaba en la primera copia: se perdía todo. Con otro nombre, esa versión
  no ve nada, arranca vacía y escribe un `store.json` nuevo en claro, sin tocar el
  cifrado. Las imágenes conservan su nombre: una versión anterior nunca reescribe un
  archivo de imagen existente (cada captura usa un UUID nuevo y solo borra las de sus
  propios items).
- **Fusión con el nombre antiguo** (`JSONPersistenceService.loadMerging`): si al
  cargar existe `store.json` —en claro de una versión anterior, o ya cifrado (`CLPE`)
  por una build sin publicar de §3.1—, sus items se suman a los de `store.enc` (los
  que no tengan ya su `id`; si no hay `store.enc`, es la migración de siempre). Los
  protegidos que traigan el texto en claro se cifran con la `protectedKey` antes de
  escribir (`ProtectedTextCipher.sealLegacyProtectedTexts`, la misma que usa
  `adoptInitialState`). El resultado se escribe en `store.enc`, se relee y se
  comprueba, y solo entonces se borra `store.json`. Morir a mitad deja `store.json`
  intacto y la fusión se repite sin duplicar (por `id`). Igual con `groups.json`. Las
  imágenes en claro se migran todas (también las huérfanas) en el mismo `load()`,
  mirando solo la cabecera de cada archivo (`FileCipher.fileIsEncrypted(at:)`); un
  fallo en una imagen no bloquea, se reintenta.
- **Escritura durable** (`writeDurably`): migraciones y cada guardado de `store.enc`
  y `groups.enc` escriben en un temporal oculto de la misma carpeta
  (`.<nombre>.<UUID>.migrating`, permisos 0600), lo llevan al disco con
  `fcntl(F_FULLFSYNC)` (o `fsync` si el volumen no lo admite), lo releen y comprueban
  si es una migración, hacen `rename` y sincronizan la carpeta. Un corte de luz no
  deja un archivo cifrado a medias en lugar del original. El UUID evita que la app
  suelta y Widomin se pisen el temporal; `load()` solo borra los temporales de más de
  diez minutos. Las imágenes nuevas se siguen escribiendo con `.atomic` sin
  `F_FULLFSYNC`.
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
  `PersistenceError.writesBlocked` e `ImageStorage.write` también se niega
  (`ImageStorage.blockWrites()`). `blockingError` forma parte del protocolo
  `PersistenceService`, y con él `ClipboardStore.isPersistenceBlocked` es `true`: el
  store no añade (`add`, `addManual`, `addGroup`) ni guarda, y `ClipboardMonitor` no
  captura. Así un anfitrión que no mire `blockingError` tampoco llena un historial
  vacío. No se escribe nunca en claro: sin llave, no se escribe. `ClipboardStore`
  además no persiste nada hasta que `load()` (o `adoptInitialState`) ha terminado,
  para no pisar el archivo con una lista a medio cargar.
- **Quick Look** necesita un archivo: `QuickLookTemporaryFiles` descifra una copia en
  `$TMPDIR/ClipboardManagerKit-QuickLook-<bundle id>/` (carpeta 0700, archivo 0600),
  la borra al terminar `qlmanage` y purga la carpeta entera en cada `load()`.
  `ClipboardItem.imageFileURL` apunta al archivo **cifrado**: no sirve para abrirlo
  fuera de la app.

**Qué protege y qué no**: protege el archivo (copias de seguridad, alguien que se
lleve el disco). No protege frente a quien tenga delante el Mac desbloqueado con la
sesión de Willy. Las copias de Time Machine y las instantáneas de APFS anteriores a la
migración siguen teniendo el historial en claro: cifrar ahora no las reescribe.

## Texto protegido con su propia llave

El texto de un item protegido se cifra **otra vez**, dentro del `store.enc` ya
cifrado, con la `protectedKey` (§3.2 del blueprint). En memoria tampoco está en claro:
el item lleva `textContent = nil` y el texto en `sealedText`. Solo
`ProtectedAccess.reveal` lo descifra, en una copia, tras autenticar.

- **Par de llaves, no una sola** (`Security/ProtectedKey.swift`): la `protectedKey` es
  un par X25519; la privada son 32 bytes aleatorios. Cifrar usa la pública y no pide
  nada, así que proteger, crear una contraseña protegida y migrar no piden el dedo.
  Descifrar usa la privada, que solo se saca del Llavero tras autenticar.
- **Cifrado** (`Security/ProtectedTextCipher.swift`): llave efímera X25519 por
  cifrado, HKDF-SHA256 (sal = pública efímera ‖ pública de destino) y AES-256-GCM.
  Formato `"CLPP"` + versión `0x01` + pública efímera (32) + `combined`, en base64; la
  cabecera y la efímera van como dato autenticado.
- **Dónde vive cada parte**: las dos con servicio fijo
  `com.widomin.clipboard-manager.protected-key`. La pública (cuenta
  `protectedPublicKey`) en el llavero de sesión, sin control: no es secreta. La privada
  (cuenta `protectedKey`) se intenta guardar en el **llavero de protección de datos con
  `SecAccessControl` `.userPresence`**; si la build no tiene el entitlement
  (`errSecMissingEntitlement`, -34018), cae al **llavero de sesión sin control de
  presencia**. Al leer se mira primero el de protección de datos y después el de sesión.
- **Qué impone macOS y qué impone la app.** El llavero de sesión no admite
  `kSecAttrAccessControl` (lo ignora), y el de protección de datos exige el
  entitlement `keychain-access-groups`, que en macOS solo vale con un perfil de
  aprovisionamiento. `build-release.sh` firma sin perfil, así que **hoy la privada está
  en el llavero de sesión y quien exige Touch ID es la app** (`ProtectedAccess` llama a
  `evaluatePolicy` antes de leerla). El sistema solo impone lo mismo que con la
  `localKey`: sesión abierta y lista de acceso atada a la firma. Lo que sí se gana hoy:
  el texto protegido no está en claro en memoria (salvo al pegar o con el editor
  abierto), ni en un `store.enc` descifrado con la `localKey`; y la llave privada solo
  está en memoria los 15 minutos de la ventana de gracia. Con una build firmada con
  perfil y la capacidad «Keychain Sharing», las llaves **nuevas** quedarían bajo
  `.userPresence` impuesto por macOS; una llave ya creada en el llavero de sesión no se
  mueve sola (pendiente).
- **Una sola autenticación**: `ProtectedAccess.authenticate` evalúa
  `deviceOwnerAuthentication` y pasa ese mismo `LAContext` (`kSecUseAuthenticationContext`)
  a la lectura de la privada, para que el llavero de protección de datos no vuelva a
  preguntar.
- **Ventana de gracia**: la privada se queda en `ProtectedKey` mientras dura; al
  cumplirse los 15 minutos (`asyncAfter(wallDeadline:)`, que cuenta también el tiempo
  dormido, y comprobación en cada `isUnlocked`) se olvida.
- **Nunca se pierde texto**: no se crea un par nuevo si ya hay algún `sealedText`
  (`keyMissingButSealedTextExists`); no se cifra hacia una pública cuya privada no
  aparece en ningún llavero (comprobado solo con atributos, sin pedir el dedo), ni
  hacia una que no es la pareja de la privada: la privada lleva su pública apuntada en
  `kSecAttrGeneric` y, si no casa, `publicKeyMismatch` (sin el atributo, de una build
  anterior, se acepta); al desbloquear la privada se compara también su pública
  derivada. El par se crea privada primero y pública después, y se relee la pública. Si no hay llave, no
  se protege ni se crea nada protegido, y la migración deja el texto como estaba.
- **Migración**: `ClipboardStore.adoptInitialState` (también vía `load()`) cifra en
  memoria los items protegidos con texto en claro y escribe una vez con `persist()`
  (escritura atómica): morir a mitad deja el archivo anterior intacto.
- **Dos anfitriones**: si uno tuviera el entitlement y el otro no, el segundo no vería
  una privada creada en el llavero de protección de datos y no podría revelar (no
  pierde nada). Hoy ninguno lo tiene.
- **Sincronización (sin red todavía)**: el modelo local ya es sincronizable (§6:
  marcas por campo, tombstones, `imageHash`, `SyncMerge`; ver `historial/_dominio.md`),
  pero el texto protegido sigue sin resolver: la `protectedKey` no sale del aparato, así que
  un `sealedText` no se puede leer en otro. Al sincronizar habrá que decidir si el texto
  protegido viaja descifrado y recifrado con la llave del sync (exige autenticar en el
  aparato que lo sube) o cifrado hacia la pública de cada aparato (el par X25519 lo
  permite).

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

- Todo lo de UI y el store son `@MainActor`; la persistencia va sobre una
  `DispatchQueue` serie propia con escritura atómica. El store guarda con
  `enqueueSave` / `enqueueSaveGroups`, que encolan en esa cola desde el hilo
  principal sin `Task`, para que las escrituras salgan en el orden de los cambios; el
  `save` asíncrono sigue para compatibilidad.
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

**Tests del paquete con `swift test`** (en el Mac; en Linux no hay compilador). El
target `ClipboardManagerKitTests` (`Tests/ClipboardManagerKitTests/`, declarado en
`Package.swift`) pasa los vectores de fusión de `Tests/vectors/merge-vectors.json`
por `SyncMerge` y prueba marcas y tombstones del store con una persistencia en
memoria (`PersistenceService` es un protocolo) y un `deviceId` fijo. Solo items de
texto sin proteger: no tocan el Llavero ni `images/`. Los vectores no usan recursos
de SwiftPM: el test los busca desde su propio `#filePath`, para que el JSON quede en
una carpeta neutra que Kotlin y Rust copien.

El proyecto de Xcode no ve esos tests: su target `ClipboardManagerTests` apunta a
`tests/ClipboardManagerTests/`, que no existe (en el disco del Mac, que no distingue
mayúsculas, sería `Tests/ClipboardManagerTests/`, otra carpeta) y no tiene tests.

## Trampas

- El binario necesita permiso de **Accesibilidad** o el `Cmd+V` sintético se descarta
  en silencio (`PasteboardHelper.postCmdV` lo detecta y lanza el prompt del sistema).
- El `.dmg` se firma con "Apple Development" y **no se notariza**: en la máquina de
  destino hay que abrirlo la primera vez con clic derecho → Abrir.
- Datos de usuario en `~/Library/Application Support/ClipboardManager/`: `store.enc`,
  `groups.enc` e `images/*.png`, **cifrados** (los `.png` conservan la extensión pero
  ya no son PNG en disco). `head -c 4 store.enc` debe enseñar `CLPE`. Un `store.json`
  o `groups.json` ahí es de una versión anterior (o de una build sin publicar) y
  desaparece en el siguiente arranque, fundido en el `.enc`.
- Una build firmada con otro certificado (o sin firmar) es «otra app» para el
  Llavero: macOS pide permiso para leer la llave. Rechazarlo cierra la app con aviso;
  no se pierde nada.
- Borrar a mano el elemento `com.widomin.clipboard-manager.local-key` del Llavero deja
  los datos ilegibles para siempre: la app se negará a arrancar en vez de crear otra.
  Lo mismo con `com.widomin.clipboard-manager.protected-key` para los textos
  protegidos: la app arranca, pero no puede revelarlos ni protege nada nuevo.
- Preferencias sueltas en `UserDefaults`: `viewMode`, `popoverWidth`, `popoverHeight`.
- `device-id` en la carpeta de datos es el `deviceId` de las marcas de cambio: un
  UUID en claro, no secreto. Borrarlo solo hace que se cree otro; no se pierde nada.
- `store.enc` y `groups.enc` guardan también los **tombstones** (lo borrado que fue
  favorito, y los grupos borrados), sin contenido. Una versión anterior los enseñaría
  como filas o grupos vacíos.
