//
//  ClipboardItem.swift
//  ClipboardManager
//
//  Model for a single clipboard entry: text or image, with favorites support.
//  Images are stored as individual .png files on disk; the model only keeps
//  the filename reference.
//

import Foundation

/// The type of content stored in a clipboard item.
public enum ClipboardContentType: String, Codable, Sendable {
    case text
    case image
}

/// A single clipboard entry captured by the monitor.
public struct ClipboardItem: Identifiable, Codable, Sendable {

    public let id: UUID
    public let contentType: ClipboardContentType
    public let createdAt: Date

    /// The text content (nil for image items).
    public let textContent: String?

    /// Filename of the PNG file on disk, relative to the images directory.
    /// Example: "E621F1A2-4B3C-4D5E-8F9A-0B1C2D3E4F5F.png"
    public let imageFilename: String?

    /// Whether the user has starred this item as a favourite.
    public var isFavorite: Bool

    // MARK: - Preview helpers

    /// First 30 characters of the text, with ellipsis if truncated.
    public var textPreview: String {
        guard let text = textContent else { return "" }
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.count > 30 {
            return String(trimmed.prefix(30)) + "…"
        }
        return trimmed
    }

    // MARK: - Image loading

    /// Returns the full file URL for this item's image, if it is an image item.
    public var imageFileURL: URL? {
        guard let filename = imageFilename else { return nil }
        return ImageStorage.directoryURL?.appendingPathComponent(filename)
    }

    /// Loads the image from disk. Returns nil if the file doesn't exist or is
    /// not a valid image. The original file size is preserved; callers scale
    /// for display as needed.
    public func loadImage() -> NSImage? {
        guard let url = imageFileURL else { return nil }
        return NSImage(contentsOf: url)
    }

    // MARK: - Factory

    /// Creates a text clipboard item.
    public static func text(_ text: String) -> ClipboardItem {
        ClipboardItem(
            id: UUID(),
            contentType: .text,
            createdAt: Date(),
            textContent: text,
            imageFilename: nil,
            isFavorite: false
        )
    }

    /// Creates an image clipboard item. The PNG data is saved to disk; the
    /// model stores only the filename.
    public static func image(pngData: Data) -> ClipboardItem {
        let id = UUID()
        let filename = "\(id.uuidString).png"
        // Save to disk (best-effort).
        if let dir = ImageStorage.directoryURL {
            let fileURL = dir.appendingPathComponent(filename)
            try? pngData.write(to: fileURL, options: .atomic)
        }
        return ClipboardItem(
            id: id,
            contentType: .image,
            createdAt: Date(),
            textContent: nil,
            imageFilename: filename,
            isFavorite: false
        )
    }
}

/// Manages the images directory on disk.
public enum ImageStorage {
    /// URL of the images directory, creating it if needed.
    public static var directoryURL: URL? {
        let appSupport = FileManager.default.urls(
            for: .applicationSupportDirectory, in: .userDomainMask
        ).first
        guard let base = appSupport else { return nil }
        let dir = base.appendingPathComponent("ClipboardManager/images", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    /// Deletes an image file from disk. The filename must be a bare filename
    /// (not a path) to prevent directory traversal.
    public static func delete(filename: String) {
        guard let dir = directoryURL else { return }
        // Basic path sanitisation: ensure no directory separators.
        guard !filename.contains("/") else { return }
        let fileURL = dir.appendingPathComponent(filename)
        try? FileManager.default.removeItem(at: fileURL)
    }
}