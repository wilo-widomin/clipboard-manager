# Clipboard Manager

macOS menubar app for clipboard history — text & images, favorites, groups, 100 items.

## Architecture

- **AppKit** (NSStatusItem, NSMenu) for the menubar
- **SwiftUI** not used (all views are custom AppKit NSViews for menu compatibility)
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
│   ├── StatusItemController.swift    — NSStatusItem + menu lifecycle
│   ├── MenuBuilder.swift             — builds dynamic NSMenu per view mode
│   ├── ViewSelectorRow.swift         — Text | Images | Grupos switcher
│   ├── TextRowView.swift             — [30-char preview] [⭐] [🗑], right-click → assign group
│   ├── ImageRowView.swift            — [80×80 thumbnail] [⭐] [🗑] [qlmanage], right-click → assign group
│   ├── GroupRowView.swift            — [✓ filter] [name] [✎] [🗑] + "Sin grupo" checkbox row
│   ├── GroupContextMenu.swift        — native right-click menu to assign/reassign group
│   └── GroupPrompt.swift             — modal alerts for create/rename/delete group
└── Resources/
    └── (icons will go here)
```

## Models

- **ClipboardItem**: id, contentType(.text/.image), createdAt, textContent, imageFilename(PNG on disk), isFavorite, groupID(optional). `groupID` is optional so older `store.json` files decode cleanly.
- **ClipboardGroup**: id, name, isFilterEnabled. Persisted separately in `groups.json`.
- **ClipboardStore**: `@Published items` + `@Published groups`. Favourites first (by date desc), then rest (by date desc). Max 100. `visibleItems` filtered by `viewMode` **and** the per-group checkbox filter (only affects favourites).

## Groups

- A favourite can belong to at most one group. Assigning a group auto-favourites the item (so it survives the per-type cap); un-favouriting removes it from its group.
- Assign/reassign via right-click on a text/image row (native `GroupContextMenu`).
- The **Grupos** view manages groups (create/rename/delete). Deleting a group keeps the items and only clears their `groupID`.
- Each group's checkbox (and the fixed "Sin grupo" row, backed by the `showUngroupedFavorites` UserDefaults flag) filters which favourites appear in the Text/Images lists.

## Code Standards

- Swift 5.9+
- @MainActor for UI, async/await for persistence
- MVVM: ClipboardStore as single source of truth
- JSON atomically written with `.atomic` option
- NSView subclasses with `mouseDown` forwarding for buttons inside NSMenuItem