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

    /// The app that was frontmost when the menu opened. We must reactivate it
    /// before posting Cmd+V, otherwise the paste lands nowhere — closing the
    /// menu alone does NOT reliably return key focus to it.
    private var previousApp: NSRunningApplication?

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
                let target = self.previousApp
                ClipboardMonitor.debugLog("select: clicked item type=\(item.contentType) — paste starting (target=\(target?.localizedName ?? "nil"))")
                // Dismiss the menu via its known instance so key focus returns
                // to the previously active app before Cmd+V is posted.
                self.menu.cancelTracking()
                switch item.contentType {
                case .text:
                    if let text = item.textContent {
                        PasteboardHelper.copyAndPaste(text: text, reactivating: target)
                    }
                case .image:
                    if let image = item.loadImage() {
                        PasteboardHelper.copyAndPaste(image: image, reactivating: target)
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
            about: {
                AboutWindowController.show()
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
        // Remember who had focus so we can hand it back before pasting.
        previousApp = NSWorkspace.shared.frontmostApplication
    }

    func menuDidClose(_ menu: NSMenu) {
        isMenuOpen = false
        textRows = [:]
        imageRows = [:]
    }
}