//
//  ClipboardMonitor.swift
//  ClipboardManager
//
//  Polls NSPasteboard.changeCount every second. On change, reads text or
//  image content and forwards it to the store.
//

import AppKit
import Combine

/// Observes the general pasteboard by polling its change count.
/// Designed to be driven by a 1 Hz timer.
@MainActor
public final class ClipboardMonitor {

    private let store: ClipboardStore
    private let pasteboard = NSPasteboard.general
    private var lastChangeCount: Int

    public init(store: ClipboardStore) {
        self.store = store
        self.lastChangeCount = pasteboard.changeCount
    }

    /// Call this once per second (e.g. from a Timer or TickEngine).
    /// Reads the pasteboard if its changeCount has incremented.
    public func tick() {
        let current = pasteboard.changeCount
        guard current != lastChangeCount else { return }
        lastChangeCount = current

        readPasteboard()
    }

    /// Limit image size to ~10 MB to avoid bloating the store.
    private static let maxImageSize = 10_000_000

    private func readPasteboard() {
        // Images first — try several strategies (see `imageData()`), because no
        // single API captures every source (screenshots, Preview, browsers,
        // file-promises all differ).
        if let data = imageData() {
            guard data.count < Self.maxImageSize else { return }
            store.add(.image(pngData: data))
            return
        }

        // Try plain text.
        if let text = pasteboard.string(forType: .string) {
            let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { return }
            store.add(.text(trimmed))
        }
    }

    /// Returns displayable image bytes from the pasteboard, or nil if there is
    /// no image. Prefers PNG, but **never drops an image just because PNG
    /// conversion fails** — it falls back to the raw TIFF bytes, which
    /// `NSImage` renders natively. (A Qt-app TIFF was failing NSBitmapImageRep
    /// → PNG conversion and getting silently discarded.)
    private func imageData() -> Data? {
        // 1) Raw PNG data (some apps copy PNG directly).
        if let png = pasteboard.data(forType: .png) {
            return png
        }
        // 2) Raw TIFF data → PNG, or the TIFF itself if conversion fails.
        if let tiff = pasteboard.data(forType: .tiff) {
            return Self.png(fromTIFF: tiff) ?? tiff
        }
        // 3) NSImage(pasteboard:) — handles PDF, file-URLs and promised types
        //    that the raw data reads above miss.
        if pasteboard.canReadObject(forClasses: [NSImage.self], options: nil),
           let image = NSImage(pasteboard: pasteboard),
           let tiff = image.tiffRepresentation {
            return Self.png(fromTIFF: tiff) ?? tiff
        }
        return nil
    }

    /// Converts TIFF data to PNG data. Returns nil if the TIFF can't be decoded.
    private static func png(fromTIFF tiff: Data) -> Data? {
        guard let bitmap = NSBitmapImageRep(data: tiff) else { return nil }
        return bitmap.representation(using: .png, properties: [:])
    }
}
