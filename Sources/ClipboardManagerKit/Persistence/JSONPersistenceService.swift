//
//  PersistenceService.swift
//  ClipboardManager
//
//  Protocol + JSON implementation for loading/saving clipboard items.
//

import Foundation

/// Abstraction over the persistence backend (injectable for testing).
public protocol PersistenceService: Sendable {
    func load() async -> [ClipboardItem]
    func save(_ items: [ClipboardItem]) async throws
    func loadGroups() async -> [ClipboardGroup]
    func saveGroups(_ groups: [ClipboardGroup]) async throws
}

/// JSON-file based persistence. Reads/writes an array of ClipboardItem to a
/// file in the app's Application Support directory.
public final class JSONPersistenceService: PersistenceService {

    private let fileURL: URL
    private let groupsURL: URL
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()
    private let queue = DispatchQueue(label: "com.clipboardmanager.persistence", qos: .utility)

    public init() {
        let appSupport = FileManager.default.urls(
            for: .applicationSupportDirectory, in: .userDomainMask
        ).first!
        let dir = appSupport.appendingPathComponent("ClipboardManager", isDirectory: true)
        // Ensure the directory exists.
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)

        self.fileURL = dir.appendingPathComponent("store.json")
        self.groupsURL = dir.appendingPathComponent("groups.json")
    }

    /// For testing with a custom URL. The groups file sits alongside it.
    public init(fileURL: URL) {
        self.fileURL = fileURL
        self.groupsURL = fileURL.deletingLastPathComponent().appendingPathComponent("groups.json")
    }

    public func load() async -> [ClipboardItem] {
        await withCheckedContinuation { continuation in
            queue.async { [weak self] in
                guard let self = self else {
                    continuation.resume(returning: [])
                    return
                }
                do {
                    let data = try Data(contentsOf: self.fileURL)
                    let items = try self.decoder.decode([ClipboardItem].self, from: data)
                    continuation.resume(returning: items)
                } catch {
                    // File missing or corrupt — start fresh.
                    continuation.resume(returning: [])
                }
            }
        }
    }

    public func save(_ items: [ClipboardItem]) async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            queue.async { [weak self] in
                guard let self = self else {
                    continuation.resume()
                    return
                }
                do {
                    let data = try self.encoder.encode(items)
                    try data.write(to: self.fileURL, options: .atomic)
                    continuation.resume()
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }

    // MARK: - Groups

    public func loadGroups() async -> [ClipboardGroup] {
        await withCheckedContinuation { continuation in
            queue.async { [weak self] in
                guard let self = self else {
                    continuation.resume(returning: [])
                    return
                }
                do {
                    let data = try Data(contentsOf: self.groupsURL)
                    let groups = try self.decoder.decode([ClipboardGroup].self, from: data)
                    continuation.resume(returning: groups)
                } catch {
                    // File missing or corrupt — start with no groups.
                    continuation.resume(returning: [])
                }
            }
        }
    }

    public func saveGroups(_ groups: [ClipboardGroup]) async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            queue.async { [weak self] in
                guard let self = self else {
                    continuation.resume()
                    return
                }
                do {
                    let data = try self.encoder.encode(groups)
                    try data.write(to: self.groupsURL, options: .atomic)
                    continuation.resume()
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }
}