//
//  TextRowView.swift
//  ClipboardManager
//
//  Custom NSView for a text clipboard item inside the menu.
//  Layout: [ 30-char preview ]  [ ⭐ ]  [ 🗑 ]
//

import AppKit

/// A single row in the text clipboard list.
@MainActor
final class TextRowView: NSView {

    let itemID: ClipboardItem.ID

    var onToggleFavorite: (() -> Void)?
    var onDelete: (() -> Void)?
    var onSelect: (() -> Void)?

    /// Assign this item to a group (nil removes it from any group).
    var onAssignGroup: ((UUID?) -> Void)?
    /// Create a new group (via prompt) and assign this item to it.
    var onNewGroupAndAssign: (() -> Void)?

    /// Group context injected by the builder so the right-click menu can list
    /// the current groups and mark the item's current assignment.
    var groups: [ClipboardGroup] = []
    private var currentGroupID: UUID?

    private let previewLabel = NSTextField(labelWithString: "")
    private let favoriteButton = NSButton()
    private let deleteButton = NSButton()

    private static let rowWidth: CGFloat = 300
    private static let horizontalInset: CGFloat = 12

    init(item: ClipboardItem) {
        self.itemID = item.id
        self.currentGroupID = item.groupID
        super.init(frame: NSRect(x: 0, y: 0, width: Self.rowWidth, height: 36))
        setupSubviews()
        update(with: item)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func update(with item: ClipboardItem) {
        previewLabel.stringValue = item.textPreview
        currentGroupID = item.groupID
        updateFavoriteIcon(isFavorite: item.isFavorite)
    }

    // MARK: - Layout

    private func setupSubviews() {
        translatesAutoresizingMaskIntoConstraints = false
        wantsLayer = true
        layer?.cornerRadius = 5

        previewLabel.font = .menuFont(ofSize: 0)
        previewLabel.lineBreakMode = .byTruncatingTail
        previewLabel.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)

        favoriteButton.bezelStyle = .shadowlessSquare
        favoriteButton.isBordered = false
        favoriteButton.imagePosition = .imageOnly
        favoriteButton.contentTintColor = .secondaryLabelColor
        favoriteButton.target = self
        favoriteButton.action = #selector(favoriteTapped)
        favoriteButton.toolTip = "Toggle Favorite"
        favoriteButton.setContentHuggingPriority(.required, for: .horizontal)

        deleteButton.bezelStyle = .shadowlessSquare
        deleteButton.isBordered = false
        deleteButton.image = NSImage(systemSymbolName: "trash", accessibilityDescription: "Delete")
        deleteButton.imagePosition = .imageOnly
        deleteButton.contentTintColor = .secondaryLabelColor
        deleteButton.target = self
        deleteButton.action = #selector(deleteTapped)
        deleteButton.toolTip = "Delete"
        deleteButton.setContentHuggingPriority(.required, for: .horizontal)

        let spacer = NSView()
        spacer.setContentHuggingPriority(.defaultLow, for: .horizontal)

        let rowStack = NSStackView(views: [previewLabel, spacer, favoriteButton, deleteButton])
        rowStack.orientation = .horizontal
        rowStack.alignment = .centerY
        rowStack.spacing = 8
        rowStack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(rowStack)

        NSLayoutConstraint.activate([
            widthAnchor.constraint(equalToConstant: Self.rowWidth),
            rowStack.leadingAnchor.constraint(equalTo: leadingAnchor, constant: Self.horizontalInset),
            rowStack.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -Self.horizontalInset),
            rowStack.topAnchor.constraint(equalTo: topAnchor, constant: 4),
            rowStack.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -4),
        ])
    }

    private func updateFavoriteIcon(isFavorite: Bool) {
        let symbol = isFavorite ? "star.fill" : "star"
        favoriteButton.image = NSImage(systemSymbolName: symbol, accessibilityDescription: "Favorite")
        favoriteButton.contentTintColor = isFavorite ? .systemYellow : .secondaryLabelColor
    }

    // MARK: - Actions

    @objc private func favoriteTapped() {
        onToggleFavorite?()
    }

    @objc private func deleteTapped() {
        onDelete?()
    }

    // MARK: - Hover (rollover)

    /// Subtle accent-tinted background shown while the pointer is over the row.
    private static let hoverColor = NSColor.controlAccentColor.withAlphaComponent(0.18).cgColor

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        trackingAreas.forEach(removeTrackingArea)
        // `.activeAlways` is required: menus track events in their own run-loop
        // mode, so the default `.activeInKeyWindow` would never fire here.
        let area = NSTrackingArea(
            rect: .zero,
            options: [.mouseEnteredAndExited, .mouseMoved, .cursorUpdate, .activeAlways, .inVisibleRect],
            owner: self,
            userInfo: nil
        )
        addTrackingArea(area)
    }

    override func mouseEntered(with event: NSEvent) {
        layer?.backgroundColor = Self.hoverColor
        NSCursor.pointingHand.set()
    }

    // Menus reset the cursor on every mouse-moved event, so we must reassert
    // the pointing hand continuously while the pointer travels over the row.
    override func mouseMoved(with event: NSEvent) {
        NSCursor.pointingHand.set()
    }

    override func mouseExited(with event: NSEvent) {
        layer?.backgroundColor = nil
        NSCursor.arrow.set()
    }

    override func cursorUpdate(with event: NSEvent) {
        NSCursor.pointingHand.set()
    }

    // MARK: - Mouse forwarding

    override func mouseDown(with event: NSEvent) {
        let location = convert(event.locationInWindow, from: nil)
        // Try delete button first, then favorite, then select (copy + paste).
        if deleteButton.frame.contains(location) {
            deleteButton.mouseDown(with: event)
        } else if favoriteButton.frame.contains(location) {
            favoriteButton.mouseDown(with: event)
        } else {
            // Dismiss the menu first so key focus returns to the previously
            // active app before PasteboardHelper posts Cmd+V.
            enclosingMenuItem?.menu?.cancelTracking()
            onSelect?()
        }
    }

    // Right-click assigns the item to a group.
    override func rightMouseDown(with event: NSEvent) {
        let menu = GroupContextMenu.make(
            groups: groups,
            currentGroupID: currentGroupID,
            onAssign: { [weak self] gid in self?.onAssignGroup?(gid) },
            onNew: { [weak self] in self?.onNewGroupAndAssign?() }
        )
        let location = convert(event.locationInWindow, from: nil)
        menu.popUp(positioning: nil, at: location, in: self)
    }
}