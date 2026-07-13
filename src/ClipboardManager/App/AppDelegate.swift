//
//  AppDelegate.swift
//  ClipboardManager
//
//  Application entry point. LSUIElement = YES so the app runs as an agent
//  (no Dock icon, no menu bar). Loads persisted state, starts the clipboard
//  monitor, and installs the status item.
//

import AppKit

@main
@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {

    /// Programmatic entry point. We drive the `NSApplication` lifecycle ourselves
    /// (rather than relying on `NSApplicationMain` / a storyboard) because this is
    /// a menu-bar agent with no Dock icon and no main window. `application.run()`
    /// starts the AppKit run loop that keeps the process alive and delivers
    /// `applicationDidFinishLaunching` — without it the process exits immediately
    /// and the status item is never installed.
    static func main() {
        let application = NSApplication.shared
        let delegate = AppDelegate()
        application.delegate = delegate

        // Reinforce LSUIElement=YES at runtime: run as an accessory (menu-bar)
        // app with no Dock presence and no application menu in the menu bar.
        application.setActivationPolicy(.accessory)

        application.run()
    }

    private var store: ClipboardStore?
    private var monitor: ClipboardMonitor?
    private var statusItemController: StatusItemController?
    private var tickTimer: Timer?

    func applicationDidFinishLaunching(_ notification: Notification) {
        let persistence = JSONPersistenceService()
        let store = ClipboardStore(persistence: persistence)
        self.store = store

        // Load persisted state.
        Task {
            await store.load()
        }

        // Install the status item.
        let controller = StatusItemController(store: store)
        self.statusItemController = controller
        self.monitor = ClipboardMonitor(store: store)

        // Start the 1 Hz tick for clipboard monitoring. The popover UI is SwiftUI
        // bound to the store's @Published state, so it refreshes automatically
        // when the monitor adds items — no manual menu rebuild needed.
        tickTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.monitor?.tick()
            }
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        tickTimer?.invalidate()
    }

    /// Opt in to secure state restoration (silences the macOS 14+ warning).
    func applicationSupportsSecureRestorableState(_ app: NSApplication) -> Bool {
        true
    }
}