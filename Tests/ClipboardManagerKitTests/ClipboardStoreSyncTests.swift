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
/// Los tombstones van aparte, como en `JSONPersistenceService`.
private final class MemoryPersistence: PersistenceService, @unchecked Sendable {
    var storedItems: [ClipboardItem]
    var storedGroups: [ClipboardGroup]
    var storedItemTombstones: [ClipboardItem] = []
    var storedGroupTombstones: [ClipboardGroup] = []

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
    func loadTombstones() async -> (items: [ClipboardItem], groups: [ClipboardGroup]) {
        (storedItemTombstones, storedGroupTombstones)
    }
    func enqueueSaveItemTombstones(_ tombstones: [ClipboardItem]) { storedItemTombstones = tombstones }
    func enqueueSaveGroupTombstones(_ tombstones: [ClipboardGroup]) { storedGroupTombstones = tombstones }
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
        // `store.enc` solo tiene vivos; el tombstone va a su propio archivo.
        XCTAssertTrue(persistence.storedItems.isEmpty)
        XCTAssertEqual(persistence.storedItemTombstones.map(\.id), [id])

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
    func testProtectingThroughEditorMakesItemFavouriteAndStampsIt() async {
        // Cifrado de pega: la prueba no toca el Llavero.
        let store = ClipboardStore(
            persistence: MemoryPersistence(), deviceId: device, textSealer: { "sellado:" + $0 }
        )
        await store.load()
        store.add(.text("clave"))
        let id = store.items[0].id
        XCTAssertFalse(store.items[0].isFavorite)
        XCTAssertNil(store.items[0].stamps.favorite)

        XCTAssertTrue(store.setText(id: id, text: "clave", isProtected: true, title: "Banco"))
        XCTAssertTrue(store.items[0].isProtected)
        XCTAssertTrue(store.items[0].isFavorite)
        XCTAssertEqual(store.items[0].stamps.favorite?.deviceId, device)

        // Desproteger no quita la estrella ni cambia su marca.
        let favouriteStamp = store.items[0].stamps.favorite
        XCTAssertTrue(store.setText(id: id, text: "clave", isProtected: false, title: "Banco"))
        XCTAssertTrue(store.items[0].isFavorite)
        XCTAssertEqual(store.items[0].stamps.favorite, favouriteStamp)
    }

    @MainActor
    func testEditingNoteMakesItemFavouriteButSameNoteDoesNot() async {
        let store = await makeStore(MemoryPersistence())
        store.add(.text("hola"))
        let id = store.items[0].id
        XCTAssertFalse(store.items[0].isFavorite)

        // Guardar sin cambios no hace nada.
        store.setDetail(id: id, detail: "")
        XCTAssertFalse(store.items[0].isFavorite)
        XCTAssertNil(store.items[0].stamps.favorite)

        store.setDetail(id: id, detail: "nota")
        XCTAssertTrue(store.items[0].isFavorite)
        XCTAssertEqual(store.items[0].stamps.favorite?.deviceId, device)

        // La misma nota otra vez no toca la marca del favorito.
        let favouriteStamp = store.items[0].stamps.favorite
        store.setDetail(id: id, detail: "nota")
        XCTAssertEqual(store.items[0].stamps.favorite, favouriteStamp)
    }

    @MainActor
    func testEditingTextMakesItemFavouriteButSameTextDoesNot() async {
        let store = await makeStore(MemoryPersistence())
        store.add(.text("hola"))
        let id = store.items[0].id

        XCTAssertTrue(store.setText(id: id, text: "hola", isProtected: false, title: ""))
        XCTAssertFalse(store.items[0].isFavorite)
        XCTAssertNil(store.items[0].stamps.favorite)

        XCTAssertTrue(store.setText(id: id, text: "hola editado", isProtected: false, title: ""))
        XCTAssertTrue(store.items[0].isFavorite)
        XCTAssertEqual(store.items[0].stamps.favorite?.deviceId, device)
    }

    @MainActor
    func testEditingTitleMakesItemFavourite() async {
        let store = ClipboardStore(
            persistence: MemoryPersistence(), deviceId: device, textSealer: { "sellado:" + $0 }
        )
        await store.load()
        store.add(.text("clave"))
        let id = store.items[0].id
        XCTAssertTrue(store.setText(id: id, text: "clave", isProtected: false, title: "Banco"))
        XCTAssertTrue(store.items[0].isFavorite)
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
        XCTAssertTrue(persistence.storedGroups.isEmpty)
        XCTAssertEqual(persistence.storedGroupTombstones.map(\.id), [groupID])

        let reloaded = await makeStore(persistence)
        XCTAssertTrue(reloaded.groups.isEmpty)
        XCTAssertEqual(reloaded.groupTombstones.map(\.id), [groupID])
    }

    /// Una build anterior de esta rama guardaba los tombstones mezclados con
    /// los vivos. Al cargar se apartan, gana el borrado si el mismo id está
    /// vivo, y se reescriben los dos archivos por separado.
    @MainActor
    func testInlineTombstonesMoveToTheirOwnFiles() async {
        var dead = ClipboardItem.text("borrado")
        dead.isFavorite = true
        let deadStamp = SyncStamp(updatedAt: Date(timeIntervalSince1970: 1_700_000_000), deviceId: device)
        let tombstone = dead.tombstone(deadStamp)
        let alive = ClipboardItem.text("vivo")
        let deadGroup = ClipboardGroup(name: "Viejo").tombstone(deadStamp)
        let liveGroup = ClipboardGroup(name: "Trabajo")

        // El mismo id vivo y borrado: gana el borrado.
        let persistence = MemoryPersistence(items: [alive, tombstone, dead], groups: [liveGroup, deadGroup])
        let store = await makeStore(persistence)

        XCTAssertEqual(store.items.map(\.id), [alive.id])
        XCTAssertEqual(store.itemTombstones.map(\.id), [tombstone.id])
        XCTAssertEqual(store.groups.map(\.id), [liveGroup.id])
        XCTAssertEqual(store.groupTombstones.map(\.id), [deadGroup.id])
        XCTAssertEqual(persistence.storedItems.map(\.id), [alive.id])
        XCTAssertEqual(persistence.storedItemTombstones.map(\.id), [tombstone.id])
        XCTAssertEqual(persistence.storedGroups.map(\.id), [liveGroup.id])
        XCTAssertEqual(persistence.storedGroupTombstones.map(\.id), [deadGroup.id])
    }

    /// Un item vivo cuyo id ya tiene tombstone en su archivo (la app murió
    /// entre las dos escrituras) no vuelve: gana el borrado.
    @MainActor
    func testTombstoneFileWinsOverLiveCopy() async {
        var item = ClipboardItem.text("a medio borrar")
        item.isFavorite = true
        let persistence = MemoryPersistence(items: [item])
        persistence.storedItemTombstones = [item.tombstone(SyncStamp.now(deviceId: device))]
        let store = await makeStore(persistence)
        XCTAssertTrue(store.items.isEmpty)
        XCTAssertEqual(store.itemTombstones.map(\.id), [item.id])
        XCTAssertTrue(persistence.storedItems.isEmpty)
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
