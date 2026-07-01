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

        // Images first. We use `NSImage(pasteboard:)` rather than reading a raw
        // `.tiff`/`.png` data type directly: many apps (Preview, browsers, some
        // screenshot flows) publish images as PDF, file-URLs or *promised* types
        // for which `data(forType: .tiff)` returns nil, so those images were
        // silently dropped. `NSImage(pasteboard:)` resolves all of those.
        if pasteboard.canReadObject(forClasses: [NSImage.self], options: nil) {
            if let image = NSImage(pasteboard: pasteboard),
               let pngData = Self.pngData(from: image) {
                guard pngData.count < Self.maxImageSize else {
                    NSLog("ClipboardManager: image skipped, too large (%d bytes)", pngData.count)
                    return
                }
                NSLog("ClipboardManager: captured image (%d bytes PNG)", pngData.count)
                let item = ClipboardItem.image(pngData: pngData)
                store.add(item)
                return
            }
            NSLog("ClipboardManager: canReadObject(NSImage)=true but NSImage/PNG conversion failed")
        }

        // Try plain text.
        if let text = pasteboard.string(forType: .string) {
            let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { return }
            let item = ClipboardItem.text(trimmed)
            store.add(item)
            return
        }
    }

    /// Normalises any `NSImage` to PNG data for on-disk storage.
    private static func pngData(from image: NSImage) -> Data? {
        guard let tiff = image.tiffRepresentation,
              let bitmap = NSBitmapImageRep(data: tiff) else { return nil }
        return bitmap.representation(using: .png, properties: [:])
    }
}