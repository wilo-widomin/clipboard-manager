//
//  MenuBuilder.swift
//  ClipboardManager
//
//  Builds the status-item menu: view selector (Text / Images / Grupos), dynamic
//  rows per active view, and fixed items (Quit).
//

import AppKit

/// Actions the menu can trigger, injected by the controller.
struct MenuActions {
    let switchToText: () -> Void
    let switchToImages: () -> Void
    let switchToGroups: () -> Void
    let select: (ClipboardItem) -> Void
    let toggleFavorite: (ClipboardItem.ID) -> Void
    let delete: (ClipboardItem.ID) -> Void
    let clearText: () -> Void
    let clearImages: () -> Void
    /// Assign an item to a group (nil removes it from any group).
    let assignGroup: (ClipboardItem.ID, UUID?) -> Void
    /// Create a group (prompting for its name) and assign the item to it.
    let newGroupAndAssign: (ClipboardItem.ID) -> Void
    /// Toggle a group's filter checkbox.
    let toggleGroupFilter: (ClipboardGroup.ID) -> Void
    let renameGroup: (ClipboardGroup.ID) -> Void
    let deleteGroup: (ClipboardGroup.ID) -> Void
    /// Create a new group (prompting for its name).
    let newGroup: () -> Void
    /// Toggle the "Sin grupo" filter checkbox.
    let toggleUngroupedFilter: () -> Void
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
        store: ClipboardStore,
        actions: MenuActions
    ) -> (textRows: TextRows, imageRows: ImageRows) {
        menu.removeAllItems()
        menu.autoenablesItems = false

        let items = store.items
        let groups = store.groups
        let viewMode = store.viewMode

        // --- View selector (custom row: Text | Images | Grupos) ---
        let selectorRow = ViewSelectorRow(selectedView: viewMode)
        selectorRow.onSelectText = actions.switchToText
        selectorRow.onSelectImages = actions.switchToImages
        selectorRow.onSelectGroups = actions.switchToGroups
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
            textRows = appendTextSection(to: menu, store: store, groups: groups, actions: actions)
        case .images:
            imageRows = appendImageSection(to: menu, store: store, groups: groups, actions: actions)
        case .groups:
            appendGroupsSection(to: menu, store: store, actions: actions)
        }

        menu.addItem(.separator())
        menu.addItem(BlockMenuItem(title: "About Clipboard Manager", keyEquivalent: "", handler: actions.about))
        menu.addItem(BlockMenuItem(title: "Quit Clipboard Manager", keyEquivalent: "q", handler: actions.quit))

        return (textRows, imageRows)
    }

    // MARK: - Text section

    private func appendTextSection(
        to menu: NSMenu,
        store: ClipboardStore,
        groups: [ClipboardGroup],
        actions: MenuActions
    ) -> TextRows {
        let filtered = store.items.filter { $0.contentType == .text && store.passesGroupFilter($0) }
        guard !filtered.isEmpty else {
            let allText = store.items.contains { $0.contentType == .text }
            let empty = NSMenuItem(title: allText ? "No text items (filtrados)" : "No text items",
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
            rowView.groups = groups
            rowView.onToggleFavorite = { actions.toggleFavorite(item.id) }
            rowView.onDelete = { actions.delete(item.id) }
            rowView.onSelect = { actions.select(item) }
            rowView.onAssignGroup = { gid in actions.assignGroup(item.id, gid) }
            rowView.onNewGroupAndAssign = { actions.newGroupAndAssign(item.id) }

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
        store: ClipboardStore,
        groups: [ClipboardGroup],
        actions: MenuActions
    ) -> ImageRows {
        let filtered = store.items.filter { $0.contentType == .image && store.passesGroupFilter($0) }
        guard !filtered.isEmpty else {
            let allImages = store.items.contains { $0.contentType == .image }
            let empty = NSMenuItem(title: allImages ? "No image items (filtrados)" : "No image items",
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
            rowView.groups = groups
            rowView.onToggleFavorite = { actions.toggleFavorite(item.id) }
            rowView.onDelete = { actions.delete(item.id) }
            rowView.onSelect = { actions.select(item) }
            rowView.onAssignGroup = { gid in actions.assignGroup(item.id, gid) }
            rowView.onNewGroupAndAssign = { actions.newGroupAndAssign(item.id) }

            let menuItem = NSMenuItem()
            menuItem.view = rowView
            menu.addItem(menuItem)
            rows[item.id] = rowView
        }
        return rows
    }

    // MARK: - Groups section

    private func appendGroupsSection(
        to menu: NSMenu,
        store: ClipboardStore,
        actions: MenuActions
    ) {
        // One row per group with a filter checkbox + rename/delete.
        for group in store.groups {
            let row = GroupRowView(group: group)
            row.onToggleFilter = { actions.toggleGroupFilter(group.id) }
            row.onRename = { actions.renameGroup(group.id) }
            row.onDelete = { actions.deleteGroup(group.id) }
            let menuItem = NSMenuItem()
            menuItem.view = row
            menu.addItem(menuItem)
        }

        // Fixed "Sin grupo" filter row for ungrouped favourites.
        let ungrouped = SimpleCheckboxRow(title: "Sin grupo", isOn: store.showUngroupedFavorites)
        ungrouped.onToggle = { actions.toggleUngroupedFilter() }
        let ungroupedItem = NSMenuItem()
        ungroupedItem.view = ungrouped
        menu.addItem(ungroupedItem)

        menu.addItem(.separator())
        menu.addItem(BlockMenuItem(title: "+ Nuevo grupo…", handler: actions.newGroup))
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
