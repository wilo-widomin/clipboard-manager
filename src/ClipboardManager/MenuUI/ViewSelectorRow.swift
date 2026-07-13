//
//  ViewSelectorRow.swift
//  ClipboardManager
//
//  Custom NSView for the view-mode switcher (Text / Images / Grupos).
//  A single row with three clickable segments. The active one is highlighted
//  (bold + accent colour). Clicking does NOT close the menu (custom mouseDown
//  keeps tracking alive). Trash buttons at each edge clear non-favourite text
//  and image items.
//

import AppKit

/// A row in the menu showing three toggleable segments: "Text", "Images",
/// "Grupos". The active segment appears bold / accent-coloured.
@MainActor
final class ViewSelectorRow: NSView {

    private let textSegment: NSTextField
    private let imagesSegment: NSTextField
    private let groupsSegment: NSTextField
    private let separator1: NSTextField
    private let separator2: NSTextField
    private let clearTextButton: NSImageView
    private let clearImagesButton: NSImageView

    var onSelectText: (() -> Void)?
    var onSelectImages: (() -> Void)?
    var onSelectGroups: (() -> Void)?
    /// Clears all non-favourite text items.
    var onClearText: (() -> Void)?
    /// Clears all non-favourite image items.
    var onClearImages: (() -> Void)?

    private static let rowWidth: CGFloat = 300
    private static let horizontalInset: CGFloat = 14

    init(selectedView: ClipboardViewMode) {
        textSegment = NSTextField(labelWithString: "Text")
        imagesSegment = NSTextField(labelWithString: "Images")
        groupsSegment = NSTextField(labelWithString: "Grupos")
        separator1 = NSTextField(labelWithString: "  |  ")
        separator2 = NSTextField(labelWithString: "  |  ")
        clearTextButton = NSImageView()
        clearImagesButton = NSImageView()

        super.init(frame: NSRect(x: 0, y: 0, width: Self.rowWidth, height: 32))
        setupSubviews(selectedView: selectedView)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func update(selectedView: ClipboardViewMode) {
        style(textSegment, active: selectedView == .text)
        style(imagesSegment, active: selectedView == .images)
        style(groupsSegment, active: selectedView == .groups)
    }

    private func style(_ segment: NSTextField, active: Bool) {
        segment.font = active ? .boldSystemFont(ofSize: NSFont.systemFontSize) : .menuFont(ofSize: 0)
        segment.textColor = active ? .controlAccentColor : .secondaryLabelColor
    }

    private func setupSubviews(selectedView: ClipboardViewMode) {
        translatesAutoresizingMaskIntoConstraints = false

        for segment in [textSegment, imagesSegment, groupsSegment] {
            segment.isEnabled = false  // We handle clicks via mouseDown
            segment.setContentHuggingPriority(.required, for: .horizontal)
            segment.setContentCompressionResistancePriority(.required, for: .horizontal)
        }
        for sep in [separator1, separator2] {
            sep.font = .menuFont(ofSize: 0)
            sep.textColor = .tertiaryLabelColor
            sep.isEnabled = false
            sep.setContentHuggingPriority(.required, for: .horizontal)
        }

        // Trash buttons pinned to each edge (clicks handled via mouseDown).
        configureTrashButton(clearTextButton, tooltip: "Borrar todos los textos (excepto favoritos)")
        configureTrashButton(clearImagesButton, tooltip: "Borrar todas las imágenes (excepto favoritos)")

        let rowStack = NSStackView(views: [textSegment, separator1, imagesSegment, separator2, groupsSegment])
        rowStack.orientation = .horizontal
        rowStack.alignment = .centerY
        rowStack.spacing = 2
        rowStack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(rowStack)
        addSubview(clearTextButton)
        addSubview(clearImagesButton)

        NSLayoutConstraint.activate([
            widthAnchor.constraint(equalToConstant: Self.rowWidth),
            rowStack.centerXAnchor.constraint(equalTo: centerXAnchor),
            rowStack.centerYAnchor.constraint(equalTo: centerYAnchor),
            rowStack.topAnchor.constraint(greaterThanOrEqualTo: topAnchor, constant: 4),
            rowStack.bottomAnchor.constraint(lessThanOrEqualTo: bottomAnchor, constant: -4),

            clearTextButton.leadingAnchor.constraint(equalTo: leadingAnchor, constant: Self.horizontalInset),
            clearTextButton.centerYAnchor.constraint(equalTo: centerYAnchor),
            clearTextButton.widthAnchor.constraint(equalToConstant: 16),
            clearTextButton.heightAnchor.constraint(equalToConstant: 16),

            clearImagesButton.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -Self.horizontalInset),
            clearImagesButton.centerYAnchor.constraint(equalTo: centerYAnchor),
            clearImagesButton.widthAnchor.constraint(equalToConstant: 16),
            clearImagesButton.heightAnchor.constraint(equalToConstant: 16),
        ])

        update(selectedView: selectedView)
    }

    /// Styles an NSImageView as a subtle trash-can button.
    private func configureTrashButton(_ view: NSImageView, tooltip: String) {
        view.image = NSImage(systemSymbolName: "trash", accessibilityDescription: tooltip)
        view.contentTintColor = .secondaryLabelColor
        view.toolTip = tooltip
        view.translatesAutoresizingMaskIntoConstraints = false
    }

    // MARK: - Hit testing areas for clicks

    private func rect(for view: NSView) -> NSRect {
        view.convert(view.bounds, to: self)
    }

    /// Enlarged hit rect around a trash button so it's comfortable to click.
    private func hitRect(for view: NSView) -> NSRect {
        view.convert(view.bounds, to: self).insetBy(dx: -6, dy: -6)
    }

    /// Claim every click inside our bounds so `mouseDown` handles routing
    /// (the trash `NSImageView`s would otherwise swallow their own clicks).
    override func hitTest(_ point: NSPoint) -> NSView? {
        bounds.contains(convert(point, from: superview)) ? self : nil
    }

    override func mouseDown(with event: NSEvent) {
        let location = convert(event.locationInWindow, from: nil)
        if hitRect(for: clearTextButton).contains(location) {
            onClearText?()
        } else if hitRect(for: clearImagesButton).contains(location) {
            onClearImages?()
        } else if rect(for: textSegment).contains(location) {
            onSelectText?()
        } else if rect(for: imagesSegment).contains(location) {
            onSelectImages?()
        } else if rect(for: groupsSegment).contains(location) {
            onSelectGroups?()
        } else {
            super.mouseDown(with: event)
        }
    }
}
