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

    private lazy var store: ClipboardStore = {
        let persistence = JSONPersistenceService()
        return ClipboardStore(persistence: persistence)
    }()

    private lazy var monitor: ClipboardMonitor = {
        ClipboardMonitor(store: store)
    }()

    private lazy var statusItemController: StatusItemController = {
        StatusItemController(store: store)
    }()

    private var tickTimer: Timer?

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Load persisted state synchronously (blocking briefly).
        Task {
            await store.load()
        }

        // Install the status item.
        _ = statusItemController

        // Start the 1 Hz tick for clipboard monitoring and menu refresh.
        tickTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.monitor.tick()
                self?.statusItemController.tick()
            }
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        tickTimer?.invalidate()
    }
}