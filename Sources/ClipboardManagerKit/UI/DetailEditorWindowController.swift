//
//  DetailEditorWindowController.swift
//  ClipboardManager
//
//  The item editor: a small window with two text areas — the captured text
//  itself (text items only) and a free-text note. Presented as its own window
//  (like About) rather than a sheet/popover-overlay because taking focus would
//  dismiss the transient-style popover mid-edit.
//

import AppKit
import SwiftUI

/// Manages the lifecycle of a detail-editor window. Each edit gets its own
/// window; the controllers are retained here and released when their window
/// closes.
@MainActor
public final class DetailEditorWindowController: NSObject {

    /// Retains live controllers so their windows aren't deallocated.
    private static var open: [DetailEditorWindowController] = []

    private var window: NSWindow?

    /// Opens the editor for `item`, writing changes back through `store`.
    public static func show(item: ClipboardItem, store: ClipboardStore) {
        let controller = DetailEditorWindowController()
        open.append(controller)
        controller.present(item: item, store: store)
    }

    private func present(item: ClipboardItem, store: ClipboardStore) {
        let root = DetailEditorView(
            itemID: item.id,
            isText: item.contentType == .text,
            store: store,
            onClose: { [weak self] in self?.close() }
        )
        let hosting = NSHostingController(rootView: root)
        let win = NSWindow(contentViewController: hosting)
        win.title = item.contentType == .text ? "Editar elemento" : "Detalle"
        // Resizable: the captured text can be long, and the two areas grow with
        // the window.
        win.styleMask = [.titled, .closable, .resizable]
        win.isReleasedWhenClosed = false
        win.delegate = self
        win.setContentSize(NSSize(width: 460, height: item.contentType == .text ? 520 : 320))
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
    /// `public` because the class is public and `NSWindowDelegate` is a public
    /// protocol: a witness can't be less visible than the conformance.
    public func windowWillClose(_ notification: Notification) {
        window = nil
        DetailEditorWindowController.open.removeAll { $0 === self }
    }
}

// MARK: - Editor content

/// SwiftUI content of the editor: for a text item, the captured text itself and
/// the note, each in its own multi-line area; for an image item, only the note.
/// Saving persists both — the note trimmed (empty clears it), the text verbatim.
struct DetailEditorView: View {
    let itemID: ClipboardItem.ID
    /// Image items have no text to rewrite, so they only get the note area.
    let isText: Bool
    @ObservedObject var store: ClipboardStore
    let onClose: () -> Void

    @State private var content: String
    @State private var note: String

    init(itemID: ClipboardItem.ID, isText: Bool, store: ClipboardStore, onClose: @escaping () -> Void) {
        self.itemID = itemID
        self.isText = isText
        self._store = ObservedObject(wrappedValue: store)
        self.onClose = onClose
        // Seed both editors from the item as it stands now.
        let item = store.items.first(where: { $0.id == itemID })
        self._content = State(initialValue: item?.textContent ?? "")
        self._note = State(initialValue: item?.detail ?? "")
    }

    /// Blanking a text item would leave a ghost row, so Guardar is blocked
    /// instead (`setTextContent` rejects it too).
    private var canSave: Bool {
        !isText || !content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if isText {
                section("Texto copiado", text: $content, minHeight: 180)
            } else {
                Text("Imagen")
                    .font(.headline)
            }

            section("Detalle", text: $note, minHeight: 120)

            HStack {
                Spacer()
                Button("Cancelar", role: .cancel) { onClose() }
                    .keyboardShortcut(.cancelAction)
                Button("Guardar", action: save)
                    .keyboardShortcut(.defaultAction)
                    .disabled(!canSave)
            }
        }
        .padding(16)
        .frame(minWidth: 380, maxWidth: .infinity,
               minHeight: isText ? 400 : 240, maxHeight: .infinity)
    }

    private func section(_ title: String, text: Binding<String>, minHeight: CGFloat) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.headline)
            TextEditor(text: text)
                .font(.system(size: 13))
                .frame(minHeight: minHeight, maxHeight: .infinity)
                .overlay(
                    RoundedRectangle(cornerRadius: 6)
                        .stroke(Color.secondary.opacity(0.3), lineWidth: 1)
                )
        }
    }

    private func save() {
        guard canSave else { return }
        if isText { store.setTextContent(id: itemID, text: content) }
        store.setDetail(id: itemID, detail: note)
        onClose()
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
