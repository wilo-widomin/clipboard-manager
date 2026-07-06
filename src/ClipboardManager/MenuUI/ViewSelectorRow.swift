//
//  ViewSelectorRow.swift
//  ClipboardManager
//
//  Custom NSView for the view-mode switcher (Text / Images).
//  A single row with two clickable segments. The active one is highlighted.
//  Clicking does NOT close the menu (custom mouseDown keeps tracking alive).
//

import AppKit

/// A row in the menu showing two toggleable segments: "Text" and "Images".
/// The active segment appears bold / highlighted.
@MainActor
final class ViewSelectorRow: NSView {

    private let textSegment: NSTextField
    private let imagesSegment: NSTextField
    private let separator: NSTextField
    private let leftIndicator: NSView
    private let rightIndicator: NSView
    private let clearTextButton: NSImageView
    private let clearImagesButton: NSImageView

    var onSelectText: (() -> Void)?
    var onSelectImages: (() -> Void)?
    /// Clears all non-favourite text items.
    var onClearText: (() -> Void)?
    /// Clears all non-favourite image items.
    var onClearImages: (() -> Void)?

    private static let rowWidth: CGFloat = 300
    private static let horizontalInset: CGFloat = 14

    init(selectedView: ClipboardViewMode) {
        textSegment = NSTextField(labelWithString: "Text")
        imagesSegment = NSTextField(labelWithString: "Images")
        separator = NSTextField(labelWithString: "|")
        leftIndicator = NSView()
        rightIndicator = NSView()
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
        let isText = selectedView == .text
        textSegment.font = isText ? .boldSystemFont(ofSize: NSFont.systemFontSize) : .menuFont(ofSize: 0)
        textSegment.textColor = isText ? .labelColor : .secondaryLabelColor
        leftIndicator.isHidden = !isText

        imagesSegment.font = !isText ? .boldSystemFont(ofSize: NSFont.systemFontSize) : .menuFont(ofSize: 0)
        imagesSegment.textColor = !isText ? .labelColor : .secondaryLabelColor
        rightIndicator.isHidden = isText
    }

    private func setupSubviews(selectedView: ClipboardViewMode) {
        translatesAutoresizingMaskIntoConstraints = false

        // Left indicator dot
        leftIndicator.wantsLayer = true
        leftIndicator.layer?.cornerRadius = 3
        leftIndicator.layer?.backgroundColor = NSColor.controlAccentColor.cgColor

        // Right indicator dot
        rightIndicator.wantsLayer = true
        rightIndicator.layer?.cornerRadius = 3
        rightIndicator.layer?.backgroundColor = NSColor.controlAccentColor.cgColor

        // Text segment
        textSegment.font = .menuFont(ofSize: 0)
        textSegment.isEnabled = false  // We handle clicks via mouseDown
        textSegment.setContentHuggingPriority(.required, for: .horizontal)
        textSegment.setContentCompressionResistancePriority(.required, for: .horizontal)

        // Separator
        separator.stringValue = "  |  "
        separator.font = .menuFont(ofSize: 0)
        separator.textColor = .tertiaryLabelColor
        separator.isEnabled = false
        separator.setContentHuggingPriority(.required, for: .horizontal)

        // Images segment
        imagesSegment.font = .menuFont(ofSize: 0)
        imagesSegment.isEnabled = false
        imagesSegment.setContentHuggingPriority(.required, for: .horizontal)
        imagesSegment.setContentCompressionResistancePriority(.required, for: .horizontal)

        // Trash buttons pinned to each edge (clicks handled via mouseDown).
        configureTrashButton(clearTextButton, tooltip: "Borrar todos los textos (excepto favoritos)")
        configureTrashButton(clearImagesButton, tooltip: "Borrar todas las imágenes (excepto favoritos)")

        let rowStack = NSStackView(views: [leftIndicator, textSegment, separator, imagesSegment, rightIndicator])
        rowStack.orientation = .horizontal
        rowStack.alignment = .centerY
        rowStack.spacing = 4
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

            leftIndicator.widthAnchor.constraint(equalToConstant: 6),
            leftIndicator.heightAnchor.constraint(equalToConstant: 6),
            rightIndicator.widthAnchor.constraint(equalToConstant: 6),
            rightIndicator.heightAnchor.constraint(equalToConstant: 6),

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

    /// The on-screen rect for the "Text" label (in our coordinate space).
    private var textRect: NSRect {
        textSegment.convert(textSegment.bounds, to: self)
    }

    /// The on-screen rect for the "Images" label (in our coordinate space).
    private var imagesRect: NSRect {
        imagesSegment.convert(imagesSegment.bounds, to: self)
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
        } else if textRect.contains(location) {
            onSelectText?()
        } else if imagesRect.contains(location) {
            onSelectImages?()
        } else {
            super.mouseDown(with: event)
        }
    }
}