//
//  ClipboardStoreSyncTests.swift
//  ClipboardManagerKitTests
//
//  Marcas y tombstones del store, con una persistencia en memoria. Solo items
//  de texto sin proteger: no tocan el Llavero ni la carpeta de imágenes.
//

import XCTest
import ClipboardManagerKit

/// Persistencia en memoria: devuelve lo que se le dé y guarda lo último escrito.
private final class MemoryPersistence: PersistenceService, @unchecked Sendable {
    var storedItems: [ClipboardItem]
    var storedGroups: [ClipboardGroup]

    init(items: [ClipboardItem] = [], groups: [ClipboardGroup] = []) {
        storedItems = items
        storedGroups = groups
    }

    var blockingError: Error? { nil }
    func load() async -> [ClipboardItem] { storedItems }
    func save(_ items: [ClipboardItem]) async throws { storedItems = items }
    func loadGroups() async -> [ClipboardGroup] { storedGroups }
    func saveGroups(_ groups: [ClipboardGroup]) async throws { storedGroups = groups }
    func enqueueSave(_ items: [ClipboardItem]) { storedItems = items }
    func enqueueSaveGroups(_ groups: [ClipboardGroup]) { storedGroups = groups }
}

final class ClipboardStoreSyncTests: XCTestCase {

    private let device = "TEST-DEVICE"

    @MainActor
    private func makeStore(_ persistence: MemoryPersistence) async -> ClipboardStore {
        let store = ClipboardStore(persistence: persistence, deviceId: device)
        await store.load()
        return store
    }

    @MainActor
    func testDeletingHistoryLeavesNoTombstone() async {
        let persistence = MemoryPersistence()
        let store = await makeStore(persistence)
        store.add(.text("historial"))
        let id = store.items[0].id
        store.remove(id: id)
        XCTAssertTrue(store.items.isEmpty)
        XCTAssertTrue(store.itemTombstones.isEmpty)
        XCTAssertTrue(persistence.storedItems.isEmpty)
    }

    @MainActor
    func testDeletingFavouriteLeavesContentlessTombstone() async {
        let persistence = MemoryPersistence()
        let store = await makeStore(persistence)
        store.add(.text("secreto"))
        let id = store.items[0].id
        store.toggleFavorite(id: id)
        store.setDetail(id: id, detail: "nota")
        store.remove(id: id)

        XCTAssertTrue(store.items.isEmpty)
        XCTAssertEqual(store.itemTombstones.count, 1)
        let dead = store.itemTombstones[0]
        XCTAssertEqual(dead.id, id)
        XCTAssertTrue(dead.isDeleted)
        XCTAssertEqual(dead.deletion?.deviceId, device)
        XCTAssertNil(dead.textContent)
        XCTAssertNil(dead.detail)
        XCTAssertEqual(persistence.storedItems.map(\.id), [id])

        // Al volver a cargar, el tombstone no aparece en la lista.
        let reloaded = await makeStore(persistence)
        XCTAssertTrue(reloaded.items.isEmpty)
        XCTAssertEqual(reloaded.itemTombstones.map(\.id), [id])
    }

    @MainActor
    func testMutationsStampOnlyWhatChanged() async {
        let store = await makeStore(MemoryPersistence())
        store.add(.text("hola"))
        let id = store.items[0].id
        XCTAssertNil(store.items[0].stamps.favorite)

        store.toggleFavorite(id: id)
        XCTAssertEqual(store.items[0].stamps.favorite?.deviceId, device)
        XCTAssertNil(store.items[0].stamps.detail)

        store.setDetail(id: id, detail: "nota")
        XCTAssertEqual(store.items[0].stamps.detail?.deviceId, device)

        store.setTextContent(id: id, text: "hola editado")
        XCTAssertEqual(store.items[0].stamps.content?.deviceId, device)
        XCTAssertNil(store.items[0].stamps.title)
        XCTAssertNil(store.items[0].stamps.protection)
    }

    @MainActor
    func testUnfavouriteKeepsItemAndCapLeavesTombstone() async {
        let store = await makeStore(MemoryPersistence())
        store.add(.text("fue favorito"))
        let id = store.items[0].id
        store.toggleFavorite(id: id)
        store.toggleFavorite(id: id)

        let item = store.items.first { $0.id == id }
        XCTAssertNotNil(item)
        XCTAssertEqual(item?.hasLeftSyncedSet, true)
        XCTAssertTrue(store.itemTombstones.isEmpty)

        // 50 textos más: el tope recicla el más viejo, que deja tombstone.
        for n in 0..<50 { store.add(.text("relleno \(n)")) }
        XCTAssertFalse(store.items.contains { $0.id == id })
        XCTAssertEqual(store.itemTombstones.map(\.id), [id])
        XCTAssertEqual(store.items.count, 50)
    }

    @MainActor
    func testRecopyingKeepsIdAndStamps() async {
        let store = await makeStore(MemoryPersistence())
        store.add(.text("repetido"))
        let id = store.items[0].id
        store.toggleFavorite(id: id)
        let stamp = store.items[0].stamps.favorite

        store.add(.text("repetido"))
        XCTAssertEqual(store.items.count, 1)
        XCTAssertEqual(store.items[0].id, id)
        XCTAssertTrue(store.items[0].isFavorite)
        XCTAssertEqual(store.items[0].stamps.favorite, stamp)
        XCTAssertTrue(store.itemTombstones.isEmpty)
    }

    @MainActor
    func testDeletingGroupLeavesTombstoneAndStampsItems() async {
        let persistence = MemoryPersistence()
        let store = await makeStore(persistence)
        guard let groupID = store.addGroup(name: "Trabajo") else { return XCTFail("sin grupo") }
        store.renameGroup(id: groupID, to: "Oficina")
        XCTAssertEqual(store.groups[0].nameStamp?.deviceId, device)

        store.add(.text("en el grupo"))
        let id = store.items[0].id
        store.assignGroup(itemID: id, groupID: groupID)
        store.deleteGroup(id: groupID)

        XCTAssertTrue(store.groups.isEmpty)
        XCTAssertEqual(store.groupTombstones.map(\.id), [groupID])
        XCTAssertEqual(store.groupTombstones[0].name, "")
        XCTAssertNil(store.items[0].groupID)
        XCTAssertEqual(store.items[0].stamps.group?.deviceId, device)
        XCTAssertEqual(persistence.storedGroups.map(\.id), [groupID])

        let reloaded = await makeStore(persistence)
        XCTAssertTrue(reloaded.groups.isEmpty)
        XCTAssertEqual(reloaded.groupTombstones.map(\.id), [groupID])
    }

    @MainActor
    func testOldFilesWithoutSyncFieldsDecode() throws {
        let json = """
        [{"id":"10000000-0000-4000-8000-000000000001","contentType":"text",
          "createdAt":700000000,"textContent":"viejo","isFavorite":true}]
        """
        let items = try JSONDecoder().decode([ClipboardItem].self, from: Data(json.utf8))
        XCTAssertEqual(items.count, 1)
        XCTAssertNil(items[0].stamps.content)
        XCTAssertNil(items[0].deletion)
        XCTAssertNil(items[0].imageHash)
        XCTAssertEqual(items[0].effectiveStamps().favorite, SyncStamp.legacy(at: items[0].createdAt))

        let groupsJSON = #"[{"id":"90000000-0000-4000-8000-000000000001","name":"Trabajo"}]"#
        let groups = try JSONDecoder().decode([ClipboardGroup].self, from: Data(groupsJSON.utf8))
        XCTAssertEqual(groups[0].effectiveNameStamp, SyncStamp.legacyGroup)
        XCTAssertFalse(groups[0].isDeleted)
    }
}
