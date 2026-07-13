//
//  GroupRowView.swift
//  ClipboardManager
//
//  Custom NSView for a group row inside the Groups view of the menu.
//  Layout: [ ✓ checkbox ]  [ name ]  [ ✎ rename ]  [ 🗑 delete ]
//  The checkbox toggles whether this group's favourites appear in the
//  Text / Images lists.
//

import AppKit

/// A single row in the Groups management list.
@MainActor
final class GroupRowView: NSView {

    let groupID: ClipboardGroup.ID

    var onToggleFilter: (() -> Void)?
    var onRename: (() -> Void)?
    var onDelete: (() -> Void)?

    private let checkboxButton = NSButton()
    private let nameLabel = NSTextField(labelWithString: "")
    private let renameButton = NSButton()
    private let deleteButton = NSButton()

    private static let rowWidth: CGFloat = 300
    private static let horizontalInset: CGFloat = 12

    init(group: ClipboardGroup) {
        self.groupID = group.id
        super.init(frame: NSRect(x: 0, y: 0, width: Self.rowWidth, height: 36))
        setupSubviews()
        update(with: group)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func update(with group: ClipboardGroup) {
        nameLabel.stringValue = group.name
        updateCheckboxIcon(enabled: group.isFilterEnabled)
    }

    // MARK: - Layout

    private func setupSubviews() {
        translatesAutoresizingMaskIntoConstraints = false
        wantsLayer = true
        layer?.cornerRadius = 5

        configureIconButton(checkboxButton, tooltip: "Mostrar/ocultar sus favoritos", action: #selector(checkboxTapped))
        checkboxButton.contentTintColor = .controlAccentColor

        nameLabel.font = .menuFont(ofSize: 0)
        nameLabel.lineBreakMode = .byTruncatingTail
        nameLabel.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)

        configureIconButton(renameButton, tooltip: "Renombrar", action: #selector(renameTapped))
        renameButton.image = NSImage(systemSymbolName: "pencil", accessibilityDescription: "Rename")

        configureIconButton(deleteButton, tooltip: "Eliminar grupo", action: #selector(deleteTapped))
        deleteButton.image = NSImage(systemSymbolName: "trash", accessibilityDescription: "Delete")

        let spacer = NSView()
        spacer.setContentHuggingPriority(.defaultLow, for: .horizontal)

        let rowStack = NSStackView(views: [checkboxButton, nameLabel, spacer, renameButton, deleteButton])
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

    private func configureIconButton(_ button: NSButton, tooltip: String, action: Selector) {
        button.bezelStyle = .shadowlessSquare
        button.isBordered = false
        button.imagePosition = .imageOnly
        button.contentTintColor = .secondaryLabelColor
        button.target = self
        button.action = action
        button.toolTip = tooltip
        button.setContentHuggingPriority(.required, for: .horizontal)
    }

    private func updateCheckboxIcon(enabled: Bool) {
        let symbol = enabled ? "checkmark.square.fill" : "square"
        checkboxButton.image = NSImage(systemSymbolName: symbol, accessibilityDescription: "Filter")
        checkboxButton.contentTintColor = enabled ? .controlAccentColor : .secondaryLabelColor
    }

    // MARK: - Actions

    @objc private func checkboxTapped() { onToggleFilter?() }
    @objc private func renameTapped() { onRename?() }
    @objc private func deleteTapped() { onDelete?() }

    // MARK: - Hover (rollover)

    private static let hoverColor = NSColor.controlAccentColor.withAlphaComponent(0.18).cgColor

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        trackingAreas.forEach(removeTrackingArea)
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
        } else if renameButton.frame.contains(location) {
            renameButton.mouseDown(with: event)
        } else {
            // Clicking anywhere else on the row toggles the checkbox — a
            // forgiving hit target for the filter.
            onToggleFilter?()
        }
    }
}

/// A checkbox + label row with no rename/delete affordances. Used for the fixed
/// "Sin grupo" filter row in the Groups view.
@MainActor
final class SimpleCheckboxRow: NSView {

    var onToggle: (() -> Void)?

    private let checkboxButton = NSButton()
    private let label = NSTextField(labelWithString: "")

    private static let rowWidth: CGFloat = 300
    private static let horizontalInset: CGFloat = 12

    init(title: String, isOn: Bool) {
        super.init(frame: NSRect(x: 0, y: 0, width: Self.rowWidth, height: 36))
        setupSubviews(title: title)
        update(isOn: isOn)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func update(isOn: Bool) {
        let symbol = isOn ? "checkmark.square.fill" : "square"
        checkboxButton.image = NSImage(systemSymbolName: symbol, accessibilityDescription: "Filter")
        checkboxButton.contentTintColor = isOn ? .controlAccentColor : .secondaryLabelColor
    }

    private func setupSubviews(title: String) {
        translatesAutoresizingMaskIntoConstraints = false
        wantsLayer = true
        layer?.cornerRadius = 5

        checkboxButton.bezelStyle = .shadowlessSquare
        checkboxButton.isBordered = false
        checkboxButton.imagePosition = .imageOnly
        checkboxButton.target = self
        checkboxButton.action = #selector(toggle)
        checkboxButton.setContentHuggingPriority(.required, for: .horizontal)

        label.font = .menuFont(ofSize: 0)
        label.textColor = .secondaryLabelColor
        label.stringValue = title

        let spacer = NSView()
        spacer.setContentHuggingPriority(.defaultLow, for: .horizontal)

        let rowStack = NSStackView(views: [checkboxButton, label, spacer])
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

    @objc private func toggle() { onToggle?() }

    override func mouseDown(with event: NSEvent) {
        onToggle?()
    }
}
