//
//  PopoverActions.swift
//  ClipboardManagerKit
//
//  The seam between the shared popover UI and whichever app hosts it.
//
//  Everything that is a plain data mutation goes straight to `ClipboardStore`
//  from the views. Only the three things that need the *host* — pasting into
//  another app, Quick Look, and opening the editor window — are injected here,
//  because each host does them differently: the standalone app has to capture
//  and reactivate the app that had focus before its popover stole it, while a
//  host like Widomin owns the popover already and has no focus to restore.
//

import Foundation

/// Callbacks the popover needs from the app hosting it.
public struct PopoverActions {

    /// The user picked an item: copy it and paste it wherever it belongs.
    public let selectItem: (ClipboardItem) -> Void

    /// Preview an image item.
    public let quickLook: (ClipboardItem) -> Void

    /// Open the detail editor for an item (right-click on a row).
    public let editDetail: (ClipboardItem) -> Void

    public init(
        selectItem: @escaping (ClipboardItem) -> Void,
        quickLook: @escaping (ClipboardItem) -> Void,
        editDetail: @escaping (ClipboardItem) -> Void
    ) {
        self.selectItem = selectItem
        self.quickLook = quickLook
        self.editDetail = editDetail
    }
}
