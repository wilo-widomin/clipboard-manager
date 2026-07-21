//
//  ClipboardStore.swift
//  ClipboardManager
//
//  ObservableObject single source of truth for all clipboard items.
//  Capped per content type (50 text, 20 images), never globally; only
//  non-favourites are evicted, so favourites can push a type past its
//  limit. Favourites always sort first, then the rest — both groups
//  ordered by creation date descending.
//

import Foundation
import Combine

/// The current display filter for the menu.
public enum ClipboardViewMode: String, Codable, Sendable, Hashable {
    case text
    case images
    case groups
}

/// Owns the clipboard item list, manages ordering and persistence triggers.
@MainActor
public final class ClipboardStore: ObservableObject {

    // Separate limits per content type.
    private let maxTextItems = 50
    private let maxImageItems = 20

    /// All items, ordered: favourites first (by date desc), then rest (by date desc).
    @Published public private(set) var items: [ClipboardItem] = []

    /// User-defined groups. Favourites can be assigned to at most one each.
    @Published public private(set) var groups: [ClipboardGroup] = []

    /// Whether ungrouped items (groupID == nil) are shown in the Text / Images
    /// lists. Controlled by the "Sin grupo" checkbox in the Groups view.
    @Published public var showUngrouped: Bool = true {
        didSet {
            UserDefaults.standard.set(showUngrouped, forKey: "showUngroupedFavorites")
        }
    }

    /// Which view the menu should show. Persisted in UserDefaults.
    @Published public var viewMode: ClipboardViewMode = .text {
        didSet {
            UserDefaults.standard.set(viewMode.rawValue, forKey: "viewMode")
        }
    }

    /// Items filtered by the current view mode and the active group filter.
    public var visibleItems: [ClipboardItem] {
        switch viewMode {
        case .text:
            return items.filter { $0.contentType == .text && passesGroupFilter($0) }
        case .images:
            return items.filter { $0.contentType == .image && passesGroupFilter($0) }
        case .groups:
            return []
        }
    }

    /// The group-checkbox filter, applied to **all** items: an item is hidden
    /// when its group's checkbox is off, or (for ungrouped items — which includes
    /// every non-favourite, since only favourites can hold a group) when the
    /// "Sin grupo" checkbox is off. An item whose group was deleted is treated
    /// as ungrouped.
    public func passesGroupFilter(_ item: ClipboardItem) -> Bool {
        if let gid = item.groupID, let group = groups.first(where: { $0.id == gid }) {
            return group.isFilterEnabled
        }
        return showUngrouped
    }

    private let persistence: PersistenceService

    public init(persistence: PersistenceService) {
        self.persistence = persistence
        // Restore persisted view mode preference.
        if let raw = UserDefaults.standard.string(forKey: "viewMode"),
           let mode = ClipboardViewMode(rawValue: raw) {
            self.viewMode = mode
        }
        // Restore the "Sin grupo" filter toggle (defaults to shown).
        if UserDefaults.standard.object(forKey: "showUngroupedFavorites") != nil {
            self.showUngrouped = UserDefaults.standard.bool(forKey: "showUngroupedFavorites")
        }
    }

    // MARK: - Loading

    public func load() async {
        let loaded = await persistence.load()
        let loadedGroups = await persistence.loadGroups()
        groups = loadedGroups
        // Enforce the per-type limits on load too, so a store that grew past
        // the limit under an older build (or a lowered limit) is normalised.
        items = capAllTypes(sort(loaded))
    }

    public func adoptInitialState(_ loaded: [ClipboardItem]) {
        items = capAllTypes(sort(loaded))
    }

    // MARK: - Mutations

    /// Adds a new item, enforcing the per-type max count (oldest non-favourite drops).
    public func add(_ item: ClipboardItem) {
        var incoming = item

        // Deduplicate: re-copying an item already in the list (e.g. clicking a
        // row puts it back on the pasteboard, which the monitor then re-reads)
        // must not create a second copy. Drop the old entry so only one remains;
        // the new one takes its place at the top (it has the newest date).
        // Carry over the favourite flag AND the group so re-copying an item
        // (e.g. clicking it to paste) keeps its star and its group assignment —
        // otherwise the fresh copy, which has no group, would replace it and the
        // group relationship would silently disappear.
        if let existing = items.first(where: { isDuplicate($0, of: incoming) }) {
            incoming.isFavorite = existing.isFavorite
            incoming.groupID = existing.groupID
            purge(id: existing.id)
        }

        // Cap only the type we just added; enforce the count *of that type*,
        // NOT the total across all types (the old bug compared the total item
        // count against a per-type limit, which deleted a freshly-added image
        // whenever the store already held more items than the image limit).
        let capped = cap(items + [incoming], type: incoming.contentType)
        items = sort(capped)
        persist()
    }

    /// True when two items hold the same content (same text, or same image
    /// bytes). Favourite flag and creation date are ignored.
    private func isDuplicate(_ a: ClipboardItem, of b: ClipboardItem) -> Bool {
        guard a.contentType == b.contentType else { return false }
        switch a.contentType {
        case .text:
            return a.textContent == b.textContent
        case .image:
            return imageBytes(a) == imageBytes(b)
        }
    }

    /// Reads an image item's bytes from disk for content comparison.
    private func imageBytes(_ item: ClipboardItem) -> Data? {
        guard let url = item.imageFileURL else { return nil }
        return try? Data(contentsOf: url)
    }

    /// Removes an item from the list and deletes its image file, without
    /// triggering a persist (the caller persists after the surrounding change).
    private func purge(id: ClipboardItem.ID) {
        let toRemove = items.first { $0.id == id }
        items.removeAll { $0.id == id }
        if let filename = toRemove?.imageFilename {
            ImageStorage.delete(filename: filename)
        }
    }

    /// Maximum items allowed for a given content type.
    private func maxCount(for contentType: ClipboardContentType) -> Int {
        switch contentType {
        case .text:  return maxTextItems
        case .image: return maxImageItems
        }
    }

    /// Drops oldest non-favourite items of `type` until that type is within its
    /// limit. Deletes the image file of any dropped image item.
    private func cap(_ list: [ClipboardItem], type: ClipboardContentType) -> [ClipboardItem] {
        var result = list
        let limit = maxCount(for: type)
        while result.filter({ $0.contentType == type }).count > limit {
            guard let drop = result
                .filter({ $0.contentType == type && !$0.isFavorite })
                .min(by: { $0.createdAt < $1.createdAt })
            else { break }  // only favourites left — keep them
            result.removeAll { $0.id == drop.id }
            if let filename = drop.imageFilename {
                ImageStorage.delete(filename: filename)
            }
        }
        return result
    }

    /// Applies `cap` to every content type.
    private func capAllTypes(_ list: [ClipboardItem]) -> [ClipboardItem] {
        var result = list
        for type in [ClipboardContentType.text, .image] {
            result = cap(result, type: type)
        }
        return result
    }

    /// Removes a single item by id. Also deletes the image file from disk
    /// if the item was an image.
    public func remove(id: ClipboardItem.ID) {
        let before = items.count
        // Grab the item before removing it so we can clean up its file.
        let toRemove = items.first { $0.id == id }
        items.removeAll { $0.id == id }
        guard items.count != before else { return }
        // Delete the image file if applicable.
        if let filename = toRemove?.imageFilename {
            ImageStorage.delete(filename: filename)
        }
        persist()
    }

    /// Toggles the favourite flag on an item. Un-favouriting also removes the
    /// item from any group, since group membership implies "favourite".
    public func toggleFavorite(id: ClipboardItem.ID) {
        guard let idx = items.firstIndex(where: { $0.id == id }) else { return }
        items[idx].isFavorite.toggle()
        if !items[idx].isFavorite {
            items[idx].groupID = nil
        }
        items = sort(items)
        persist()
    }

    /// Sets (or clears) the free-text detail note on an item. Whitespace-only
    /// input clears the note (stored as `nil`). Order is unaffected, so no
    /// re-sort — just persist. Editing is gated by the caller behind
    /// authentication (see `Authenticator`).
    public func setDetail(id: ClipboardItem.ID, detail: String) {
        guard let idx = items.firstIndex(where: { $0.id == id }) else { return }
        let trimmed = detail.trimmingCharacters(in: .whitespacesAndNewlines)
        items[idx].detail = trimmed.isEmpty ? nil : trimmed
        persist()
    }

    /// Clears all non-favourite items. Also deletes their image files from disk.
    public func clearNonFavorites() {
        let before = items.count
        let removed = items.filter { !$0.isFavorite }
        items = items.filter { $0.isFavorite }
        guard items.count != before else { return }
        // Delete image files of removed items.
        for item in removed {
            if let filename = item.imageFilename {
                ImageStorage.delete(filename: filename)
            }
        }
        persist()
    }

    /// Clears all non-favourite items of a single content type, leaving
    /// favourites and the other type untouched. Deletes any removed image files.
    public func clearNonFavorites(ofType type: ClipboardContentType) {
        let removed = items.filter { $0.contentType == type && !$0.isFavorite }
        guard !removed.isEmpty else { return }
        let removedIDs = Set(removed.map(\.id))
        items.removeAll { removedIDs.contains($0.id) }
        for item in removed {
            if let filename = item.imageFilename {
                ImageStorage.delete(filename: filename)
            }
        }
        persist()
    }

    // MARK: - Groups

    /// Creates a new group with the given name (trimmed). Returns its id, or
    /// nil if the name is blank. Duplicate names are allowed (ids are unique).
    @discardableResult
    public func addGroup(name: String) -> UUID? {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        let group = ClipboardGroup(name: trimmed)
        groups.append(group)
        persistGroups()
        return group.id
    }

    /// Renames a group. No-op if the id is unknown or the name is blank.
    public func renameGroup(id: ClipboardGroup.ID, to name: String) {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        guard let idx = groups.firstIndex(where: { $0.id == id }) else { return }
        groups[idx].name = trimmed
        persistGroups()
    }

    /// Deletes a group. Items assigned to it are kept and become ungrouped
    /// (their content — text/passwords and images — is untouched).
    public func deleteGroup(id: ClipboardGroup.ID) {
        guard groups.contains(where: { $0.id == id }) else { return }
        groups.removeAll { $0.id == id }
        var itemsChanged = false
        for idx in items.indices where items[idx].groupID == id {
            items[idx].groupID = nil
            itemsChanged = true
        }
        persistGroups()
        if itemsChanged { persist() }
    }

    /// Toggles a group's filter checkbox (show/hide its favourites in the lists).
    public func toggleGroupFilter(id: ClipboardGroup.ID) {
        guard let idx = groups.firstIndex(where: { $0.id == id }) else { return }
        groups[idx].isFilterEnabled.toggle()
        persistGroups()
    }

    /// Assigns an item to a group (or removes it from any group when `groupID`
    /// is nil). Assigning to a group also marks the item as a favourite, so it
    /// survives the per-type cap. Removing the group leaves the favourite flag
    /// untouched.
    public func assignGroup(itemID: ClipboardItem.ID, groupID: ClipboardGroup.ID?) {
        guard let idx = items.firstIndex(where: { $0.id == itemID }) else { return }
        // Ignore unknown group ids.
        if let gid = groupID, !groups.contains(where: { $0.id == gid }) { return }
        items[idx].groupID = groupID
        if groupID != nil { items[idx].isFavorite = true }
        items = sort(items)
        persist()
    }

    // MARK: - Sorting

    /// Favourites first (descending date), then the rest (descending date).
    private func sort(_ list: [ClipboardItem]) -> [ClipboardItem] {
        list.sorted { a, b in
            if a.isFavorite != b.isFavorite {
                return a.isFavorite && !b.isFavorite
            }
            return a.createdAt > b.createdAt
        }
    }

    // MARK: - Persistence

    private func persist() {
        let snapshot = items
        Task { [persistence] in
            do {
                try await persistence.save(snapshot)
            } catch {
                NSLog("ClipboardManager: failed to persist: \(error.localizedDescription)")
            }
        }
    }

    private func persistGroups() {
        let snapshot = groups
        Task { [persistence] in
            do {
                try await persistence.saveGroups(snapshot)
            } catch {
                NSLog("ClipboardManager: failed to persist groups: \(error.localizedDescription)")
            }
        }
    }
}