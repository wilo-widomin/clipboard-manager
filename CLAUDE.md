# Clipboard Manager

macOS menubar app for clipboard history — text & images, favorites, groups.

> Contexto por dominios para agentes en `docs/agent-context/` — empieza por su
> `INDEX.md` y abre solo el dominio de la tarea. Al cambiar código, actualiza el
> documento que declare esos archivos (`ac-stale.py --changed` los detecta).

## Architecture

- **AppKit** `NSStatusItem` hosting a **SwiftUI popover** (`NSPopover` + `NSHostingController`).
  We moved off `NSMenu`: custom rows inside a tracking `NSMenu` can't reliably receive
  clicks/buttons/right-click/nested menus. In a popover, SwiftUI handles all of that.
- **Popover behaviour** = `.applicationDefined` (a `.transient` popover can't become key
  in an inactive LSUIElement app and closes instantly); closed via a global outside-click
  monitor. Showing it activates the app, so the paste target is captured *before* that.
- **Left-click** the status item toggles the popover; **right-click** shows a small
  native menu (Abrir / About / Quit) — the only remaining `NSMenu` in the app.
- **Resizable popover**: a reserved 8px border on the right/bottom holds drag handles
  (right edge = width, bottom edge = height, corner = both). The size is persisted in
  UserDefaults and drives `preferredContentSize` via `NSHostingController.sizingOptions`.
- **JSON persistence** via Codable in `~/Library/Application Support/ClipboardManager/store.enc`,
  **cifrado** con AES-256-GCM (CryptoKit) igual que `groups.enc` e `images/*`. La `localKey`
  (32 bytes) vive en el llavero de sesión (servicio fijo `com.widomin.clipboard-manager.local-key`,
  compartido con Widomin). Formato: `CLPE` + versión + `SealedBox.combined`. Los cifrados **no** se
  llaman `store.json`/`groups.json` a propósito: así una versión antigua de la app no los pisa. Un
  `store.json`/`groups.json` que aparezca (en claro o cifrado) se funde por `id` en el `.enc` en
  `load()` y se borra. Si algo existente no se puede leer, la persistencia se bloquea y no escribe
  nada (`blockingError`, parte del protocolo `PersistenceService`); el store deja de añadir y la app
  avisa y se cierra. El icono no aparece hasta que `load()` termina. Detalle en `docs/agent-context/arquitectura.md`.
- **1 Hz polling** of `NSPasteboard.changeCount` for clipboard monitoring
- **macOS 13+** minimum target
- **LSUIElement = YES** (agent app, no Dock)

## Project structure

Everything reusable lives in the **ClipboardManagerKit** Swift Package; the app is a
thin shell around it. There is exactly **one copy of each file** — the standalone app
target compiles `Sources/ClipboardManagerKit/` directly (a second
`fileSystemSynchronizedGroup`), and Widomin consumes the same directory as an SPM
dependency. Never copy a file into `src/` to "adapt" it.

```
Package.swift                  — product ClipboardManagerKit, macOS 13+
Sources/ClipboardManagerKit/   — SHARED: everything both hosts need
├── Models/
│   ├── ClipboardItem.swift    — item model (text/image, favorite, date, groupID)
│   ├── ClipboardGroup.swift   — group model (id, name, isFilterEnabled)
│   └── ClipboardStore.swift   — ObservableObject, per-type caps, fav sorting, groups
├── Monitor/
│   └── ClipboardMonitor.swift — polls changeCount, reads text or TIFF/PNG
├── Persistence/
│   └── JSONPersistenceService.swift  — async JSON read/write cifrado (store.enc + groups.enc), fusión de los .json antiguos, bloqueo
├── Security/
│   ├── ProtectedAccess.swift  — Touch ID / contraseña del Mac + ventana de gracia (15 min); `reveal` descifra
│   ├── ProtectedKey.swift     — `protectedKey` (par X25519) en el Keychain; nunca crea otra si hay texto cifrado
│   ├── ProtectedTextCipher.swift — cifra el texto de los items protegidos (X25519 + HKDF + AES-GCM)
│   ├── PasswordGenerator.swift — generador de contraseñas (largo, tipos, símbolos extra)
│   ├── LocalKey.swift         — `localKey` en el Keychain; nunca crea otra si hay datos cifrados
│   ├── FileCipher.swift       — AES-256-GCM y formato de archivo cifrado
│   └── QuickLookTemporaryFiles.swift — copia descifrada temporal (0700) para Quick Look
├── Sync/                      — modelo sincronizable, sin red (§6 del blueprint)
│   ├── SyncStamp.swift        — marca (updatedAt, deviceId) + ItemFieldStamps
│   ├── SyncMerge.swift        — fusión pura last-write-wins por campo; aún no la llama nadie
│   └── DeviceIdentity.swift   — deviceId estable en el archivo device-id
└── UI/
    ├── PopoverRootView.swift         — SwiftUI popover: Texto/Imágenes/Grupos + rows
    ├── PopoverActions.swift          — the seam: what each host injects
    ├── PasteboardHelper.swift        — copy + reactivate target + Cmd+V
    ├── DetailEditorWindowController.swift — item editor window + RightClickCatcher
    └── PasswordCreatorWindowController.swift — modal «Nueva contraseña» (item manual + generador)

Tests/                         — `swift test` (solo SwiftPM; el proyecto de Xcode no lo ve)
├── ClipboardManagerKitTests/  — vectores de fusión + marcas y tombstones del store
└── vectors/merge-vectors.json — vectores neutrales que copiarán Kotlin y Rust (§9)

src/ClipboardManager/          — STANDALONE APP ONLY
├── App/
│   ├── AppDelegate.swift     — @main entry, LSUIElement, tick timer
│   ├── AppInfo.swift         — name, version, author credit (widomin.com)
│   ├── EditMenu.swift        — menú principal invisible: sin él no hay Cmd+C/V en los campos
│   └── Info.plist
├── MenuUI/
│   ├── StatusItemController.swift    — NSStatusItem + NSPopover lifecycle, focus/paste
│   └── AboutView.swift / AboutWindowController.swift
└── Resources/
    └── Assets.xcassets
```

**What goes where:** if a second host would need it, it belongs in the Kit. What stays
in the app is only what makes sense when *this* app owns the menu bar — the status
item, stealing and restoring focus to paste, its own About window and version string.

`PopoverRootView(store:actions:ownsWindow:)` is the entry point. `ownsWindow` defaults
to `true`: the standalone app hosts the view in its own `NSPopover`, so the view sets
its size and draws the resize handles. A host that already owns the window (Widomin)
passes `false` and the view just fills the space it is given.

The Texto/Imágenes lists are **split in two independently scrolling panes** (`splitList`):
favourites on top, non-favourite history below, separated by the same heavy
`favoriteDivider`. The favourites pane is sized to at most `maxFavoriteRows` (15) rows
and never more than half the available height (an image row is ~78pt, so 15 would leave
the history no room); with no history below it takes the whole area. One shared scroll
is not an option — favourites are unlimited and would push the history off the bottom.

`PopoverRootView` holds the SwiftUI views: a segmented Texto/Imágenes/Grupos picker,
a search box (filters by text, title and note),
`ClipboardTextRow` / `ClipboardImageRow` (each with a 📁 `Menu` for group assignment,
⭐ favourite, 🗑 delete, and 👁 Quick Look on images), and `GroupsManageView` /
`GroupManageRow` (checkbox filter + inline rename + delete). It also owns the resize
handles (`PopoverSize` persists the size) and the pointing-hand / resize cursors
(`.onContinuousHover` + `NSCursor`; the diagonal corner cursor uses a guarded private
AppKit selector via `Cursors`). Plain data mutations call `ClipboardStore` directly;
only paste and Quick Look go through `PopoverActions` on the controller (About/Quit
live in the status-item right-click menu).

## Models

- **ClipboardItem**: id, contentType(.text/.image), createdAt, textContent, imageFilename(PNG on disk, cifrado; leer con `ImageStorage.readData`/`loadImage`, nunca con `imageFileURL`), isFavorite, groupID(optional), detail(optional), title(optional), isProtected(bool, text only), sealedText(optional: texto protegido cifrado; con él `textContent` es nil). `groupID` and `detail` are optional so older `store.json` files decode cleanly.
- **ClipboardGroup**: id, name, isFilterEnabled, nameStamp?, deletion?. Persisted separately in `groups.enc`.
- **Modelo sincronizable** (§6 de `docs/05-blueprint-sync-android.md`, todavía sin red): los
  items llevan además `imageHash?` (SHA-256 en hexadecimal del PNG en claro), `stamps` (una
  marca `(updatedAt, deviceId)` por campo: content = textContent+sealedText+isProtected, detail,
  title, favorite, protection (solo informativa), group) y `deletion?`. Cada mutación del store marca solo los campos que
  cambian de verdad; una marca ausente es implícita —`(createdAt, "")` en items, `(1970, "")` en
  grupos— y nunca se escribe al cargar. Quitar algo que **es o fue** favorito (borrar, tope,
  vaciar) y borrar cualquier grupo deja un **tombstone** sin contenido en `itemTombstones` /
  `groupTombstones`; el historial que nunca fue favorito se sigue borrando de verdad. `items` y
  `groups` solo tienen lo vivo, así que vistas, topes, buscador, deduplicación y filtro de grupos
  no ven nunca un tombstone. En disco también van aparte, en `item-tombstones.enc` y
  `group-tombstones.enc` (mismo cifrado y escritura durable que `store.enc`, y se escriben
  antes que los vivos): `store.enc`/`groups.enc` solo tienen registros vivos, para que una
  versión anterior o un Widomin con un Kit anterior no los tome por filas en blanco. Quitar la estrella deja el item
  aquí (`hasLeftSyncedSet`) hasta que el tope lo recicle. Deduplicar conserva el `id` y las
  marcas del item sustituido. El `deviceId` vive en el archivo `device-id` junto a `store.enc`
  (lo comparten la app y Widomin). `SyncMerge.merge(local:remote:)` es pura y la fijan los
  vectores de `Tests/vectors/merge-vectors.json`. Detalle en
  `docs/agent-context/historial/_dominio.md`.
- **ClipboardStore**: `@Published items` + `@Published groups`. Favourites first (by date desc), then rest (by date desc), with a divider drawn at the boundary. Capped **per content type** — 50 text, 20 images — never globally, and the cap counts **only non-favourites**: favourites are unlimited and don't consume the budget, `cap` evicts the oldest non-favourite of that type (dropping an image deletes its PNG). `visibleItems` filtered by `viewMode`, the per-group checkbox filter (applies to **all** items — see Groups) and the search box (`searchQuery`, matched against text, title and note; de un item protegido, solo título y nota).

## Groups

- A favourite can belong to at most one group. Assigning a group auto-favourites the item (so it survives the per-type cap); un-favouriting removes it from its group.
- Assign/reassign via the 📁 `Menu` on each text/image row — it lists the groups,
  "Sin grupo", and "Nuevo grupo…". (Right-click on rows was dropped: the 📁 button covers it.)
- The **Grupos** view manages groups: **inline rename** (edit the name field, Enter to
  commit), delete (trash), and create via **"Nuevo grupo"** (a SwiftUI `.alert` with a
  text field — the same alert backs "Nuevo grupo…" from the assignment menu, which then
  auto-assigns the new group to the item). Deleting a group keeps the items and only
  clears their `groupID`.
- The group filter works like a set of **OR filter chips** (`passesGroupFilter` /
  `isGroupFilterActive`): with **nothing selected the filter is inactive and every
  item shows** — the default a fresh popover opens with. Selecting one or more chips
  narrows the Text/Images lists to those groups (an item passes if its group is
  selected, or — for ungrouped items, which includes every non-favourite since only
  favourites can hold a group — if "Sin grupo" is selected).
- The selection lives in each group's `isFilterEnabled` and `store.showUngrouped`, but
  is **not persisted**: it resets to empty every launch (init doesn't restore it and
  `load()` clears each loaded group's `isFilterEnabled`), so the app always opens
  showing everything.
- Two UIs drive the same selection: the **badges** (`GroupFilterBadges`) in a
  horizontal strip above the Texto/Imágenes lists (one capsule per group + "Sin grupo",
  followed by a `Divider`; a selected chip is filled with the accent colour, an
  unselected one is drawn hollow), and the **checkboxes** in the Grupos tab.
- The badge strip **scrolls with arrows, not a scrollbar**: the chips are laid out at
  their intrinsic width (`fixedSize`) inside a `GeometryReader`, shifted by an `offset`
  state and clipped. `‹` / `›` chevrons on each side page it by ~80% of the visible
  width; each chevron keeps its slot but goes transparent/inert when that side is
  exhausted, and both vanish when every chip fits (`overflows`, from content width —
  measured with `ContentWidthKey` — vs viewport width).

## Editor por item (texto + detalle)

- Each item can carry a free-text **detail note** (`ClipboardItem.detail`, optional).
- **Right-click** on any text/image row opens the editor. Detection is a
  `RightClickCatcher` (an `NSViewRepresentable` overlaid on the row whose `hitTest`
  only claims `.rightMouseDown` events, so left-clicks/buttons/hover pass through).
- The editor is `DetailEditorWindowController` — its own small window rather than a
  popover sheet, since taking focus would dismiss the popover. It hosts
  `DetailEditorView`: for a **text** item two `TextEditor`s (the captured text and
  the note), for an **image** item only the note. The window is `.resizable` and both
  areas grow with it, because the captured text can be long.
- Saving writes the note via `store.setDetail(id:detail:)` (whitespace-only clears it)
  and, for text items, the content (with protection and title) via `store.setText(id:text:isProtected:title:)` — stored
  verbatim, **rejected if blank** (Guardar is disabled too, so an edit can't leave a
  ghost row), and it touches neither `createdAt` nor the order.
- Rows show a `note.text` glyph (`DetailIndicator`) when the item has a detail,
  with the note text as tooltip.
- Opening the editor goes through the controller (`PopoverActions.editDetail`), like
  paste/Quick Look; the save is a plain data mutation straight to the store.
- **Protected items** (text only): the editor has a `Protegido` switch plus a
  `title`. When protected the list shows the title (italic, with a lock) instead of
  the captured text, and both revealing actions — pasting the item and opening the
  editor — go through `ProtectedAccess.reveal` (`deviceOwnerAuthentication`: Touch ID
  or the macOS user password) with a **15-minute in-memory grace window**. Inside the
  editor the captured text is a `SecureField`, toggled to a plain editor by the eye button.
- **El texto protegido va cifrado con su propia llave** (§3.2 del blueprint): en
  memoria y en `store.enc` un item protegido tiene `textContent = nil` y el texto en
  `sealedText`, cifrado con la `protectedKey` (par X25519: cifrar usa la pública y no
  pide nada; descifrar usa la privada, que solo se saca tras autenticar y vive en
  memoria lo que dura la ventana de gracia). `reveal` entrega al anfitrión una copia
  con el texto en claro; el editor guarda con `store.setText(id:text:isProtected:title:)`.
- **Qué impone macOS y qué la app**: la privada solo queda bajo `.userPresence`
  impuesto por el sistema si la build tiene el entitlement del llavero de protección de
  datos (perfil de aprovisionamiento). Firmada como hoy, sin perfil, cae al llavero de
  sesión y quien exige Touch ID es la app. Detalle en `docs/agent-context/arquitectura.md`.
- El buscador **no** mira el contenido de los protegidos (solo título y nota), y la
  deduplicación contra un protegido solo funciona con la ventana de gracia abierta.

## Contraseñas creadas a mano

- El pie «Nueva contraseña» de la pestaña Texto abre un modal (ventana propia) con
  título, contraseña, generador, detalle, grupo y `Protegida` (activada por defecto).
- Guarda con `ClipboardStore.addManual`: un item de texto normal, **favorito** (para
  esquivar el tope) y sin deduplicar. No hay tipo aparte. Si va protegida, nace ya
  cifrada; sin llave para cifrarla no se crea y el modal lo dice.

## Code Standards

- Swift 5.9+
- @MainActor for UI, async/await for persistence
- MVVM: ClipboardStore as single source of truth
- JSON atomically written with `.atomic` option
- UI is SwiftUI hosted in an `NSPopover`; the store is an `ObservableObject` the views
  observe, so no manual refresh — adding an item repaints the list automatically