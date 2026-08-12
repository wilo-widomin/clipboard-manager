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
- **JSON persistence** via Codable in `~/Library/Application Support/ClipboardManager/store.json`
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
│   └── JSONPersistenceService.swift  — async JSON read/write (store.json + groups.json)
└── UI/
    ├── PopoverRootView.swift         — SwiftUI popover: Texto/Imágenes/Grupos + rows
    ├── PopoverActions.swift          — the seam: what each host injects
    ├── PasteboardHelper.swift        — copy + reactivate target + Cmd+V
    └── DetailEditorWindowController.swift — item editor window + RightClickCatcher

src/ClipboardManager/          — STANDALONE APP ONLY
├── App/
│   ├── AppDelegate.swift     — @main entry, LSUIElement, tick timer
│   ├── AppInfo.swift         — name, version, author credit (widomin.com)
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
`ClipboardTextRow` / `ClipboardImageRow` (each with a 📁 `Menu` for group assignment,
⭐ favourite, 🗑 delete, and 👁 Quick Look on images), and `GroupsManageView` /
`GroupManageRow` (checkbox filter + inline rename + delete). It also owns the resize
handles (`PopoverSize` persists the size) and the pointing-hand / resize cursors
(`.onContinuousHover` + `NSCursor`; the diagonal corner cursor uses a guarded private
AppKit selector via `Cursors`). Plain data mutations call `ClipboardStore` directly;
only paste and Quick Look go through `PopoverActions` on the controller (About/Quit
live in the status-item right-click menu).

## Models

- **ClipboardItem**: id, contentType(.text/.image), createdAt, textContent, imageFilename(PNG on disk), isFavorite, groupID(optional), detail(optional). `groupID` and `detail` are optional so older `store.json` files decode cleanly.
- **ClipboardGroup**: id, name, isFilterEnabled. Persisted separately in `groups.json`.
- **ClipboardStore**: `@Published items` + `@Published groups`. Favourites first (by date desc), then rest (by date desc), with a divider drawn at the boundary. Capped **per content type** — 50 text, 20 images — never globally, and the cap counts **only non-favourites**: favourites are unlimited and don't consume the budget, `cap` evicts the oldest non-favourite of that type (dropping an image deletes its PNG). `visibleItems` filtered by `viewMode` **and** the per-group checkbox filter (applies to **all** items — see Groups).

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
  and, for text items, the content via `store.setTextContent(id:text:)` — stored
  verbatim, **rejected if blank** (Guardar is disabled too, so an edit can't leave a
  ghost row), and it touches neither `createdAt` nor the order.
- Rows show a `note.text` glyph (`DetailIndicator`) when the item has a detail,
  with the note text as tooltip.
- Opening the editor goes through the controller (`PopoverActions.editDetail`), like
  paste/Quick Look; the save is a plain data mutation straight to the store.
- There is **no authentication gate**: it was dropped (an earlier version used
  `LocalAuthentication`) because the note is stored in clear text in `store.json`
  anyway, so the prompt bought no real protection — only friction. Don't reintroduce
  it without also encrypting the note.

## Code Standards

- Swift 5.9+
- @MainActor for UI, async/await for persistence
- MVVM: ClipboardStore as single source of truth
- JSON atomically written with `.atomic` option
- UI is SwiftUI hosted in an `NSPopover`; the store is an `ObservableObject` the views
  observe, so no manual refresh — adding an item repaints the list automatically