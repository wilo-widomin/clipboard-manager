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
final class AppDelegate: NSObject, NSApplicationDelegate {

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

        // Start the 1 Hz tick for clipboard monitoring and menu refresh.
        tickTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.monitor?.tick()
                self?.statusItemController?.tick()
            }
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        tickTimer?.invalidate()
    }
}