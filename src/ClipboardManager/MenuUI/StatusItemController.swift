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

    /// The last app that held focus before ours. We track every app-activation
    /// system-wide and remember the most recent one that isn't us, because
    /// `NSWorkspace.frontmostApplication` sampled at menu-open time is wrong on
    /// multi-display setups (it can report a window on the screen where the menu
    /// was clicked instead of the app that actually had key focus). We must
    /// reactivate this app before Cmd+V or the paste lands in the wrong place.
    private var previousApp: NSRunningApplication?

    init(store: ClipboardStore) {
        self.store = store
        self.statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        super.init()

        configureButton()
        menu.delegate = self
        statusItem.menu = menu
        observeAppActivation()
    }

    /// Continuously records the last non-self app to become active, so we always
    /// know the true previous focus regardless of displays or menu timing.
    private func observeAppActivation() {
        NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification,
            object: nil,
            queue: .main
        ) { [weak self] note in
            guard let self = self else { return }
            guard let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication else { return }
            // Ignore our own activations (e.g. when the menu-bar item is clicked).
            guard app.processIdentifier != NSRunningApplication.current.processIdentifier else { return }
            self.previousApp = app
        }
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
        // `previousApp` is kept up to date continuously by observeAppActivation();
        // sampling frontmostApplication here was unreliable on multi-display setups.
    }

    func menuDidClose(_ menu: NSMenu) {
        isMenuOpen = false
        textRows = [:]
        imageRows = [:]
    }
}