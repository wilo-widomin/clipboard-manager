//
//  PasswordCreatorWindowController.swift
//  ClipboardManagerKit
//
//  Modal «Nueva contraseña»: crea a mano un item de texto que nunca pasó por el
//  portapapeles, con un generador de contraseñas. Es una ventana propia, como el
//  editor de items, porque tomar el foco dentro del popover lo cerraría.
//

import AppKit
import SwiftUI

/// Ciclo de vida de la ventana de creación. Se auto-retiene mientras está
/// abierta, igual que `DetailEditorWindowController`.
@MainActor
public final class PasswordCreatorWindowController: NSObject {

    private static var open: [PasswordCreatorWindowController] = []

    private var window: NSWindow?

    /// Abre el modal; al guardar escribe el item nuevo en `store`.
    public static func show(store: ClipboardStore) {
        let controller = PasswordCreatorWindowController()
        open.append(controller)
        controller.present(store: store)
    }

    private func present(store: ClipboardStore) {
        let root = PasswordCreatorView(store: store, onClose: { [weak self] in self?.close() })
        let hosting = NSHostingController(rootView: root)
        let win = NSWindow(contentViewController: hosting)
        win.title = "Nueva contraseña"
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

extension PasswordCreatorWindowController: NSWindowDelegate {
    public func windowWillClose(_ notification: Notification) {
        window = nil
        PasswordCreatorWindowController.open.removeAll { $0 === self }
    }
}

// MARK: - Contenido

struct PasswordCreatorView: View {
    @ObservedObject var store: ClipboardStore
    let onClose: () -> Void

    @State private var title = ""
    @State private var password = ""
    @State private var note = ""
    @State private var groupID: ClipboardGroup.ID? = nil
    @State private var isProtected = true
    /// Empieza tapada: quien pase por detrás no debe verla. El ojo la destapa.
    @State private var isRevealed = false

    // Opciones del generador.
    @State private var length: Double = 16
    @State private var useUppercase = true
    @State private var useLowercase = true
    @State private var useDigits = true
    @State private var useSymbols = true
    @State private var extraSymbols = ""

    private var generator: PasswordGenerator {
        PasswordGenerator(
            length: Int(length),
            useUppercase: useUppercase,
            useLowercase: useLowercase,
            useDigits: useDigits,
            useSymbols: useSymbols,
            extraSymbols: extraSymbols
        )
    }

    /// Contraseña no vacía y, si va protegida, con título: lo mismo que exige
    /// el almacén, para que Guardar no se quede sin efecto en silencio.
    private var canSave: Bool {
        if password.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { return false }
        if isProtected && title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { return false }
        return true
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            labeled("Título") {
                TextField("Lo que se verá en la lista, p. ej. «Wifi oficina»", text: $title)
                    .textFieldStyle(.roundedBorder)
            }

            passwordSection
            generatorSection

            labeled("Detalle (opcional)") {
                TextEditor(text: $note)
                    .font(.system(size: 13))
                    .frame(height: 60)
                    .overlay(
                        RoundedRectangle(cornerRadius: 6)
                            .stroke(Color.secondary.opacity(0.3), lineWidth: 1)
                    )
            }

            Picker("Grupo", selection: $groupID) {
                Text("Sin grupo").tag(ClipboardGroup.ID?.none)
                ForEach(store.groups) { group in
                    Text(group.name).tag(ClipboardGroup.ID?.some(group.id))
                }
            }

            Toggle("Protegida", isOn: $isProtected)
                .toggleStyle(.switch)
                .help("Oculta el texto en la lista y pide autenticación para copiarlo o abrirlo")

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
        .frame(width: 440)
    }

    // MARK: - Secciones

    private var passwordSection: some View {
        labeled("Contraseña") {
            HStack(spacing: 8) {
                Group {
                    if isRevealed {
                        TextField("", text: $password)
                    } else {
                        SecureField("", text: $password)
                    }
                }
                .textFieldStyle(.roundedBorder)
                .font(.system(size: 13, design: .monospaced))

                Button {
                    isRevealed.toggle()
                } label: {
                    Image(systemName: isRevealed ? "eye.slash" : "eye")
                }
                .buttonStyle(.borderless)
                .help(isRevealed ? "Ocultar la contraseña" : "Mostrar la contraseña")
            }
        }
    }

    private var generatorSection: some View {
        GroupBox("Generador") {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text("Largo: \(Int(length))")
                        .monospacedDigit()
                        .frame(width: 80, alignment: .leading)
                    Slider(
                        value: $length,
                        in: Double(PasswordGenerator.lengthRange.lowerBound)...Double(PasswordGenerator.lengthRange.upperBound),
                        step: 1
                    )
                }

                HStack(spacing: 14) {
                    Toggle("Mayúsculas", isOn: $useUppercase)
                    Toggle("Minúsculas", isOn: $useLowercase)
                    Toggle("Números", isOn: $useDigits)
                    Toggle("Símbolos", isOn: $useSymbols)
                }
                .toggleStyle(.checkbox)

                TextField("Símbolos extra, p. ej. ¿¡€", text: $extraSymbols)
                    .textFieldStyle(.roundedBorder)
                    .help("Se suman a los símbolos normales. Con «Símbolos» apagado, se usan solo estos.")

                HStack {
                    Button("Generar", action: generate)
                        .disabled(!generator.canGenerate)
                    if !generator.canGenerate {
                        Text("Activa al menos un tipo de carácter")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .padding(6)
        }
    }

    private func labeled<Content: View>(_ label: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label).font(.headline)
            content()
        }
    }

    // MARK: - Acciones

    private func generate() {
        guard let generated = generator.generate() else { return }
        password = generated
    }

    private func save() {
        guard canSave else { return }
        store.addManual(
            title: title,
            text: password,
            detail: note,
            groupID: groupID,
            isProtected: isProtected
        )
        onClose()
    }
}
