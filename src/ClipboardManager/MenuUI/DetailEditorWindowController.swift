//
//  DetailEditorWindowController.swift
//  ClipboardManager
//
//  The "detail note" editor: a small modal-style window with a text area where
//  the user writes a free-text note for a clipboard item. Presented as its own
//  window (like About) rather than a sheet/popover-overlay because opening it
//  goes through system authentication, whose dialog steals focus and would
//  otherwise dismiss the transient-style popover mid-flow.
//

import AppKit
import SwiftUI

/// Manages the lifecycle of a detail-editor window. Each edit gets its own
/// window; the controllers are retained here and released when their window
/// closes.
@MainActor
final class DetailEditorWindowController: NSObject {

    /// Retains live controllers so their windows aren't deallocated.
    private static var open: [DetailEditorWindowController] = []

    private var window: NSWindow?

    /// Opens the editor for `item`, writing changes back through `store`.
    static func show(item: ClipboardItem, store: ClipboardStore) {
        let controller = DetailEditorWindowController()
        open.append(controller)
        controller.present(item: item, store: store)
    }

    private func present(item: ClipboardItem, store: ClipboardStore) {
        let root = DetailEditorView(
            itemID: item.id,
            heading: item.contentType == .image ? "Imagen" : item.textPreview,
            store: store,
            onClose: { [weak self] in self?.close() }
        )
        let hosting = NSHostingController(rootView: root)
        let win = NSWindow(contentViewController: hosting)
        win.title = "Detalle"
        win.styleMask = [.titled, .closable]
        win.isReleasedWhenClosed = false
        win.delegate = self
        win.center()

        self.window = win
        win.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    private func close() {
        window?.close()
    }
}

extension DetailEditorWindowController: NSWindowDelegate {
    func windowWillClose(_ notification: Notification) {
        window = nil
        DetailEditorWindowController.open.removeAll { $0 === self }
    }
}

// MARK: - Editor content

/// SwiftUI content of the detail editor: a heading identifying the item, a
/// multi-line text area, and Cancelar / Guardar. Saving trims the text and
/// persists it (empty clears the note).
struct DetailEditorView: View {
    let itemID: ClipboardItem.ID
    /// Short label identifying which item is being annotated.
    let heading: String
    @ObservedObject var store: ClipboardStore
    let onClose: () -> Void

    @State private var text: String

    init(itemID: ClipboardItem.ID, heading: String, store: ClipboardStore, onClose: @escaping () -> Void) {
        self.itemID = itemID
        self.heading = heading
        self._store = ObservedObject(wrappedValue: store)
        self.onClose = onClose
        // Seed the editor with any existing note for this item.
        let existing = store.items.first(where: { $0.id == itemID })?.detail ?? ""
        self._text = State(initialValue: existing)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Detalle")
                .font(.headline)

            Text(heading.isEmpty ? "Elemento" : heading)
                .font(.callout)
                .foregroundStyle(.secondary)
                .lineLimit(2)
                .truncationMode(.tail)

            TextEditor(text: $text)
                .font(.system(size: 13))
                .frame(minHeight: 160)
                .overlay(
                    RoundedRectangle(cornerRadius: 6)
                        .stroke(Color.secondary.opacity(0.3), lineWidth: 1)
                )

            HStack {
                Spacer()
                Button("Cancelar", role: .cancel) { onClose() }
                    .keyboardShortcut(.cancelAction)
                Button("Guardar") {
                    store.setDetail(id: itemID, detail: text)
                    onClose()
                }
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(16)
        .frame(width: 420)
    }
}

// MARK: - Right-click detection

/// Transparent overlay that reports secondary (right) clicks while letting all
/// other events fall through to the SwiftUI views underneath. Placed as an
/// `.overlay` on a row so a right-click anywhere on the row — even over its
/// buttons — opens the detail editor, without stealing left-clicks/hover.
struct RightClickCatcher: NSViewRepresentable {
    let action: () -> Void

    func makeNSView(context: Context) -> NSView {
        let view = CatcherView()
        view.action = action
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        (nsView as? CatcherView)?.action = action
    }

    private final class CatcherView: NSView {
        var action: (() -> Void)?

        override func rightMouseDown(with event: NSEvent) {
            action?()
        }

        /// Only claim the current event when it's a right mouse-down; return
        /// `nil` otherwise so left-clicks, buttons and hover reach the views
        /// behind this overlay.
        override func hitTest(_ point: NSPoint) -> NSView? {
            if NSApp.currentEvent?.type == .rightMouseDown {
                return self
            }
            return nil
        }
    }
}
