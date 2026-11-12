//  PasteboardHelper.swift
//  ClipboardManager
//
//  Copies content to the system pasteboard and posts Cmd+V to paste it
//  at the current cursor position.
//

import AppKit
import CoreGraphics

/// Copies content to the general pasteboard, then simulates Cmd+V to paste
/// it into the currently focused input.
@MainActor
public enum PasteboardHelper {

    /// Grace period after the target is confirmed frontmost, before posting ⌘V:
    /// being frontmost and having a key window ready to take keystrokes are not
    /// the same instant.
    private static let settleDelay: TimeInterval = 0.15

    /// How often to check whether the target has come to the front.
    private static let pollInterval: TimeInterval = 0.05

    /// How long to wait for that before giving up and pasting anyway. Generous,
    /// because activating an app that lives on another Space plays the
    /// desktop-switch animation, which runs far longer than any fixed delay
    /// worth paying in the common case.
    private static let maxWait: TimeInterval = 2.0

    /// Copies text to the pasteboard and pastes it into `target` (the app that
    /// had focus before the menu opened).
    public static func copyAndPaste(text: String, reactivating target: NSRunningApplication?) {
        let pb = NSPasteboard.general
        pb.clearContents()
        pb.setString(text, forType: .string)
        pasteAfterReactivating(target)
    }

    /// Copies an image to the pasteboard and pastes it into `target`.
    public static func copyAndPaste(image: NSImage, reactivating target: NSRunningApplication?) {
        let pb = NSPasteboard.general
        pb.clearContents()
        pb.writeObjects([image])
        pasteAfterReactivating(target)
    }

    /// Reactivates the previously-focused app, waits until it really is in
    /// front, then posts ⌘V. Without the explicit reactivation, closing the
    /// popover leaves key focus on our own (menu-bar) app and the paste goes
    /// nowhere.
    ///
    /// The wait is a poll rather than a fixed delay because how long it takes
    /// varies by two orders of magnitude: reactivating an app on the current
    /// desktop is nearly instant, while one on another Space has to play the
    /// switch animation first. A delay long enough for the second case would
    /// make the first feel broken, and the delay this code used to have (0.25s)
    /// was short enough that pasting across Spaces missed entirely.
    private static func pasteAfterReactivating(_ target: NSRunningApplication?) {
        guard let target else {
            // No target resolved: the content is on the pasteboard either way,
            // so paste into whatever has focus and let the user sort it out.
            pasteAfterSettling()
            return
        }
        target.activate(options: [.activateAllWindows])
        waitUntilFrontmost(target, giveUpAt: Date().addingTimeInterval(maxWait))
    }

    /// Polls until `target` is the frontmost app, then pastes. Pastes anyway
    /// once the deadline passes: a paste into the wrong place is no worse than
    /// the silent no-op we would otherwise leave behind.
    private static func waitUntilFrontmost(_ target: NSRunningApplication, giveUpAt deadline: Date) {
        let isFrontmost = NSWorkspace.shared.frontmostApplication?.processIdentifier
            == target.processIdentifier

        guard !isFrontmost, Date() < deadline else {
            pasteAfterSettling()
            return
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + pollInterval) {
            waitUntilFrontmost(target, giveUpAt: deadline)
        }
    }

    private static func pasteAfterSettling() {
        DispatchQueue.main.asyncAfter(deadline: .now() + settleDelay) {
            postCmdV()
        }
    }

    /// Posts a Cmd+V keystroke to the HID event stream.
    private static func postCmdV() {
        // The paste keystroke is silently swallowed unless this binary is trusted
        // for Accessibility. If it isn't, prompt the user to grant it and bail.
        guard AXIsProcessTrusted() else {
            let opts = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true]
            _ = AXIsProcessTrustedWithOptions(opts as CFDictionary)
            return
        }

        guard let source = CGEventSource(stateID: .hidSystemState) else { return }

        let keyDown = CGEvent(keyboardEventSource: source, virtualKey: 0x09, keyDown: true)
        keyDown?.flags = .maskCommand

        let keyUp = CGEvent(keyboardEventSource: source, virtualKey: 0x09, keyDown: false)
        keyUp?.flags = .maskCommand

        keyDown?.post(tap: .cghidEventTap)
        keyUp?.post(tap: .cghidEventTap)
    }
}