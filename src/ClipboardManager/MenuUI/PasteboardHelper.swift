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
enum PasteboardHelper {

    /// Delay before posting Cmd+V. The menu must fully close and key focus must
    /// return to the previously active app first, otherwise the paste lands in
    /// the void. 0.15s was still too short once the menu closes — reactivating
    /// the target app needs a beat to take effect.
    private static let pasteDelay: TimeInterval = 0.25

    /// Copies text to the pasteboard and pastes it into `target` (the app that
    /// had focus before the menu opened).
    static func copyAndPaste(text: String, reactivating target: NSRunningApplication?) {
        let pb = NSPasteboard.general
        pb.clearContents()
        pb.setString(text, forType: .string)
        pasteAfterReactivating(target)
    }

    /// Copies an image to the pasteboard and pastes it into `target`.
    static func copyAndPaste(image: NSImage, reactivating target: NSRunningApplication?) {
        let pb = NSPasteboard.general
        pb.clearContents()
        pb.writeObjects([image])
        pasteAfterReactivating(target)
    }

    /// Reactivates the previously-focused app, waits for focus to settle, then
    /// posts Cmd+V. Without the explicit reactivation, closing the menu leaves
    /// key focus on our own (menu-bar) app and the paste goes nowhere.
    private static func pasteAfterReactivating(_ target: NSRunningApplication?) {
        target?.activate(options: [])
        DispatchQueue.main.asyncAfter(deadline: .now() + pasteDelay) {
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