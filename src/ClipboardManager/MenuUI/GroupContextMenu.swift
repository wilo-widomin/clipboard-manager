//
//  GroupContextMenu.swift
//  ClipboardManager
//
//  Builds the native right-click menu shown over a text/image row for assigning
//  the item to a group. The current group is marked with a checkmark. Choosing
//  a group assigns (and auto-favourites) the item; "Sin grupo" removes it from
//  any group; "+ Nuevo grupo…" creates one and assigns it.
//

import AppKit

@MainActor
enum GroupContextMenu {

    static func make(
        groups: [ClipboardGroup],
        currentGroupID: UUID?,
        onAssign: @escaping (UUID?) -> Void,
        onNew: @escaping () -> Void
    ) -> NSMenu {
        let menu = NSMenu()
        menu.autoenablesItems = false

        let header = NSMenuItem(title: "Asignar a grupo", action: nil, keyEquivalent: "")
        header.isEnabled = false
        menu.addItem(header)
        menu.addItem(.separator())

        for group in groups {
            let item = BlockMenuItem(title: group.name) { onAssign(group.id) }
            item.state = (group.id == currentGroupID) ? .on : .off
            menu.addItem(item)
        }
        if !groups.isEmpty {
            menu.addItem(.separator())
        }

        let none = BlockMenuItem(title: "Sin grupo") { onAssign(nil) }
        none.state = (currentGroupID == nil) ? .on : .off
        menu.addItem(none)

        menu.addItem(.separator())
        menu.addItem(BlockMenuItem(title: "+ Nuevo grupo…", handler: onNew))

        return menu
    }
}
