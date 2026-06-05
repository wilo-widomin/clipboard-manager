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

    /// All items, ordered: favourites first (by date desc), then rest (by date desc).
    @Published public private(set) var items: [ClipboardItem] = []

    /// Which view the menu should show.
    @Published public var viewMode: ClipboardViewMode = .text

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

    /// Adds a new item, enforcing the max count (oldest non-favourite drops).
    public func add(_ item: ClipboardItem) {
        var newItems = items + [item]
        if newItems.count > maxItems {
            // Drop the oldest non-favourite item.
            let oldestNonFav = newItems
                .filter { !$0.isFavorite }
                .sorted { $0.createdAt < $1.createdAt }
                .first
            if let drop = oldestNonFav {
                newItems.removeAll { $0.id == drop.id }
            }
        }
        items = sort(newItems)
        persist()
    }

    /// Removes a single item by id.
    public func remove(id: ClipboardItem.ID) {
        let before = items.count
        items.removeAll { $0.id == id }
        guard items.count != before else { return }
        persist()
    }

    /// Toggles the favourite flag on an item.
    public func toggleFavorite(id: ClipboardItem.ID) {
        guard let idx = items.firstIndex(where: { $0.id == id }) else { return }
        items[idx].isFavorite.toggle()
        items = sort(items)
        persist()
    }

    /// Clears all non-favourite items.
    public func clearNonFavorites() {
        let before = items.count
        items = items.filter { $0.isFavorite }
        guard items.count != before else { return }
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