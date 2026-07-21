//
//  StatusItemController.swift
//  ClipboardManager
//
//  Owns the NSStatusItem and a SwiftUI popover. We use a popover (not an NSMenu)
//  because custom rows inside a tracking NSMenu can't reliably receive clicks —
//  buttons, right-click and nested menus all fail there. In a popover, SwiftUI
//  handles all of that natively.
//
//  Paste flow: showing the popover activates our app (required so the popover's
//  controls respond to clicks), which steals focus from whatever app the user
//  was in. So we capture that app as the paste target BEFORE activating, and
//  reactivate + Cmd+V it when an item is chosen.
//

import AppKit
import SwiftUI

/// Callbacks the SwiftUI popover needs that live at the app/controller level.
/// All plain data mutations go straight to `ClipboardStore`; only these need
/// the controller (focus/paste, app windows).
struct PopoverActions {
    let selectItem: (ClipboardItem) -> Void
    let quickLook: (ClipboardItem) -> Void
    let editDetail: (ClipboardItem) -> Void
}

/// Manages the menu-bar status item and its popover.
@MainActor
final class StatusItemController: NSObject {

    private let statusItem: NSStatusItem
    private let store: ClipboardStore
    private let popover = NSPopover()
    private var eventMonitor: Any?

    /// Rolling history of the last few non-self app activations, newest last,
    /// used as a fallback when resolving the paste target.
    private var focusHistory: [NSRunningApplication] = []

    /// The app to paste into, captured when the popover opens (before we steal
    /// focus by activating ourselves).
    private var pasteTarget: NSRunningApplication?

    init(store: ClipboardStore) {
        self.store = store
        self.statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        super.init()

        configureButton()
        setupPopover()
        observeAppActivation()
    }

    // MARK: - Status button

    private func configureButton() {
        guard let button = statusItem.button else { return }
        let image = NSImage(systemSymbolName: "doc.on.clipboard", accessibilityDescription: "Clipboard Manager")
            ?? NSImage(systemSymbolName: "list.clipboard", accessibilityDescription: "Clipboard Manager")
        image?.isTemplate = true
        button.image = image
        button.imagePosition = .imageLeading
        button.target = self
        button.action = #selector(handleClick(_:))
        button.sendAction(on: [.leftMouseUp, .rightMouseUp])
    }

    private func setupPopover() {
        // `.applicationDefined`: in an LSUIElement app that isn't active, a
        // `.transient` popover can't become key and macOS closes it immediately.
        // We control closing ourselves (via the outside-click monitor).
        popover.behavior = .applicationDefined
        // No animation: the SwiftUI content drives live resizing via the grip,
        // and per-frame popover animation would make that drag feel laggy.
        popover.animates = false
        popover.contentSize = PopoverSize.saved()
        let root = PopoverRootView(store: store, actions: makeActions())
        let hosting = NSHostingController(rootView: root)
        // Track the SwiftUI content's size so dragging the resize grip (which
        // changes the content's .frame) actually resizes the popover.
        hosting.sizingOptions = [.preferredContentSize]
        popover.contentViewController = hosting
    }

    private func makeActions() -> PopoverActions {
        PopoverActions(
            selectItem: { [weak self] item in self?.selectItem(item) },
            quickLook: { [weak self] item in self?.quickLook(item) },
            editDetail: { [weak self] item in self?.editDetail(item) }
        )
    }

    // MARK: - Click handling

    @objc private func handleClick(_ sender: NSStatusBarButton) {
        let event = NSApp.currentEvent
        if event?.type == .rightMouseUp || (event?.modifierFlags.contains(.control) ?? false) {
            showStatusMenu(sender)
        } else {
            togglePopover(sender)
        }
    }

    private func togglePopover(_ sender: NSStatusBarButton) {
        if popover.isShown {
            closePopover()
        } else {
            showPopover(sender)
        }
    }

    private func showPopover(_ sender: NSStatusBarButton) {
        // Capture the paste target BEFORE activating ourselves.
        pasteTarget = resolvePasteTarget()
        // Record which display the icon was clicked on: it bounds how tall the
        // popover may be, and the content re-clamps to it as it appears.
        PopoverSize.activeScreen = sender.window?.screen
        NSApp.activate(ignoringOtherApps: true)
        popover.show(relativeTo: sender.bounds, of: sender, preferredEdge: .minY)
        popover.contentViewController?.view.window?.makeKey()
        registerOutsideClickMonitor()
    }

    private func closePopover() {
        popover.performClose(nil)
        unregisterOutsideClickMonitor()
    }

    private func registerOutsideClickMonitor() {
        unregisterOutsideClickMonitor()
        eventMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] _ in
            self?.closePopover()
        }
    }

    private func unregisterOutsideClickMonitor() {
        if let monitor = eventMonitor {
            NSEvent.removeMonitor(monitor)
            eventMonitor = nil
        }
    }

    // MARK: - Right-click menu (escape hatch: open / about / quit)

    private func showStatusMenu(_ sender: NSStatusBarButton) {
        if popover.isShown { closePopover() }

        let menu = NSMenu()
        menu.addItem(withTitle: "Abrir", action: #selector(openFromMenu), keyEquivalent: "").target = self
        menu.addItem(.separator())
        menu.addItem(withTitle: "About Clipboard Manager", action: #selector(aboutFromMenu), keyEquivalent: "").target = self
        menu.addItem(withTitle: "Quit Clipboard Manager", action: #selector(quitFromMenu), keyEquivalent: "q").target = self

        statusItem.menu = menu
        sender.performClick(nil)
        statusItem.menu = nil
    }

    @objc private func openFromMenu() {
        guard let button = statusItem.button else { return }
        // The menu is still closing; defer a run-loop pass before showing.
        DispatchQueue.main.async { [weak self] in
            guard let self, !self.popover.isShown else { return }
            self.showPopover(button)
        }
    }

    @objc private func aboutFromMenu() { AboutWindowController.show() }
    @objc private func quitFromMenu() { NSApp.terminate(nil) }

    // MARK: - Paste

    private func selectItem(_ item: ClipboardItem) {
        let target = pasteTarget
        closePopover()
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
    }

    /// Right-click on a row: require the macOS user's credentials, then open
    /// the detail editor. Authentication is cached briefly (see `Authenticator`),
    /// so editing several items in a row won't re-prompt each time. The
    /// completion runs on the main queue.
    private func editDetail(_ item: ClipboardItem) {
        Authenticator.shared.authenticate(
            reason: "Autentícate para editar el detalle de este elemento"
        ) { [weak self] granted in
            guard let self, granted else { return }
            DetailEditorWindowController.show(item: item, store: self.store)
        }
    }

    private func quickLook(_ item: ClipboardItem) {
        guard let url = item.imageFileURL else { return }
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/qlmanage")
        process.arguments = ["-p", url.path]
        do {
            try process.run()
        } catch {
            NSLog("ClipboardManager: failed to open Quick Look: \(error)")
        }
    }

    // MARK: - Focus tracking

    /// Continuously records the last non-self app to become active.
    private func observeAppActivation() {
        NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification,
            object: nil,
            queue: .main
        ) { [weak self] note in
            guard let self = self else { return }
            guard let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication else { return }
            guard app.processIdentifier != NSRunningApplication.current.processIdentifier else { return }
            self.focusHistory.append(app)
            if self.focusHistory.count > 8 {
                self.focusHistory.removeFirst(self.focusHistory.count - 8)
            }
        }
    }

    /// The app to paste into: the frontmost app right now (before we activate),
    /// falling back to the most recent app we saw activate.
    private func resolvePasteTarget() -> NSRunningApplication? {
        let selfPID = NSRunningApplication.current.processIdentifier
        if let front = NSWorkspace.shared.frontmostApplication, front.processIdentifier != selfPID {
            return front
        }
        return focusHistory.last(where: { !$0.isTerminated && $0.processIdentifier != selfPID })
    }
}
