# Clipboard Manager

macOS menubar app for clipboard history — text & images, favorites, 100 items.

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
│   ├── ClipboardItem.swift    — item model (text/image, favorite, date)
│   └── ClipboardStore.swift   — ObservableObject, max 100 items, fav sorting
├── Monitor/
│   └── ClipboardMonitor.swift — polls changeCount, reads text or TIFF/PNG
├── Persistence/
│   └── JSONPersistenceService.swift  — async JSON read/write
├── MenuUI/
│   ├── StatusItemController.swift    — NSStatusItem + menu lifecycle
│   ├── MenuBuilder.swift             — builds dynamic NSMenu per view mode
│   ├── TextRowView.swift             — [30-char preview] [⭐] [🗑]
│   └── ImageRowView.swift            — [80×80 thumbnail] [⭐] [🗑] [qlmanage]
└── Resources/
    └── (icons will go here)
```

## Models

- **ClipboardItem**: id, contentType(.text/.image), createdAt, textContent, imageData(PNG), isFavorite
- **ClipboardStore**: `@Published items` — favourites first (by date desc), then rest (by date desc). Max 100. `visibleItems` filtered by `viewMode`.

## Code Standards

- Swift 5.9+
- @MainActor for UI, async/await for persistence
- MVVM: ClipboardStore as single source of truth
- JSON atomically written with `.atomic` option
- NSView subclasses with `mouseDown` forwarding for buttons inside NSMenuItem