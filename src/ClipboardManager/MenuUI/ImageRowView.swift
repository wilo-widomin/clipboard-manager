//
//  ImageRowView.swift
//  ClipboardManager
//
//  Custom NSView for an image clipboard item inside the menu.
//  Layout: [ 80×80 thumbnail ]  [ ⭐ ]  [ 🗑 ]
//  Clicking the thumbnail opens Quick Look preview.
//

import AppKit

/// A single row in the image clipboard list.
@MainActor
final class ImageRowView: NSView {

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

    private let imageView = NSImageView()
    private let groupButton = NSButton()
    private let favoriteButton = NSButton()
    private let deleteButton = NSButton()

    /// Loads the image from the file path stored in the model.
    private var itemImage: NSImage? {
        guard let item else { return nil }
        return item.loadImage()
    }

    /// The model item this row represents. Used to load the image from its file.
    private var item: ClipboardItem?

    private static let rowWidth: CGFloat = 300
    private static let horizontalInset: CGFloat = 12
    private static let thumbnailSize: CGFloat = 80

    init(item: ClipboardItem) {
        self.itemID = item.id
        self.item = item
        self.currentGroupID = item.groupID
        super.init(frame: NSRect(x: 0, y: 0, width: Self.rowWidth, height: 96))
        setupSubviews()
        update(with: item)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func update(with item: ClipboardItem) {
        self.item = item
        self.currentGroupID = item.groupID
        if let image = item.loadImage() {
            imageView.image = image
        } else {
            NSLog("ClipboardManager: failed to load thumbnail for %@ (file: %@)",
                  item.id.uuidString, item.imageFilename ?? "nil")
        }
        updateFavoriteIcon(isFavorite: item.isFavorite)
        updateGroupIcon(hasGroup: item.groupID != nil)
    }

    // MARK: - Layout

    private func setupSubviews() {
        translatesAutoresizingMaskIntoConstraints = false
        wantsLayer = true
        layer?.cornerRadius = 5

        imageView.wantsLayer = true
        imageView.layer?.cornerRadius = 4
        imageView.layer?.masksToBounds = true
        imageView.imageScaling = .scaleProportionallyUpOrDown

        NSLayoutConstraint.activate([
            imageView.widthAnchor.constraint(equalToConstant: Self.thumbnailSize),
            imageView.heightAnchor.constraint(equalToConstant: Self.thumbnailSize),
        ])

        groupButton.bezelStyle = .shadowlessSquare
        groupButton.isBordered = false
        groupButton.imagePosition = .imageOnly
        groupButton.contentTintColor = .secondaryLabelColor
        groupButton.target = self
        groupButton.action = #selector(groupTapped)
        groupButton.toolTip = "Asignar a grupo"
        groupButton.setContentHuggingPriority(.required, for: .horizontal)

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

        let rowStack = NSStackView(views: [imageView, spacer, groupButton, favoriteButton, deleteButton])
        rowStack.orientation = .horizontal
        rowStack.alignment = .centerY
        rowStack.spacing = 10
        rowStack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(rowStack)

        NSLayoutConstraint.activate([
            widthAnchor.constraint(equalToConstant: Self.rowWidth),
            rowStack.leadingAnchor.constraint(equalTo: leadingAnchor, constant: Self.horizontalInset),
            rowStack.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -Self.horizontalInset),
            rowStack.topAnchor.constraint(equalTo: topAnchor, constant: 8),
            rowStack.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -8),
        ])
    }

    private func updateFavoriteIcon(isFavorite: Bool) {
        let symbol = isFavorite ? "star.fill" : "star"
        favoriteButton.image = NSImage(systemSymbolName: symbol, accessibilityDescription: "Favorite")
        favoriteButton.contentTintColor = isFavorite ? .systemYellow : .secondaryLabelColor
    }

    private func updateGroupIcon(hasGroup: Bool) {
        let symbol = hasGroup ? "folder.fill" : "folder"
        groupButton.image = NSImage(systemSymbolName: symbol, accessibilityDescription: "Group")
        groupButton.contentTintColor = hasGroup ? .controlAccentColor : .secondaryLabelColor
    }

    // MARK: - Actions

    @objc private func favoriteTapped() {
        onToggleFavorite?()
    }

    @objc private func groupTapped() {
        presentGroupAssignmentMenu()
    }

    /// Shows the group-assignment menu. See TextRowView for why the status menu
    /// is closed first and the popup is deferred to the next run-loop pass.
    private func presentGroupAssignmentMenu() {
        guard let window = window else { return }
        let assign = onAssignGroup
        let makeNew = onNewGroupAndAssign
        let menu = GroupContextMenu.make(
            groups: groups,
            currentGroupID: currentGroupID,
            onAssign: { assign?($0) },
            onNew: { makeNew?() }
        )
        let frameInWindow = groupButton.convert(groupButton.bounds, to: nil)
        let screenRect = window.convertToScreen(frameInWindow)
        let point = NSPoint(x: screenRect.minX, y: screenRect.minY)

        enclosingMenuItem?.menu?.cancelTracking()
        DispatchQueue.main.async {
            NSApp.activate(ignoringOtherApps: true)
            menu.popUp(positioning: nil, at: point, in: nil)
        }
    }

    @objc private func deleteTapped() {
        onDelete?()
    }

    @objc private func imageClicked() {
        guard let url = item?.imageFileURL else { return }

        // Open the image file with Quick Look (qlmanage).
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/qlmanage")
        process.arguments = ["-p", url.path]
        do {
            try process.run()
        } catch {
            NSLog("ClipboardManager: failed to open Quick Look: \(error)")
        }
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
        if deleteButton.frame.contains(location) {
            deleteButton.mouseDown(with: event)
        } else if favoriteButton.frame.contains(location) {
            favoriteButton.mouseDown(with: event)
        } else if groupButton.frame.contains(location) {
            presentGroupAssignmentMenu()
        } else {
            // Dismiss the menu first so key focus returns to the previously
            // active app before PasteboardHelper posts Cmd+V.
            enclosingMenuItem?.menu?.cancelTracking()
            onSelect?()
        }
    }

    // Right-click also assigns to a group, where AppKit delivers it (it usually
    // does not inside an open menu — hence the group button above).
    override func rightMouseDown(with event: NSEvent) {
        presentGroupAssignmentMenu()
    }
}