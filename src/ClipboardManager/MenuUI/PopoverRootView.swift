//
//  PopoverRootView.swift
//  ClipboardManager
//
//  SwiftUI content of the menu-bar popover. Three views (Texto / Imágenes /
//  Grupos) driven by ClipboardStore. Group assignment uses a native SwiftUI
//  Menu (the 📁 button), which works reliably here unlike inside an NSMenu.
//  A resize grip in the bottom-right corner lets the user drag the popover
//  larger/smaller; the size is persisted.
//

import SwiftUI
import AppKit
import ObjectiveC

enum Cursors {
    /// The diagonal (NW–SE) window-resize cursor. There's no public diagonal
    /// resize cursor before macOS 15, so we use AppKit's private class method,
    /// guarded by a runtime check, and fall back to the vertical resize cursor.
    static var resizeNWSE: NSCursor {
        let sel = NSSelectorFromString("_windowResizeNorthWestSouthEastCursor")
        if class_getClassMethod(NSCursor.self, sel) != nil,
           let cursor = (NSCursor.self as AnyObject).perform(sel)?.takeUnretainedValue() as? NSCursor {
            return cursor
        }
        return .resizeUpDown
    }
}

/// Persisted, clamped popover size. Shared by the SwiftUI content (which drives
/// the live size while dragging the resize grip) and the controller (initial size).
enum PopoverSize {
    static let minWidth: CGFloat = 300
    static let minHeight: CGFloat = 260
    static let maxWidth: CGFloat = 760
    static let maxHeight: CGFloat = 1000
    static let defaultSize = CGSize(width: 340, height: 460)

    static func saved() -> CGSize {
        let d = UserDefaults.standard
        guard d.object(forKey: "popoverWidth") != nil else { return defaultSize }
        let w = clampWidth(CGFloat(d.double(forKey: "popoverWidth")))
        let h = clampHeight(CGFloat(d.double(forKey: "popoverHeight")))
        return CGSize(width: w, height: h)
    }

    static func save(_ size: CGSize) {
        UserDefaults.standard.set(Double(size.width), forKey: "popoverWidth")
        UserDefaults.standard.set(Double(size.height), forKey: "popoverHeight")
    }

    static func clampWidth(_ v: CGFloat) -> CGFloat { min(max(v, minWidth), maxWidth) }
    static func clampHeight(_ v: CGFloat) -> CGFloat { min(max(v, minHeight), maxHeight) }
}

struct PopoverRootView: View {

    @ObservedObject var store: ClipboardStore
    let actions: PopoverActions

    // New-group prompt state. `assignTo` carries the item to auto-assign the
    // freshly created group to (nil for a standalone create from the Grupos tab).
    @State private var showNewGroupAlert = false
    @State private var newGroupName = ""
    @State private var newGroupAssignTo: ClipboardItem.ID? = nil

    // Live popover size; dragging the resize grip updates it (and persists it).
    @State private var size = PopoverSize.saved()
    @State private var sizeAtDragStart: CGSize?

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            content
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .frame(width: size.width, height: size.height)
        .overlay(alignment: .bottomTrailing) { resizeGrip }
        .alert("Nuevo grupo", isPresented: $showNewGroupAlert) {
            TextField("Nombre", text: $newGroupName)
            Button("Cancelar", role: .cancel) { newGroupName = "" }
            Button("Crear") { createGroup() }
        }
    }

    // MARK: - Resize grip

    private var resizeGrip: some View {
        Image(systemName: "arrow.up.left.and.arrow.down.right")
            .font(.system(size: 9, weight: .bold))
            .foregroundStyle(.secondary)
            .padding(5)
            .contentShape(Rectangle())
            .help("Arrastra para redimensionar")
            .onContinuousHover { phase in
                switch phase {
                case .active: Cursors.resizeNWSE.set()
                case .ended: NSCursor.arrow.set()
                }
            }
            .gesture(
                DragGesture(minimumDistance: 1)
                    .onChanged { value in
                        let base = sizeAtDragStart ?? size
                        if sizeAtDragStart == nil { sizeAtDragStart = size }
                        size = CGSize(
                            width: PopoverSize.clampWidth(base.width + value.translation.width),
                            height: PopoverSize.clampHeight(base.height + value.translation.height)
                        )
                    }
                    .onEnded { _ in
                        sizeAtDragStart = nil
                        PopoverSize.save(size)
                    }
            )
    }

    // MARK: - Header

    private var header: some View {
        HStack(spacing: 8) {
            Picker("", selection: $store.viewMode) {
                Text("Texto").tag(ClipboardViewMode.text)
                Text("Imágenes").tag(ClipboardViewMode.images)
                Text("Grupos").tag(ClipboardViewMode.groups)
            }
            .pickerStyle(.segmented)
            .labelsHidden()

            if store.viewMode == .text {
                trashButton("Borrar textos no favoritos") {
                    store.clearNonFavorites(ofType: .text)
                }
            } else if store.viewMode == .images {
                trashButton("Borrar imágenes no favoritas") {
                    store.clearNonFavorites(ofType: .image)
                }
            }
        }
        .padding(10)
    }

    private func trashButton(_ help: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: "trash")
        }
        .buttonStyle(.borderless)
        .foregroundStyle(.secondary)
        .help(help)
    }

    // MARK: - Content

    @ViewBuilder
    private var content: some View {
        switch store.viewMode {
        case .text:   textList
        case .images: imageList
        case .groups: GroupsManageView(store: store, onNewGroup: startStandaloneNewGroup)
        }
    }

    private var textList: some View {
        let items = store.items.filter { $0.contentType == .text && store.passesGroupFilter($0) }
        return ScrollView {
            LazyVStack(spacing: 2) {
                if items.isEmpty {
                    emptyLabel(store.items.contains { $0.contentType == .text } ? "Sin textos visibles (filtrados)" : "Sin textos")
                }
                ForEach(items) { item in
                    ClipboardTextRow(
                        item: item,
                        groups: store.groups,
                        onSelect: { actions.selectItem(item) },
                        onToggleFavorite: { store.toggleFavorite(id: item.id) },
                        onDelete: { store.remove(id: item.id) },
                        onAssign: { store.assignGroup(itemID: item.id, groupID: $0) },
                        onNewGroup: { startNewGroup(assignTo: item.id) }
                    )
                }
            }
            .padding(6)
        }
    }

    private var imageList: some View {
        let items = store.items.filter { $0.contentType == .image && store.passesGroupFilter($0) }
        return ScrollView {
            LazyVStack(spacing: 2) {
                if items.isEmpty {
                    emptyLabel(store.items.contains { $0.contentType == .image } ? "Sin imágenes visibles (filtradas)" : "Sin imágenes")
                }
                ForEach(items) { item in
                    ClipboardImageRow(
                        item: item,
                        groups: store.groups,
                        onSelect: { actions.selectItem(item) },
                        onQuickLook: { actions.quickLook(item) },
                        onToggleFavorite: { store.toggleFavorite(id: item.id) },
                        onDelete: { store.remove(id: item.id) },
                        onAssign: { store.assignGroup(itemID: item.id, groupID: $0) },
                        onNewGroup: { startNewGroup(assignTo: item.id) }
                    )
                }
            }
            .padding(6)
        }
    }

    private func emptyLabel(_ text: String) -> some View {
        Text(text)
            .foregroundStyle(.secondary)
            .font(.callout)
            .frame(maxWidth: .infinity)
            .padding(.top, 24)
    }

    // MARK: - New group helpers

    private func startStandaloneNewGroup() {
        newGroupAssignTo = nil
        newGroupName = ""
        showNewGroupAlert = true
    }

    private func startNewGroup(assignTo itemID: ClipboardItem.ID) {
        newGroupAssignTo = itemID
        newGroupName = ""
        showNewGroupAlert = true
    }

    private func createGroup() {
        let name = newGroupName
        newGroupName = ""
        guard let id = store.addGroup(name: name) else { return }
        if let itemID = newGroupAssignTo {
            store.assignGroup(itemID: itemID, groupID: id)
        }
        newGroupAssignTo = nil
    }
}

// MARK: - Group assignment menu (shared by text & image rows)

/// The list of buttons shown by the 📁 menu and the right-click context menu.
struct GroupAssignmentMenu: View {
    let currentGroupID: UUID?
    let groups: [ClipboardGroup]
    let onAssign: (UUID?) -> Void
    let onNewGroup: () -> Void

    var body: some View {
        ForEach(groups) { group in
            Button {
                onAssign(group.id)
            } label: {
                if group.id == currentGroupID {
                    Label(group.name, systemImage: "checkmark")
                } else {
                    Text(group.name)
                }
            }
        }
        if !groups.isEmpty { Divider() }
        Button("Sin grupo") { onAssign(nil) }
        Divider()
        Button("Nuevo grupo…") { onNewGroup() }
    }
}

// MARK: - Text row

struct ClipboardTextRow: View {
    let item: ClipboardItem
    let groups: [ClipboardGroup]
    let onSelect: () -> Void
    let onToggleFavorite: () -> Void
    let onDelete: () -> Void
    let onAssign: (UUID?) -> Void
    let onNewGroup: () -> Void

    @State private var hover = false

    var body: some View {
        HStack(spacing: 8) {
            Text(item.textPreview)
                .font(.system(size: 13))
                .lineLimit(1)
                .truncationMode(.tail)
            Spacer(minLength: 4)
            groupMenu
            favoriteButton
            Button(action: onDelete) { Image(systemName: "trash") }
                .buttonStyle(.borderless)
                .foregroundStyle(.secondary)
                .help("Eliminar")
        }
        .padding(.vertical, 5)
        .padding(.horizontal, 8)
        .contentShape(Rectangle())
        .onTapGesture(perform: onSelect)
        .onContinuousHover { phase in
            switch phase {
            case .active: hover = true; NSCursor.pointingHand.set()
            case .ended: hover = false; NSCursor.arrow.set()
            }
        }
        .background(RoundedRectangle(cornerRadius: 5).fill(hover ? Color.accentColor.opacity(0.15) : .clear))
    }

    private var groupMenu: some View {
        Menu {
            GroupAssignmentMenu(currentGroupID: item.groupID, groups: groups, onAssign: onAssign, onNewGroup: onNewGroup)
        } label: {
            Image(systemName: item.groupID != nil ? "folder.fill" : "folder")
                .foregroundStyle(item.groupID != nil ? Color.accentColor : Color.secondary)
        }
        .buttonStyle(.borderless)
        .menuIndicator(.hidden)
        .fixedSize()
        .help("Asignar a grupo")
    }

    private var favoriteButton: some View {
        Button(action: onToggleFavorite) {
            Image(systemName: item.isFavorite ? "star.fill" : "star")
                .foregroundStyle(item.isFavorite ? Color.yellow : Color.secondary)
        }
        .buttonStyle(.borderless)
        .help("Favorito")
    }
}

// MARK: - Image row

struct ClipboardImageRow: View {
    let item: ClipboardItem
    let groups: [ClipboardGroup]
    let onSelect: () -> Void
    let onQuickLook: () -> Void
    let onToggleFavorite: () -> Void
    let onDelete: () -> Void
    let onAssign: (UUID?) -> Void
    let onNewGroup: () -> Void

    @State private var hover = false

    var body: some View {
        HStack(spacing: 10) {
            thumbnail
            Spacer(minLength: 4)
            groupMenu
            favoriteButton
            Button(action: onQuickLook) { Image(systemName: "eye") }
                .buttonStyle(.borderless)
                .foregroundStyle(.secondary)
                .help("Vista rápida")
            Button(action: onDelete) { Image(systemName: "trash") }
                .buttonStyle(.borderless)
                .foregroundStyle(.secondary)
                .help("Eliminar")
        }
        .padding(.vertical, 6)
        .padding(.horizontal, 8)
        .contentShape(Rectangle())
        .onTapGesture(perform: onSelect)
        .onContinuousHover { phase in
            switch phase {
            case .active: hover = true; NSCursor.pointingHand.set()
            case .ended: hover = false; NSCursor.arrow.set()
            }
        }
        .background(RoundedRectangle(cornerRadius: 5).fill(hover ? Color.accentColor.opacity(0.15) : .clear))
    }

    private var thumbnail: some View {
        Group {
            if let image = item.loadImage() {
                Image(nsImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
            } else {
                Color.gray.opacity(0.2)
            }
        }
        .frame(width: 64, height: 64)
        .clipShape(RoundedRectangle(cornerRadius: 4))
    }

    private var groupMenu: some View {
        Menu {
            GroupAssignmentMenu(currentGroupID: item.groupID, groups: groups, onAssign: onAssign, onNewGroup: onNewGroup)
        } label: {
            Image(systemName: item.groupID != nil ? "folder.fill" : "folder")
                .foregroundStyle(item.groupID != nil ? Color.accentColor : Color.secondary)
        }
        .buttonStyle(.borderless)
        .menuIndicator(.hidden)
        .fixedSize()
        .help("Asignar a grupo")
    }

    private var favoriteButton: some View {
        Button(action: onToggleFavorite) {
            Image(systemName: item.isFavorite ? "star.fill" : "star")
                .foregroundStyle(item.isFavorite ? Color.yellow : Color.secondary)
        }
        .buttonStyle(.borderless)
        .help("Favorito")
    }
}

// MARK: - Groups management

struct GroupsManageView: View {
    @ObservedObject var store: ClipboardStore
    let onNewGroup: () -> Void

    var body: some View {
        ScrollView {
            VStack(spacing: 2) {
                if store.groups.isEmpty {
                    Text("Sin grupos todavía")
                        .foregroundStyle(.secondary)
                        .font(.callout)
                        .frame(maxWidth: .infinity)
                        .padding(.top, 20)
                }
                ForEach(store.groups) { group in
                    GroupManageRow(group: group, store: store)
                }

                // Fixed "Sin grupo" filter row.
                HStack(spacing: 8) {
                    Toggle("", isOn: Binding(
                        get: { store.showUngroupedFavorites },
                        set: { _ in store.showUngroupedFavorites.toggle() }
                    ))
                    .labelsHidden()
                    .toggleStyle(.checkbox)
                    Text("Sin grupo")
                        .foregroundStyle(.secondary)
                    Spacer()
                }
                .padding(.vertical, 5)
                .padding(.horizontal, 8)

                Divider().padding(.vertical, 4)

                Button(action: onNewGroup) {
                    Label("Nuevo grupo", systemImage: "plus")
                }
                .buttonStyle(.borderless)
            }
            .padding(8)
        }
    }
}

struct GroupManageRow: View {
    let group: ClipboardGroup
    @ObservedObject var store: ClipboardStore

    @State private var name: String

    init(group: ClipboardGroup, store: ClipboardStore) {
        self.group = group
        self._store = ObservedObject(wrappedValue: store)
        self._name = State(initialValue: group.name)
    }

    var body: some View {
        HStack(spacing: 8) {
            Toggle("", isOn: Binding(
                get: { group.isFilterEnabled },
                set: { _ in store.toggleGroupFilter(id: group.id) }
            ))
            .labelsHidden()
            .toggleStyle(.checkbox)
            .help("Mostrar/ocultar sus favoritos")

            TextField("Nombre", text: $name)
                .textFieldStyle(.plain)
                .onSubmit { store.renameGroup(id: group.id, to: name) }

            Spacer(minLength: 4)

            Button {
                store.deleteGroup(id: group.id)
            } label: {
                Image(systemName: "trash")
            }
            .buttonStyle(.borderless)
            .foregroundStyle(.secondary)
            .help("Eliminar grupo (los items se conservan)")
        }
        .padding(.vertical, 5)
        .padding(.horizontal, 8)
    }
}
