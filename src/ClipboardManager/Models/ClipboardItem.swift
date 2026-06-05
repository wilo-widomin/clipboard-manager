//
//  ClipboardItem.swift
//  ClipboardManager
//
//  Model for a single clipboard entry: text or image, with favorites support.
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

    /// PNG-encoded image data (nil for text items).
    public let imageData: Data?

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

    // MARK: - Factory

    /// Creates a text clipboard item.
    public static func text(_ text: String) -> ClipboardItem {
        ClipboardItem(
            id: UUID(),
            contentType: .text,
            createdAt: Date(),
            textContent: text,
            imageData: nil,
            isFavorite: false
        )
    }

    /// Creates an image clipboard item from PNG data.
    public static func image(pngData: Data) -> ClipboardItem {
        ClipboardItem(
            id: UUID(),
            contentType: .image,
            createdAt: Date(),
            textContent: nil,
            imageData: pngData,
            isFavorite: false
        )
    }
}