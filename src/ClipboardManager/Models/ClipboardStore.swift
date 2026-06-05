//
//  ClipboardStore.swift
//  ClipboardManager
//
//  ObservableObject single source of truth for all clipboard items.
//  Holds up to `maxItems` entries. Favourites always sort first,
//  then the rest — both groups ordered by creation date descending.
//

import Foundation
import Combine

/// Maximum number of items retained in the store.
private let maxItems = 100

/// The current display filter for the menu.
public enum ClipboardViewMode: String, Codable, Sendable {
    case text
    case images
}

/// Owns the clipboard item list, manages ordering and persistence triggers.
@MainActor
public final class ClipboardStore: ObservableObject {

    // Separate limits per content type.
    private let maxTextItems = 100
    private let maxImageItems = 20

    /// All items, ordered: favourites first (by date desc), then rest (by date desc).
    @Published public private(set) var items: [ClipboardItem] = []

    /// Which view the menu should show. Persisted in UserDefaults.
    @Published public var viewMode: ClipboardViewMode = .text {
        didSet {
            UserDefaults.standard.set(viewMode.rawValue, forKey: "viewMode")
        }
    }

    /// Items filtered by the current view mode.
    public var visibleItems: [ClipboardItem] {
        switch viewMode {
        case .text:
            return items.filter { $0.contentType == .text }
        case .images:
            return items.filter { $0.contentType == .image }
        }
    }

    private let persistence: PersistenceService

    public init(persistence: PersistenceService) {
        self.persistence = persistence
        // Restore persisted view mode preference.
        if let raw = UserDefaults.standard.string(forKey: "viewMode"),
           let mode = ClipboardViewMode(rawValue: raw) {
            self.viewMode = mode
        }
    }

    // MARK: - Loading

    public func load() async {
        let loaded = await persistence.load()
        items = sort(loaded)
    }

    public func adoptInitialState(_ loaded: [ClipboardItem]) {
        items = sort(loaded)
    }

    // MARK: - Mutations

    /// Adds a new item, enforcing the per-type max count (oldest non-favourite drops).
    public func add(_ item: ClipboardItem) {
        var newItems = items + [item]
        if newItems.count > maxCount(for: item.contentType) {
            // Drop the oldest non-favourite item of the same type.
            let oldestNonFav = newItems
                .filter { $0.contentType == item.contentType && !$0.isFavorite }
                .sorted { $0.createdAt < $1.createdAt }
                .first
            if let drop = oldestNonFav {
                newItems.removeAll { $0.id == drop.id }
                // Also delete the image file if it was an image.
                if let filename = drop.imageFilename {
                    ImageStorage.delete(filename: filename)
                }
            }
        }
        items = sort(newItems)
        persist()
    }

    /// Maximum items allowed for a given content type.
    private func maxCount(for contentType: ClipboardContentType) -> Int {
        switch contentType {
        case .text:  return maxTextItems
        case .image: return maxImageItems
        }
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

    /// Toggles the favourite flag on an item.
    public func toggleFavorite(id: ClipboardItem.ID) {
        guard let idx = items.firstIndex(where: { $0.id == id }) else { return }
        items[idx].isFavorite.toggle()
        items = sort(items)
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
}