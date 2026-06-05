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

    /// Copies text to the pasteboard and pastes it at the cursor.
    static func copyAndPaste(text: String) {
        let pb = NSPasteboard.general
        pb.clearContents()
        pb.setString(text, forType: .string)

        // Give the menu time to close before posting the keystroke.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
            postCmdV()
        }
    }

    /// Copies an image to the pasteboard and pastes it at the cursor.
    static func copyAndPaste(image: NSImage) {
        let pb = NSPasteboard.general
        pb.clearContents()
        pb.writeObjects([image])

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
            postCmdV()
        }
    }

    /// Posts a Cmd+V keystroke to the HID event stream.
    private static func postCmdV() {
        guard let source = CGEventSource(stateID: .hidSystemState) else { return }

        let keyDown = CGEvent(keyboardEventSource: source, virtualKey: 0x09, keyDown: true)
        keyDown?.flags = .maskCommand

        let keyUp = CGEvent(keyboardEventSource: source, virtualKey: 0x09, keyDown: false)
        keyUp?.flags = .maskCommand

        keyDown?.post(tap: .cghidEventTap)
        keyUp?.post(tap: .cghidEventTap)
    }
}