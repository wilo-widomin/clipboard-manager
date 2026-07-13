//
//  ClipboardGroup.swift
//  ClipboardManager
//
//  A user-defined group that favourite items can be assigned to. Each item
//  belongs to at most one group (via ClipboardItem.groupID). Groups are
//  persisted separately from items in `groups.json`.
//
//  `isFilterEnabled` drives the checkbox in the Groups view: when disabled,
//  the group's favourites are hidden from the Text / Images lists.
//

import Foundation

public struct ClipboardGroup: Identifiable, Codable, Sendable, Equatable {

    public let id: UUID
    public var name: String

    /// Whether this group's favourites are shown in the Text / Images lists.
    /// Toggled by the checkbox in the Groups view. Defaults to true (shown).
    public var isFilterEnabled: Bool

    public init(id: UUID = UUID(), name: String, isFilterEnabled: Bool = true) {
        self.id = id
        self.name = name
        self.isFilterEnabled = isFilterEnabled
    }

    // Decode `isFilterEnabled` leniently so groups written by an older build
    // (or a hand-edited file) default to "shown" rather than failing to load.
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.id = try c.decode(UUID.self, forKey: .id)
        self.name = try c.decode(String.self, forKey: .name)
        self.isFilterEnabled = try c.decodeIfPresent(Bool.self, forKey: .isFilterEnabled) ?? true
    }
}
