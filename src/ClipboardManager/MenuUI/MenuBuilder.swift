//
//  MenuBuilder.swift
//  ClipboardManager
//
//  Builds the status-item menu: view selector (Text / Images), dynamic rows
//  per active view, and fixed items (Quit).
//

import AppKit

/// Actions the menu can trigger, injected by the controller.
struct MenuActions {
    let switchToText: () -> Void
    let switchToImages: () -> Void
    let select: (ClipboardItem) -> Void
    let toggleFavorite: (ClipboardItem.ID) -> Void
    let delete: (ClipboardItem.ID) -> Void
    let clearText: () -> Void
    let clearImages: () -> Void
    let about: () -> Void
    let quit: () -> Void
}

/// Constructs the NSMenu for the status item.
@MainActor
struct MenuBuilder {

    typealias TextRows = [ClipboardItem.ID: TextRowView]
    typealias ImageRows = [ClipboardItem.ID: ImageRowView]

    /// Populates the menu to reflect the current store state.
    /// - Returns: All dynamic row views keyed by item id, for in-place refresh.
    @discardableResult
    func populate(
        _ menu: NSMenu,
        items: [ClipboardItem],
        viewMode: ClipboardViewMode,
        actions: MenuActions
    ) -> (textRows: TextRows, imageRows: ImageRows) {
        menu.removeAllItems()
        menu.autoenablesItems = false

        // --- View selector (custom row: Text | Images) ---
        let selectorRow = ViewSelectorRow(selectedView: viewMode)
        selectorRow.onSelectText = actions.switchToText
        selectorRow.onSelectImages = actions.switchToImages
        selectorRow.onClearText = actions.clearText
        selectorRow.onClearImages = actions.clearImages
        selectorRow.onClearText = actions.clearText
        selectorRow.onClearImages = actions.clearImages
        let selectorItem = NSMenuItem()
        selectorItem.view = selectorRow
        menu.addItem(selectorItem)

        menu.addItem(.separator())

        // --- Dynamic rows for the active view ---
        var textRows: TextRows = [:]
        var imageRows: ImageRows = [:]

        switch viewMode {
        case .text:
            textRows = appendTextSection(to: menu, items: items, actions: actions)
        case .images:
            imageRows = appendImageSection(to: menu, items: items, actions: actions)
        }

        menu.addItem(.separator())
        menu.addItem(BlockMenuItem(title: "About Clipboard Manager", keyEquivalent: "", handler: actions.about))
        menu.addItem(BlockMenuItem(title: "Quit Clipboard Manager", keyEquivalent: "q", handler: actions.quit))

        return (textRows, imageRows)
    }

    // MARK: - Text section

    private func appendTextSection(
        to menu: NSMenu,
        items: [ClipboardItem],
        actions: MenuActions
    ) -> TextRows {
        let filtered = items.filter { $0.contentType == .text }
        guard !filtered.isEmpty else {
            let empty = NSMenuItem(title: items.isEmpty ? "No items yet" : "No text items",
                                   action: nil, keyEquivalent: "")
            empty.isEnabled = false
            menu.addItem(empty)
            return [:]
        }

        var rows: TextRows = [:]
        var didInsertFavoriteSeparator = false
        for item in filtered {
            // Items are pre-sorted favourites-first; drop a divider once, at the
            // boundary between the favourites group and the rest.
            if !item.isFavorite, !didInsertFavoriteSeparator,
               filtered.contains(where: { $0.isFavorite }) {
                menu.addItem(.separator())
                didInsertFavoriteSeparator = true
            }

            let rowView = TextRowView(item: item)
            rowView.onToggleFavorite = { actions.toggleFavorite(item.id) }
            rowView.onDelete = { actions.delete(item.id) }
            rowView.onSelect = { actions.select(item) }

            let menuItem = NSMenuItem()
            menuItem.view = rowView
            menu.addItem(menuItem)
            rows[item.id] = rowView
        }
        return rows
    }

    // MARK: - Image section

    private func appendImageSection(
        to menu: NSMenu,
        items: [ClipboardItem],
        actions: MenuActions
    ) -> ImageRows {
        let filtered = items.filter { $0.contentType == .image }
        guard !filtered.isEmpty else {
            let empty = NSMenuItem(title: items.isEmpty ? "No items yet" : "No image items",
                                   action: nil, keyEquivalent: "")
            empty.isEnabled = false
            menu.addItem(empty)
            return [:]
        }

        var rows: ImageRows = [:]
        var didInsertFavoriteSeparator = false
        for item in filtered {
            // Items are pre-sorted favourites-first; drop a divider once, at the
            // boundary between the favourites group and the rest.
            if !item.isFavorite, !didInsertFavoriteSeparator,
               filtered.contains(where: { $0.isFavorite }) {
                menu.addItem(.separator())
                didInsertFavoriteSeparator = true
            }

            let rowView = ImageRowView(item: item)
            rowView.onToggleFavorite = { actions.toggleFavorite(item.id) }
            rowView.onDelete = { actions.delete(item.id) }
            rowView.onSelect = { actions.select(item) }

            let menuItem = NSMenuItem()
            menuItem.view = rowView
            menu.addItem(menuItem)
            rows[item.id] = rowView
        }
        return rows
    }
}

/// An NSMenuItem that calls a block when selected.
final class BlockMenuItem: NSMenuItem {
    private let handler: () -> Void

    init(title: String, keyEquivalent: String = "", handler: @escaping () -> Void) {
        self.handler = handler
        super.init(title: title, action: #selector(performAction), keyEquivalent: keyEquivalent)
        self.target = self
    }

    @available(*, unavailable)
    required init(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    @objc private func performAction() {
        handler()
    }
}