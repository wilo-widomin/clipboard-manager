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

    private func readPasteboard() {
        // Try to read a TIFF image first (most common image pasteboard type).
        if let tiffData = pasteboard.data(forType: .tiff),
           let bitmap = NSBitmapImageRep(data: tiffData),
           let pngData = bitmap.representation(using: .png, properties: [.compressionFactor: 0.8]) {
            // Limit image size to ~10 MB to avoid bloating the JSON store.
            guard pngData.count < 10_000_000 else { return }
            let item = ClipboardItem.image(pngData: pngData)
            store.add(item)
            return
        }

        // Try PNG directly (some apps copy PNG data).
        if let pngData = pasteboard.data(forType: .png) {
            guard pngData.count < 10_000_000 else { return }
            let item = ClipboardItem.image(pngData: pngData)
            store.add(item)
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
    }
}