# Clipboard Manager

macOS menubar app for clipboard history — text & images, favorites, groups, 100 items.

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

```
src/ClipboardManager/
├── App/
│   ├── AppDelegate.swift     — @main entry, LSUIElement, tick timer
│   ├── AppInfo.swift         — name, version, author credit (widomin.com)
│   └── Info.plist
├── Models/
│   ├── ClipboardItem.swift    — item model (text/image, favorite, date, groupID)
│   ├── ClipboardGroup.swift   — group model (id, name, isFilterEnabled)
│   └── ClipboardStore.swift   — ObservableObject, max 100 items, fav sorting, groups
├── Monitor/
│   └── ClipboardMonitor.swift — polls changeCount, reads text or TIFF/PNG
├── Persistence/
│   └── JSONPersistenceService.swift  — async JSON read/write (store.json + groups.json)
├── MenuUI/
│   ├── StatusItemController.swift    — NSStatusItem + NSPopover lifecycle, focus/paste
│   ├── PopoverRootView.swift         — SwiftUI popover: Texto/Imágenes/Grupos + rows
│   ├── PasteboardHelper.swift        — copy + reactivate target + Cmd+V
│   ├── AboutView.swift / AboutWindowController.swift
└── Resources/
    └── (icons will go here)
```

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

- **ClipboardItem**: id, contentType(.text/.image), createdAt, textContent, imageFilename(PNG on disk), isFavorite, groupID(optional). `groupID` is optional so older `store.json` files decode cleanly.
- **ClipboardGroup**: id, name, isFilterEnabled. Persisted separately in `groups.json`.
- **ClipboardStore**: `@Published items` + `@Published groups`. Favourites first (by date desc), then rest (by date desc). Max 100. `visibleItems` filtered by `viewMode` **and** the per-group checkbox filter (applies to **all** items — see Groups).

## Groups

- A favourite can belong to at most one group. Assigning a group auto-favourites the item (so it survives the per-type cap); un-favouriting removes it from its group.
- Assign/reassign via the 📁 `Menu` on each text/image row — it lists the groups,
  "Sin grupo", and "Nuevo grupo…". (Right-click on rows was dropped: the 📁 button covers it.)
- The **Grupos** view manages groups: **inline rename** (edit the name field, Enter to
  commit), delete (trash), and create via **"Nuevo grupo"** (a SwiftUI `.alert` with a
  text field — the same alert backs "Nuevo grupo…" from the assignment menu, which then
  auto-assigns the new group to the item). Deleting a group keeps the items and only
  clears their `groupID`.
- Each group's checkbox (and the fixed "Sin grupo" row, backed by `store.showUngrouped`)
  filters which items appear in the Text/Images lists. This applies to **all** items:
  unchecking a group hides its items, and unchecking "Sin grupo" hides every ungrouped
  item (which includes all non-favourites, since only favourites can hold a group).

## Code Standards

- Swift 5.9+
- @MainActor for UI, async/await for persistence
- MVVM: ClipboardStore as single source of truth
- JSON atomically written with `.atomic` option
- UI is SwiftUI hosted in an `NSPopover`; the store is an `ObservableObject` the views
  observe, so no manual refresh — adding an item repaints the list automatically