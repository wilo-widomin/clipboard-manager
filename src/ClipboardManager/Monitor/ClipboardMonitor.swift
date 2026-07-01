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
        let types = (pasteboard.types ?? []).map(\.rawValue)
        NSLog("ClipboardManager: pasteboard changed, types=%@", types.description)

        // Images first — try several strategies (see `imagePNG()`), because no
        // single API captures every source (screenshots, Preview, browsers,
        // file-promises all differ).
        if let pngData = imagePNG() {
            guard pngData.count < Self.maxImageSize else {
                NSLog("ClipboardManager: image skipped, too large (%d bytes)", pngData.count)
                return
            }
            NSLog("ClipboardManager: captured image (%d bytes PNG)", pngData.count)
            store.add(.image(pngData: pngData))
            return
        }

        // Try plain text.
        if let text = pasteboard.string(forType: .string) {
            let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { return }
            let item = ClipboardItem.text(trimmed)
            store.add(item)
            return
        }

        NSLog("ClipboardManager: no image or text captured for types=%@", types.description)
    }

    /// Attempts to obtain PNG data for an image on the pasteboard using several
    /// fallbacks. Returns nil if the pasteboard holds no usable image.
    private func imagePNG() -> Data? {
        // 1) Raw PNG data (some apps copy PNG directly).
        if let png = pasteboard.data(forType: .png) {
            NSLog("ClipboardManager: image via raw .png data")
            return png
        }
        // 2) Raw TIFF data → PNG.
        if let tiff = pasteboard.data(forType: .tiff),
           let png = Self.png(fromTIFF: tiff) {
            NSLog("ClipboardManager: image via raw .tiff data")
            return png
        }
        // 3) NSImage(pasteboard:) — handles PDF, file-URLs and promised types
        //    that the raw data reads above miss.
        if pasteboard.canReadObject(forClasses: [NSImage.self], options: nil),
           let image = NSImage(pasteboard: pasteboard),
           let tiff = image.tiffRepresentation,
           let png = Self.png(fromTIFF: tiff) {
            NSLog("ClipboardManager: image via NSImage(pasteboard:)")
            return png
        }
        return nil
    }

    /// Converts TIFF data to PNG data.
    private static func png(fromTIFF tiff: Data) -> Data? {
        guard let bitmap = NSBitmapImageRep(data: tiff) else { return nil }
        return bitmap.representation(using: .png, properties: [:])
    }
}