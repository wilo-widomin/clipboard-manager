//
//  StatusItemController.swift
//  ClipboardManager
//
//  Owns the NSStatusItem and its menu. Rebuilds the menu on open, refreshes
//  visible rows each tick, and routes commands to the store.
//

import AppKit

/// Manages the menu-bar status item and its menu lifecycle.
@MainActor
final class StatusItemController: NSObject, NSMenuDelegate {

    private let statusItem: NSStatusItem
    private let menu = NSMenu()
    private let store: ClipboardStore
    private let builder = MenuBuilder()

    private var textRows: MenuBuilder.TextRows = [:]
    private var imageRows: MenuBuilder.ImageRows = [:]
    private var isMenuOpen = false

    init(store: ClipboardStore) {
        self.store = store
        self.statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        super.init()

        configureButton()
        menu.delegate = self
        statusItem.menu = menu
    }

    // MARK: - Status button

    private func configureButton() {
        guard let button = statusItem.button else { return }
        // "doc.on.clipboard" está disponible desde macOS 11+
        let image = NSImage(systemSymbolName: "doc.on.clipboard", accessibilityDescription: "Clipboard Manager")
            ?? NSImage(systemSymbolName: "list.clipboard", accessibilityDescription: "Clipboard Manager")
        image?.isTemplate = true
        button.image = image
        button.imagePosition = .imageLeading
    }

    // MARK: - Tick (called 1 Hz)

    /// Called once per second while the menu is open. Rebuilds the menu
    /// to reflect new items, favourites toggles, or deletions.
    func tick() {
        guard isMenuOpen else { return }
        let rows = builder.populate(menu, items: store.items, viewMode: store.viewMode, actions: makeActions())
        textRows = rows.textRows
        imageRows = rows.imageRows
    }

    // MARK: - Menu actions

    private func makeActions() -> MenuActions {
        MenuActions(
            switchToText: { [weak self] in
                guard let self = self else { return }
                self.store.viewMode = .text
                self.rebuildMenu()
            },
            switchToImages: { [weak self] in
                guard let self = self else { return }
                self.store.viewMode = .images
                self.rebuildMenu()
            },
            select: { [weak self] item in
                guard let self = self else { return }
                switch item.contentType {
                case .text:
                    if let text = item.textContent {
                        PasteboardHelper.copyAndPaste(text: text)
                    }
                case .image:
                    if let image = item.loadImage() {
                        PasteboardHelper.copyAndPaste(image: image)
                    }
                }
            },
            toggleFavorite: { [weak self] id in
                self?.store.toggleFavorite(id: id)
                self?.rebuildMenuIfOpen()
            },
            delete: { [weak self] id in
                self?.store.remove(id: id)
                self?.rebuildMenuIfOpen()
            },
            quit: { NSApp.terminate(nil) }
        )
    }

    private func rebuildMenu() {
        let rows = builder.populate(menu, items: store.items, viewMode: store.viewMode, actions: makeActions())
        textRows = rows.textRows
        imageRows = rows.imageRows
    }

    private func rebuildMenuIfOpen() {
        guard isMenuOpen else { return }
        rebuildMenu()
    }

    // MARK: - NSMenuDelegate

    func menuNeedsUpdate(_ menu: NSMenu) {
        let rows = builder.populate(menu, items: store.items, viewMode: store.viewMode, actions: makeActions())
        textRows = rows.textRows
        imageRows = rows.imageRows
    }

    func menuWillOpen(_ menu: NSMenu) {
        isMenuOpen = true
    }

    func menuDidClose(_ menu: NSMenu) {
        isMenuOpen = false
        textRows = [:]
        imageRows = [:]
    }
}