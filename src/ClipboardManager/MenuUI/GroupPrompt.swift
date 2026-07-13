//
//  GroupPrompt.swift
//  ClipboardManager
//
//  Small modal helpers for group management (create / rename / confirm delete).
//  NSAlert is used deliberately: running a modal is reliable and needs far less
//  code than inline editing inside a tracking NSMenu. Callers must cancel menu
//  tracking before invoking these, so the menu isn't left open behind the alert.
//

import AppKit

@MainActor
enum GroupPrompt {

    /// Shows a modal text prompt. Returns the trimmed entry, or nil if cancelled
    /// or left blank.
    static func text(
        title: String,
        message: String,
        defaultValue: String = "",
        okTitle: String = "OK"
    ) -> String? {
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = message
        alert.addButton(withTitle: okTitle)
        alert.addButton(withTitle: "Cancelar")

        let field = NSTextField(frame: NSRect(x: 0, y: 0, width: 240, height: 24))
        field.stringValue = defaultValue
        alert.accessoryView = field
        alert.window.initialFirstResponder = field

        NSApp.activate(ignoringOtherApps: true)
        guard alert.runModal() == .alertFirstButtonReturn else { return nil }
        let trimmed = field.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    /// Shows a confirmation alert with a destructive primary button. Returns
    /// true if the user confirmed.
    static func confirm(
        title: String,
        message: String,
        destructiveTitle: String
    ) -> Bool {
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = message
        alert.addButton(withTitle: destructiveTitle)
        alert.addButton(withTitle: "Cancelar")
        NSApp.activate(ignoringOtherApps: true)
        return alert.runModal() == .alertFirstButtonReturn
    }
}
