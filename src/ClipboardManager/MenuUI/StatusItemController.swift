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

    /// Timestamped record of an app becoming active.
    private struct FocusEvent {
        let app: NSRunningApplication
        let at: Date
    }

    /// Rolling history of the last few non-self app activations, newest last.
    /// We need history (not a single value) because opening the menu on a
    /// SECOND display makes macOS activate that display's frontmost app (a
    /// "phantom" activation) a fraction of a second before the menu opens —
    /// which would otherwise overwrite the app that actually had key focus.
    private var focusHistory: [FocusEvent] = []

    /// The paste target chosen once when the menu opens, so later phantom
    /// activations can't change it mid-interaction.
    private var pasteTarget: NSRunningApplication?

    /// Activations newer than this (relative to menu-open time) are treated as
    /// the click-induced phantom and skipped. The real focus is always older.
    private static let phantomWindow: TimeInterval = 0.4

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
            self.focusHistory.append(FocusEvent(app: app, at: Date()))
            // Keep the history short — we only ever look back a couple of entries.
            if self.focusHistory.count > 8 {
                self.focusHistory.removeFirst(self.focusHistory.count - 8)
            }
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
        let rows = builder.populate(menu, store: store, actions: makeActions())
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
            switchToGroups: { [weak self] in
                guard let self = self else { return }
                self.store.viewMode = .groups
                self.rebuildMenu()
            },
            select: { [weak self] item in
                guard let self = self else { return }
                // Use the target fixed at menu-open time, not the live focus —
                // by now our own app is frontmost and any later activation is noise.
                let target = self.pasteTarget
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
            clearText: { [weak self] in
                self?.store.clearNonFavorites(ofType: .text)
                self?.rebuildMenuIfOpen()
            },
            clearImages: { [weak self] in
                self?.store.clearNonFavorites(ofType: .image)
                self?.rebuildMenuIfOpen()
            },
            assignGroup: { [weak self] itemID, groupID in
                self?.store.assignGroup(itemID: itemID, groupID: groupID)
                self?.rebuildMenuIfOpen()
            },
            newGroupAndAssign: { [weak self] itemID in
                guard let self = self else { return }
                // A modal prompt can't run over a tracking menu — close it first.
                self.menu.cancelTracking()
                guard let name = GroupPrompt.text(
                    title: "Nuevo grupo",
                    message: "Nombre del grupo:",
                    okTitle: "Crear"
                ), let groupID = self.store.addGroup(name: name) else { return }
                self.store.assignGroup(itemID: itemID, groupID: groupID)
            },
            toggleGroupFilter: { [weak self] id in
                self?.store.toggleGroupFilter(id: id)
                self?.rebuildMenuIfOpen()
            },
            renameGroup: { [weak self] id in
                guard let self = self else { return }
                let current = self.store.groups.first(where: { $0.id == id })?.name ?? ""
                self.menu.cancelTracking()
                guard let name = GroupPrompt.text(
                    title: "Renombrar grupo",
                    message: "Nuevo nombre:",
                    defaultValue: current,
                    okTitle: "Guardar"
                ) else { return }
                self.store.renameGroup(id: id, to: name)
            },
            deleteGroup: { [weak self] id in
                guard let self = self else { return }
                let name = self.store.groups.first(where: { $0.id == id })?.name ?? ""
                self.menu.cancelTracking()
                let ok = GroupPrompt.confirm(
                    title: "Eliminar grupo",
                    message: "Se eliminará el grupo «\(name)». Los textos e imágenes se conservan; solo dejan de estar agrupados.",
                    destructiveTitle: "Eliminar"
                )
                if ok { self.store.deleteGroup(id: id) }
            },
            newGroup: { [weak self] in
                guard let self = self else { return }
                self.menu.cancelTracking()
                guard let name = GroupPrompt.text(
                    title: "Nuevo grupo",
                    message: "Nombre del grupo:",
                    okTitle: "Crear"
                ) else { return }
                self.store.addGroup(name: name)
            },
            toggleUngroupedFilter: { [weak self] in
                self?.store.showUngroupedFavorites.toggle()
                self?.rebuildMenuIfOpen()
            },
            about: {
                AboutWindowController.show()
            },
            quit: { NSApp.terminate(nil) }
        )
    }

    private func rebuildMenu() {
        let rows = builder.populate(menu, store: store, actions: makeActions())
        textRows = rows.textRows
        imageRows = rows.imageRows
    }

    private func rebuildMenuIfOpen() {
        guard isMenuOpen else { return }
        rebuildMenu()
    }

    // MARK: - NSMenuDelegate

    func menuNeedsUpdate(_ menu: NSMenu) {
        let rows = builder.populate(menu, store: store, actions: makeActions())
        textRows = rows.textRows
        imageRows = rows.imageRows
    }

    func menuWillOpen(_ menu: NSMenu) {
        isMenuOpen = true
        pasteTarget = resolvePasteTarget()
    }

    /// Picks the app to paste into when the menu opens. Skips any activation that
    /// happened within `phantomWindow` of now, because clicking the status item
    /// on a second display activates that display's frontmost app just before
    /// the menu opens — that activation is not the user's real focus.
    private func resolvePasteTarget() -> NSRunningApplication? {
        let now = Date()
        // Walk newest→oldest; take the first activation that is NOT the phantom
        // (i.e. older than the phantom window) and whose app is still running.
        for event in focusHistory.reversed() {
            if now.timeIntervalSince(event.at) < Self.phantomWindow { continue }
            if event.app.isTerminated { continue }
            return event.app
        }
        // Everything was within the phantom window (or empty) — fall back to the
        // most recent still-running app we saw.
        return focusHistory.reversed().first(where: { !$0.app.isTerminated })?.app
    }

    func menuDidClose(_ menu: NSMenu) {
        isMenuOpen = false
        textRows = [:]
        imageRows = [:]
    }
}