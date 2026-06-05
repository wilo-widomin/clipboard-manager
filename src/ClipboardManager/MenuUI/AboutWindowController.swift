//
//  AboutWindowController.swift
//  ClipboardManager
//
//  Presents the About window as a lightweight, centered, self-contained panel.
//

import AppKit
import SwiftUI

/// Manages the lifecycle of the About window.
@MainActor
final class AboutWindowController: NSObject {

    private static var shared: AboutWindowController?
    private var window: NSWindow?

    /// Shows the About window, bringing it to the front if already open.
    static func show() {
        let controller = shared ?? {
            let c = AboutWindowController()
            shared = c
            return c
        }()
        controller.showWindow()
    }

    private func showWindow() {
        if let existing = window, existing.isVisible {
            existing.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }

        let hosting = NSHostingController(rootView: AboutView())
        let win = NSWindow(contentViewController: hosting)
        win.title = "About \(AppInfo.name)"
        win.styleMask = [.titled, .closable, .miniaturizable]
        win.isReleasedWhenClosed = false
        win.delegate = self

        // Center on screen.
        win.center()

        self.window = win
        win.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }
}

extension AboutWindowController: NSWindowDelegate {
    func windowWillClose(_ notification: Notification) {
        window = nil
    }
}