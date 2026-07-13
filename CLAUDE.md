# Clipboard Manager

macOS menubar app for clipboard history — text & images, favorites, groups, 100 items.

## Architecture

- **AppKit** `NSStatusItem` hosting a **SwiftUI popover** (`NSPopover` + `NSHostingController`).
  We moved off `NSMenu`: custom rows inside a tracking `NSMenu` can't reliably receive
  clicks/buttons/right-click/nested menus. In a popover, SwiftUI handles all of that.
- **Popover behaviour** = `.applicationDefined` (a `.transient` popover can't become key
  in an inactive LSUIElement app and closes instantly); closed via a global outside-click
  monitor. Showing it activates the app, so the paste target is captured *before* that.
- **JSON persistence** via Codable in `~/Library/Application Support/ClipboardManager/store.json`
- **1 Hz polling** of `NSPasteboard.changeCount` for clipboard monitoring
- **macOS 13+** minimum target
- **LSUIElement = YES** (agent app, no Dock)

## Project structure

```
src/ClipboardManager/
├── App/
│   ├── AppDelegate.swift     — @main entry, LSUIElement, tick timer
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

`PopoverRootView` holds the SwiftUI views: `ClipboardTextRow`, `ClipboardImageRow`
(each with a 📁 `Menu` and a right-click `.contextMenu` for group assignment), and
`GroupsManageView` / `GroupManageRow` (checkbox filter + inline rename + delete).
Plain data mutations call `ClipboardStore` directly; only paste/about/quit go through
`PopoverActions` on the controller.

## Models

- **ClipboardItem**: id, contentType(.text/.image), createdAt, textContent, imageFilename(PNG on disk), isFavorite, groupID(optional). `groupID` is optional so older `store.json` files decode cleanly.
- **ClipboardGroup**: id, name, isFilterEnabled. Persisted separately in `groups.json`.
- **ClipboardStore**: `@Published items` + `@Published groups`. Favourites first (by date desc), then rest (by date desc). Max 100. `visibleItems` filtered by `viewMode` **and** the per-group checkbox filter (only affects favourites).

## Groups

- A favourite can belong to at most one group. Assigning a group auto-favourites the item (so it survives the per-type cap); un-favouriting removes it from its group.
- Assign/reassign via the 📁 `Menu` on each text/image row, or by right-clicking the row
  (`.contextMenu`) — both list the groups, "Sin grupo", and "Nuevo grupo…". Both work
  natively now that the UI is a SwiftUI popover (they did not inside the old `NSMenu`).
- The **Grupos** view manages groups (create/rename/delete). Deleting a group keeps the items and only clears their `groupID`.
- Each group's checkbox (and the fixed "Sin grupo" row, backed by the `showUngroupedFavorites` UserDefaults flag) filters which favourites appear in the Text/Images lists.

## Code Standards

- Swift 5.9+
- @MainActor for UI, async/await for persistence
- MVVM: ClipboardStore as single source of truth
- JSON atomically written with `.atomic` option
- UI is SwiftUI hosted in an `NSPopover`; the store is an `ObservableObject` the views
  observe, so no manual refresh — adding an item repaints the list automatically