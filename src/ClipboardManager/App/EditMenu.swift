//
//  EditMenu.swift
//  ClipboardManager
//
//  Minimal main menu for an agent app.
//

import AppKit

/// Instala un menú principal mínimo con el menú **Editar**.
///
/// La app es LSUIElement/`.accessory`: no muestra barra de menús, y sin menú
/// principal nadie interpreta los atajos estándar de edición. El resultado es
/// que dentro de cualquier campo de texto (el editor de un item, el renombrado
/// de un grupo) Cmd+C, Cmd+V, Cmd+X, Cmd+A o Cmd+Z no hacían nada: AppKit
/// resuelve esos atajos recorriendo `NSApp.mainMenu`, no el responder chain.
///
/// El menú no se ve en ningún sitio —seguimos sin barra de menús—, solo existe
/// para que los key equivalents lleguen al first responder.
enum EditMenu {

    static func install(on application: NSApplication) {
        let mainMenu = NSMenu()

        // Primer item: hueco del menú de aplicación. AppKit espera que exista,
        // aunque en una app accessory nunca se dibuje.
        let appMenuItem = NSMenuItem()
        appMenuItem.submenu = NSMenu()
        mainMenu.addItem(appMenuItem)

        let editMenuItem = NSMenuItem()
        let editMenu = NSMenu(title: "Edición")
        editMenu.addItem(withTitle: "Deshacer", action: Selector(("undo:")), keyEquivalent: "z")
        let redo = editMenu.addItem(withTitle: "Rehacer", action: Selector(("redo:")), keyEquivalent: "z")
        redo.keyEquivalentModifierMask = [.command, .shift]
        editMenu.addItem(.separator())
        editMenu.addItem(withTitle: "Cortar", action: #selector(NSText.cut(_:)), keyEquivalent: "x")
        editMenu.addItem(withTitle: "Copiar", action: #selector(NSText.copy(_:)), keyEquivalent: "c")
        editMenu.addItem(withTitle: "Pegar", action: #selector(NSText.paste(_:)), keyEquivalent: "v")
        editMenu.addItem(withTitle: "Seleccionar todo", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a")
        editMenuItem.submenu = editMenu
        mainMenu.addItem(editMenuItem)

        application.mainMenu = mainMenu
    }
}
