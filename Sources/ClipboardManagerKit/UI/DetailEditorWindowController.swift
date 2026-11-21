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

    /// Editores abiertos, por id de item: retiene los controladores (para que
    /// sus ventanas no se liberen) y evita abrir dos editores del mismo item.
    private static var open: [ClipboardItem.ID: DetailEditorWindowController] = [:]

    private var window: NSWindow?
    private var itemID: ClipboardItem.ID?

    /// Opens the editor for `item`, writing changes back through `store`.
    ///
    /// Un item protegido tiene que llegar **ya revelado** (de
    /// `ProtectedAccess.reveal`): el editor siembra el texto desde `item`, no
    /// desde el almacén, donde va cifrado.
    public static func show(item: ClipboardItem, store: ClipboardStore) {
        // Si ese item ya tiene editor, no se abre otro: se trae al frente el
        // que hay (aunque esté tapado, minimizado o como pestaña de otro).
        if let existing = open[item.id], existing.window != nil {
            existing.bringToFront()
            return
        }
        let controller = DetailEditorWindowController()
        open[item.id] = controller
        controller.present(item: item, store: store)
    }

    /// Una app `LSUIElement` no está activa al abrirse la ventana: sin activar
    /// la app, `makeKeyAndOrderFront` la deja detrás de las demás.
    private func bringToFront() {
        guard let win = window else { return }
        if win.isMiniaturized { win.deminiaturize(nil) }
        NSApp.activate(ignoringOtherApps: true)
        // Si el tabbing automático la agrupó, esto selecciona su pestaña.
        win.tabGroup?.selectedWindow = win
        win.makeKeyAndOrderFront(nil)
        win.orderFrontRegardless()
    }

    private func present(item: ClipboardItem, store: ClipboardStore) {
        let root = DetailEditorView(
            item: item,
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
        // Cada item tiene su ventana: nada de agruparlas como pestañas.
        win.tabbingMode = .disallowed
        win.setContentSize(NSSize(width: 460, height: item.contentType == .text ? 520 : 320))
        win.center()

        self.window = win
        self.itemID = item.id
        bringToFront()
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
        if let id = itemID, DetailEditorWindowController.open[id] === self {
            DetailEditorWindowController.open[id] = nil
        }
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
    @State private var title: String
    @State private var isProtected: Bool
    /// Un item protegido enseña su texto como contraseña; el ojo lo destapa
    /// mientras dura la edición (para llegar aquí ya se ha autenticado).
    @State private var isRevealed = false
    /// Por qué no se pudo guardar (p. ej. sin llave para cifrar el texto
    /// protegido). La ventana sigue abierta para no perder lo escrito.
    @State private var saveError: String?

    /// `item` llega ya revelado si está protegido: su `textContent` es el texto
    /// en claro, que en el almacén va cifrado.
    init(item: ClipboardItem, store: ClipboardStore, onClose: @escaping () -> Void) {
        self.itemID = item.id
        self.isText = item.contentType == .text
        self._store = ObservedObject(wrappedValue: store)
        self.onClose = onClose
        // Seed the editors: the text from the (revealed) item, the rest from
        // the store as it stands now.
        let current = store.items.first(where: { $0.id == item.id }) ?? item
        self._content = State(initialValue: item.textContent ?? "")
        self._note = State(initialValue: current.detail ?? "")
        self._title = State(initialValue: current.title ?? "")
        self._isProtected = State(initialValue: current.isProtected)
    }

    /// Blanking a text item would leave a ghost row, so Guardar is blocked
    /// instead (`setTextContent` rejects it too). Y un item protegido sin
    /// título dejaría la fila sin nada que enseñar, así que el título pasa a
    /// ser obligatorio en cuanto se activa el interruptor.
    private var canSave: Bool {
        if isText && content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { return false }
        if isProtected && title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { return false }
        return true
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if isText {
                protectionControls
                if isProtected {
                    protectedContentSection
                } else {
                    section("Texto copiado", text: $content, minHeight: 180)
                }
            } else {
                Text("Imagen")
                    .font(.headline)
            }

            section("Detalle", text: $note, minHeight: 120)

            if let saveError = saveError {
                Text(saveError)
                    .font(.callout)
                    .foregroundColor(.red)
                    .fixedSize(horizontal: false, vertical: true)
            }

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

    /// Interruptor de protección y título. El título es lo que la lista enseña
    /// en lugar del texto capturado, así que solo tiene sentido con el
    /// interruptor puesto — pero se conserva al apagarlo.
    @ViewBuilder
    private var protectionControls: some View {
        Toggle("Protegido", isOn: $isProtected)
            .toggleStyle(.switch)
            .help("Oculta el texto en la lista y pide autenticación para copiarlo o abrirlo")
        if isProtected {
            VStack(alignment: .leading, spacing: 4) {
                Text("Título")
                    .font(.headline)
                TextField("Lo que se verá en la lista", text: $title)
                    .textFieldStyle(.roundedBorder)
            }
        }
    }

    /// El texto capturado de un item protegido: oculto como contraseña, y
    /// destapado con el ojo. Empieza siempre tapado aunque ya estemos
    /// autenticados —abrir la ventana no debería enseñarlo a quien pase por
    /// detrás—, y el ojo lo alterna en los dos sentidos.
    @ViewBuilder
    private var protectedContentSection: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text("Texto copiado")
                    .font(.headline)
                Spacer()
                Button {
                    isRevealed.toggle()
                } label: {
                    Image(systemName: isRevealed ? "eye.slash" : "eye")
                }
                .buttonStyle(.borderless)
                .help(isRevealed ? "Ocultar el texto" : "Mostrar el texto")
            }
            if isRevealed {
                TextEditor(text: $content)
                    .font(.system(size: 13))
                    .frame(minHeight: 180, maxHeight: .infinity)
                    .overlay(
                        RoundedRectangle(cornerRadius: 6)
                            .stroke(Color.secondary.opacity(0.3), lineWidth: 1)
                    )
            } else {
                // `SecureField` es de una línea: mientras está tapado no se
                // edita cómodamente, y para eso está el ojo.
                SecureField("", text: $content)
                    .textFieldStyle(.roundedBorder)
                    .font(.system(size: 13))
            }
        }
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
        if isText {
            // Texto, protección y título de una vez: con el texto en claro en
            // la mano, proteger o desproteger no necesita la llave privada.
            guard store.setText(id: itemID, text: content, isProtected: isProtected, title: title) else {
                saveError = "No se ha podido guardar: no hay llave para cifrar el texto protegido "
                    + "(o el elemento ya no existe). No se ha cambiado nada."
                return
            }
        }
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
