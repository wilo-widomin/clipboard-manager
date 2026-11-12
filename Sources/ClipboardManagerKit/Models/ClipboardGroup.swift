//
//  ClipboardGroup.swift
//  ClipboardManager
//
//  A user-defined group that favourite items can be assigned to. Each item
//  belongs to at most one group (via ClipboardItem.groupID). Groups are
//  persisted separately from items in `groups.json`.
//
//  `isFilterEnabled` is the group's slot in the filter *selection* (a badge /
//  checkbox): when nothing is selected every item shows, and selecting a group
//  narrows the Text / Images lists to it (OR-combined with other selections).
//

import Foundation

public struct ClipboardGroup: Identifiable, Codable, Sendable, Equatable {

    public let id: UUID
    public var name: String

    /// Whether this group is selected in the filter. Toggled by its badge /
    /// checkbox. Defaults to false (not selected) so new groups don't
    /// immediately start hiding everything else.
    public var isFilterEnabled: Bool

    public init(id: UUID = UUID(), name: String, isFilterEnabled: Bool = false) {
        self.id = id
        self.name = name
        self.isFilterEnabled = isFilterEnabled
    }

    // Decode `isFilterEnabled` leniently so groups written by an older build
    // (or a hand-edited file) load fine. Missing → not selected, so an upgrade
    // starts with the filter inactive (all items shown) rather than suddenly
    // hiding everything outside the previously-"enabled" groups.
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.id = try c.decode(UUID.self, forKey: .id)
        self.name = try c.decode(String.self, forKey: .name)
        self.isFilterEnabled = try c.decodeIfPresent(Bool.self, forKey: .isFilterEnabled) ?? false
    }
}
