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
    /// the void. 0.05s was too short in practice.
    private static let pasteDelay: TimeInterval = 0.15

    /// Copies text to the pasteboard and pastes it at the cursor.
    static func copyAndPaste(text: String) {
        let pb = NSPasteboard.general
        pb.clearContents()
        pb.setString(text, forType: .string)

        DispatchQueue.main.asyncAfter(deadline: .now() + pasteDelay) {
            postCmdV()
        }
    }

    /// Copies an image to the pasteboard and pastes it at the cursor.
    static func copyAndPaste(image: NSImage) {
        let pb = NSPasteboard.general
        pb.clearContents()
        pb.writeObjects([image])

        DispatchQueue.main.asyncAfter(deadline: .now() + pasteDelay) {
            postCmdV()
        }
    }

    /// Posts a Cmd+V keystroke to the HID event stream.
    private static func postCmdV() {
        // Ground truth: is THIS running binary actually trusted for Accessibility?
        // If this logs `false`, the permission you granted is bound to a different
        // binary/signature than the one running — posting the keystroke will be
        // silently swallowed by the system no matter what.
        let trusted = AXIsProcessTrusted()
        ClipboardMonitor.debugLog("paste: AXIsProcessTrusted=\(trusted)")

        guard trusted else {
            // Trigger the system prompt so the user can grant it to *this* binary.
            let opts = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true]
            _ = AXIsProcessTrustedWithOptions(opts as CFDictionary)
            ClipboardMonitor.debugLog("paste: NOT trusted — prompted; aborting Cmd+V")
            return
        }

        guard let source = CGEventSource(stateID: .hidSystemState) else {
            ClipboardMonitor.debugLog("paste: CGEventSource nil — aborting")
            return
        }

        let keyDown = CGEvent(keyboardEventSource: source, virtualKey: 0x09, keyDown: true)
        keyDown?.flags = .maskCommand

        let keyUp = CGEvent(keyboardEventSource: source, virtualKey: 0x09, keyDown: false)
        keyUp?.flags = .maskCommand

        keyDown?.post(tap: .cghidEventTap)
        keyUp?.post(tap: .cghidEventTap)
        ClipboardMonitor.debugLog("paste: posted Cmd+V")
    }
}