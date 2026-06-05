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

    private let imageView = NSImageView()
    private let favoriteButton = NSButton()
    private let deleteButton = NSButton()

    /// The image data to pass to Quick Look.
    private var imageData: Data?

    private static let rowWidth: CGFloat = 300
    private static let horizontalInset: CGFloat = 12
    private static let thumbnailSize: CGFloat = 80

    init(item: ClipboardItem) {
        self.itemID = item.id
        self.imageData = item.imageData
        super.init(frame: NSRect(x: 0, y: 0, width: Self.rowWidth, height: 96))
        setupSubviews()
        update(with: item)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func update(with item: ClipboardItem) {
        if let data = item.imageData, let image = NSImage(data: data) {
            imageView.image = image
        }
        updateFavoriteIcon(isFavorite: item.isFavorite)
    }

    // MARK: - Layout

    private func setupSubviews() {
        translatesAutoresizingMaskIntoConstraints = false

        imageView.wantsLayer = true
        imageView.layer?.cornerRadius = 4
        imageView.layer?.masksToBounds = true
        imageView.imageScaling = .scaleProportionallyUpOrDown

        // Make the image view clickable for Quick Look.
        let clickGesture = NSClickGestureRecognizer(target: self, action: #selector(imageClicked))
        imageView.addGestureRecognizer(clickGesture)
        imageView.isEnabled = true

        NSLayoutConstraint.activate([
            imageView.widthAnchor.constraint(equalToConstant: Self.thumbnailSize),
            imageView.heightAnchor.constraint(equalToConstant: Self.thumbnailSize),
        ])

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

        let rowStack = NSStackView(views: [imageView, favoriteButton, deleteButton])
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

    // MARK: - Actions

    @objc private func favoriteTapped() {
        onToggleFavorite?()
    }

    @objc private func deleteTapped() {
        onDelete?()
    }

    @objc private func imageClicked() {
        guard let data = imageData else { return }

        // Write to a temp file and open with Quick Look.
        let tempURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("clipboard-preview-\(itemID.uuidString).png")
        do {
            try data.write(to: tempURL)
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/qlmanage")
            process.arguments = ["-p", tempURL.path]
            try process.run()
        } catch {
            NSLog("ClipboardManager: failed to open Quick Look: \(error)")
        }
    }

    // MARK: - Mouse forwarding

    override func mouseDown(with event: NSEvent) {
        let location = convert(event.locationInWindow, from: nil)
        if deleteButton.frame.contains(location) {
            deleteButton.mouseDown(with: event)
        } else if favoriteButton.frame.contains(location) {
            favoriteButton.mouseDown(with: event)
        } else {
            // Forward to imageView for the click gesture.
            imageView.mouseDown(with: event)
        }
    }
}