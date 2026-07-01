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
        Self.debugLog("monitor started (changeCount=\(pasteboard.changeCount))")
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
        Self.debugLog("changed: types=\(types)")

        // Images first — try several strategies (see `imageData()`), because no
        // single API captures every source (screenshots, Preview, browsers,
        // file-promises all differ).
        if let data = imageData() {
            guard data.count < Self.maxImageSize else {
                Self.debugLog("image skipped, too large (\(data.count) bytes)")
                return
            }
            Self.debugLog("stored IMAGE (\(data.count) bytes)")
            store.add(.image(pngData: data))
            return
        }

        // Try plain text.
        if let text = pasteboard.string(forType: .string) {
            let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else {
                Self.debugLog("text empty after trim — nothing stored")
                return
            }
            Self.debugLog("stored TEXT (\(trimmed.count) chars)")
            store.add(.text(trimmed))
            return
        }

        Self.debugLog("NOTHING stored for types=\(types)")
    }

    /// Returns displayable image bytes from the pasteboard, or nil if there is
    /// no image. Prefers PNG, but **never drops an image just because PNG
    /// conversion fails** — it falls back to the raw TIFF bytes, which
    /// `NSImage` renders natively. (A Qt-app TIFF was failing NSBitmapImageRep
    /// → PNG conversion and getting silently discarded.)
    private func imageData() -> Data? {
        // 1) Raw PNG data (some apps copy PNG directly).
        if let png = pasteboard.data(forType: .png) {
            Self.debugLog("image via raw .png data (\(png.count) bytes)")
            return png
        }
        // 2) Raw TIFF data → PNG, or the TIFF itself if conversion fails.
        if let tiff = pasteboard.data(forType: .tiff) {
            if let png = Self.png(fromTIFF: tiff) {
                Self.debugLog("image via .tiff→PNG (\(png.count) bytes)")
                return png
            }
            Self.debugLog("PNG conversion failed; storing raw TIFF (\(tiff.count) bytes)")
            return tiff
        }
        // 3) NSImage(pasteboard:) — handles PDF, file-URLs and promised types
        //    that the raw data reads above miss.
        if pasteboard.canReadObject(forClasses: [NSImage.self], options: nil),
           let image = NSImage(pasteboard: pasteboard),
           let tiff = image.tiffRepresentation {
            if let png = Self.png(fromTIFF: tiff) {
                Self.debugLog("image via NSImage(pasteboard:)→PNG (\(png.count) bytes)")
                return png
            }
            Self.debugLog("image via NSImage(pasteboard:) raw TIFF (\(tiff.count) bytes)")
            return tiff
        }
        Self.debugLog("imageData: no image found")
        return nil
    }

    // MARK: - File-based diagnostics

    /// Appends a line to `~/Library/Application Support/ClipboardManager/debug.log`.
    /// We log to a file because this app's `NSLog` output does not reach the
    /// unified logging system reliably, making live debugging impossible.
    private static let debugLogURL: URL? = {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
        return base?.appendingPathComponent("ClipboardManager/debug.log")
    }()

    static func debugLog(_ message: String) {
        NSLog("ClipboardManager: %@", message)
        guard let url = debugLogURL else { return }
        let line = "\(ISO8601DateFormatter().string(from: Date()))  \(message)\n"
        guard let data = line.data(using: .utf8) else { return }
        if let handle = try? FileHandle(forWritingTo: url) {
            defer { try? handle.close() }
            _ = try? handle.seekToEnd()
            try? handle.write(contentsOf: data)
        } else {
            // File doesn't exist yet — create it.
            try? data.write(to: url, options: .atomic)
        }
    }

    /// Converts TIFF data to PNG data. Returns nil if the TIFF can't be decoded.
    private static func png(fromTIFF tiff: Data) -> Data? {
        guard let bitmap = NSBitmapImageRep(data: tiff) else { return nil }
        return bitmap.representation(using: .png, properties: [:])
    }
}