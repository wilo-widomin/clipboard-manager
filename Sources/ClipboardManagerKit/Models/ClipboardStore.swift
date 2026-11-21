//
//  ClipboardStore.swift
//  ClipboardManager
//
//  ObservableObject single source of truth for all clipboard items.
//  Capped per content type (50 text, 20 images), never globally, and the
//  cap counts **only non-favourites**: favourites are unlimited and don't
//  consume the history budget. Favourites always sort first, then the
//  rest — both groups ordered by creation date descending.
//
//  Modelo sincronizable (§6 del blueprint): cada mutación de un campo
//  sincronizable le pone su marca `(updatedAt, deviceId)`, y borrar algo del
//  conjunto sincronizado (favoritos y grupos) deja un tombstone en
//  `itemTombstones` / `groupTombstones` en lugar de quitarlo sin rastro. Las
//  listas `items` y `groups` solo tienen lo vivo: vistas, topes, buscador,
//  deduplicación y filtro de grupos no ven nunca un tombstone. En disco también
//  van aparte (`item-tombstones.enc`, `group-tombstones.enc`), para que una
//  versión anterior que lea `store.enc`/`groups.enc` no los tome por vivos.
//

import Foundation
import Combine
import CryptoKit

/// The current display filter for the menu.
public enum ClipboardViewMode: String, Codable, Sendable, Hashable {
    case text
    case images
    case groups
}

/// Owns the clipboard item list, manages ordering and persistence triggers.
@MainActor
public final class ClipboardStore: ObservableObject {

    // Separate limits per content type, applied only to non-favourites.
    private let maxTextItems = 50
    private let maxImageItems = 20

    /// All items, ordered: favourites first (by date desc), then rest (by date desc).
    @Published public private(set) var items: [ClipboardItem] = []

    /// User-defined groups. Favourites can be assigned to at most one each.
    @Published public private(set) var groups: [ClipboardGroup] = []

    /// Items borrados que estaban (o estuvieron) en el conjunto sincronizado,
    /// ya sin contenido. Se guardan en su propio archivo
    /// (`item-tombstones.enc`), nunca en `store.enc`, y no se enseñan nunca.
    /// Hoy no se podan: ver «Tombstones» en
    /// `docs/agent-context/historial/_dominio.md`.
    public private(set) var itemTombstones: [ClipboardItem] = []

    /// Grupos borrados, sin nombre. Se guardan en `group-tombstones.enc`.
    public private(set) var groupTombstones: [ClipboardGroup] = []

    /// `itemTombstones` / `groupTombstones` han cambiado desde la última vez
    /// que se encolaron: el siguiente guardado escribe también su archivo.
    private var itemTombstonesDirty = false
    private var groupTombstonesDirty = false

    /// Whether the "Sin grupo" filter is selected. Part of the group-filter
    /// *selection*: when nothing is selected the filter is inactive and every
    /// item shows; selecting "Sin grupo" narrows the lists to ungrouped items.
    /// Controlled by the "Sin grupo" badge / checkbox. Deliberately **not**
    /// persisted — the filter is a per-session aid that starts empty on launch.
    @Published public var showUngrouped: Bool = false

    /// Texto del buscador. Filtra las listas por los tres campos de texto del
    /// item (contenido, título y nota). **No se persiste**: como el filtro de
    /// grupos, es una ayuda de sesión y el popover abre siempre sin filtrar.
    @Published public var searchQuery: String = ""

    /// Which view the menu should show. Persisted in UserDefaults.
    @Published public var viewMode: ClipboardViewMode = .text {
        didSet {
            UserDefaults.standard.set(viewMode.rawValue, forKey: "viewMode")
        }
    }

    /// Items filtered by the current view mode, the active group filter and the
    /// search query.
    public var visibleItems: [ClipboardItem] {
        switch viewMode {
        case .text:
            return items.filter { $0.contentType == .text && passes($0) }
        case .images:
            return items.filter { $0.contentType == .image && passes($0) }
        case .groups:
            return []
        }
    }

    /// Los dos filtros de sesión juntos: grupo y buscador.
    public func passes(_ item: ClipboardItem) -> Bool {
        passesGroupFilter(item) && matchesSearch(item)
    }

    /// Busca en los **tres campos de texto** del item: el contenido capturado,
    /// el título y la nota. Sin acentos y sin distinguir mayúsculas.
    ///
    /// Un item protegido se busca **solo por título y nota**: su contenido va
    /// cifrado y el buscador no tiene la llave (ni debe pedirla en cada tecla).
    public func matchesSearch(_ item: ClipboardItem) -> Bool {
        let query = searchQuery.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return true }
        let needle = Self.fold(query)
        return [item.isProtected ? nil : item.textContent, item.title, item.detail]
            .compactMap { $0 }
            .contains { Self.fold($0).contains(needle) }
    }

    /// Normaliza para comparar: minúsculas y sin diacríticos.
    private static func fold(_ text: String) -> String {
        text.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
    }

    /// Whether any group filter is currently selected. When false, the filter is
    /// inactive and every item shows — the default, so a fresh popover lists
    /// everything until the user taps a badge to narrow it.
    public var isGroupFilterActive: Bool {
        showUngrouped || groups.contains { $0.isFilterEnabled }
    }

    /// The group filter, applied to **all** items. It behaves like a set of OR
    /// filter chips: with nothing selected every item passes; once at least one
    /// badge is selected, an item passes only if its group is selected (or, for
    /// ungrouped items — which includes every non-favourite, since only
    /// favourites can hold a group — if "Sin grupo" is selected). An item whose
    /// group was deleted is treated as ungrouped.
    public func passesGroupFilter(_ item: ClipboardItem) -> Bool {
        guard isGroupFilterActive else { return true }
        if let gid = item.groupID, let group = groups.first(where: { $0.id == gid }) {
            return group.isFilterEnabled
        }
        return showUngrouped
    }

    private let persistence: PersistenceService
    private let textSealer: ((String) -> String?)?

    /// `false` hasta que `load()` o `adoptInitialState` han puesto en memoria
    /// lo que había en disco. Mientras tanto no se persiste nada: guardar la
    /// lista a medio cargar sobrescribiría el archivo con menos items.
    private var hasLoadedFromDisk = false

    /// `deviceId` dado al crear el store, o `nil` hasta que se lee el de
    /// `DeviceIdentity` (la primera vez que hace falta una marca).
    private var resolvedDeviceId: String?

    /// El aparato con el que este store firma sus cambios.
    public var deviceId: String {
        if let id = resolvedDeviceId { return id }
        let id = DeviceIdentity.current()
        resolvedDeviceId = id
        return id
    }

    /// Marca para un cambio hecho ahora.
    private func newStamp() -> SyncStamp {
        SyncStamp.now(deviceId: deviceId)
    }

    /// `deviceId` solo hace falta para pruebas o para un anfitrión que quiera
    /// fijarlo; por defecto se usa el de `DeviceIdentity`.
    ///
    /// `textSealer` solo existe para las pruebas: sustituye al cifrado con la
    /// `protectedKey` para no tocar el Llavero. La app nunca lo pasa.
    public init(
        persistence: PersistenceService,
        deviceId: String? = nil,
        textSealer: ((String) -> String?)? = nil
    ) {
        self.persistence = persistence
        self.textSealer = textSealer
        self.resolvedDeviceId = deviceId
        // Restore persisted view mode preference.
        if let raw = UserDefaults.standard.string(forKey: "viewMode"),
           let mode = ClipboardViewMode(rawValue: raw) {
            self.viewMode = mode
        }
        // The group filter (showUngrouped + each group's isFilterEnabled) is not
        // restored: it starts empty every launch so the lists open showing all.
    }

    // MARK: - Loading

    public func load() async {
        let loaded = await persistence.load()
        let loadedGroups = await persistence.loadGroups()
        let tombstones = await persistence.loadTombstones()

        // Los tombstones de grupos van aparte: ninguna vista los ve. Los que
        // aún vengan dentro de `groups.enc` (los escribió una build anterior de
        // esta rama) se suman a los de su archivo y el guardado de abajo los
        // saca de `groups.enc`. Si un id está vivo y borrado a la vez, gana el
        // borrado (la regla de la fusión).
        let inlineGroupTombstones = loadedGroups.filter { $0.isDeleted }
        groupTombstones = SyncMerge.merge(local: tombstones.groups, remote: inlineGroupTombstones)
        let deadGroupIDs = Set(groupTombstones.map(\.id))
        let liveGroups = loadedGroups.filter { !$0.isDeleted && !deadGroupIDs.contains($0.id) }
        // Start every launch with the filter unselected (shows all), regardless
        // of whatever selection was last written to groups.json.
        groups = liveGroups.map { var g = $0; g.isFilterEnabled = false; return g }
        let groupsNeedRewrite = liveGroups.count != loadedGroups.count
        if !inlineGroupTombstones.isEmpty { groupTombstonesDirty = true }

        adoptInitialState(loaded, tombstones: tombstones.items)
        if groupsNeedRewrite { persistGroups() }
    }

    /// Pone en memoria lo leído de disco. `tombstones` son los de
    /// `item-tombstones.enc`; también se apartan los que aún vengan mezclados
    /// en `loaded` (de una build anterior de esta rama), y entonces se
    /// reescriben los dos archivos.
    public func adoptInitialState(_ loaded: [ClipboardItem], tombstones: [ClipboardItem] = []) {
        // Items protegidos de versiones anteriores, con el texto aún en claro:
        // se cifran en memoria y los escribe el `persist()` de abajo, de una vez
        // y de forma atómica. Morir a mitad deja el archivo anterior intacto y
        // se repite en el siguiente arranque.
        //
        // Los tombstones se apartan antes que nada; si un id aparece vivo y
        // borrado a la vez, gana el borrado (la regla de la fusión).
        let inline = loaded.filter { $0.isDeleted }
        let allTombstones = SyncMerge.merge(local: tombstones, remote: inline)
        let deadIDs = Set(allTombstones.map(\.id))
        let live = loaded.filter { !$0.isDeleted && !deadIDs.contains($0.id) }
        itemTombstones = allTombstones
        if !inline.isEmpty { itemTombstonesDirty = true }
        let migration = ProtectedTextCipher.sealLegacyProtectedTexts(live)
        // Enforce the per-type limits on load too, so a store that grew past
        // the limit under an older build (or a lowered limit) is normalised.
        items = capAllTypes(sort(migration.items))
        hasLoadedFromDisk = true
        if migration.changed || live.count != loaded.count || itemTombstonesDirty { persist() }
    }

    // MARK: - Texto protegido

    private func protectedPublicKey(sealedTextExists: Bool) -> Curve25519.KeyAgreement.PublicKey? {
        do {
            return try ProtectedKey.shared.publicKey(sealedTextExists: sealedTextExists)
        } catch {
            NSLog("ClipboardManager: sin llave para los elementos protegidos: \(error.localizedDescription)")
            return nil
        }
    }

    /// Cifra el texto de un item protegido. `nil` si no hay llave: quien llama
    /// no debe guardar nada en ese caso.
    private func sealProtectedText(_ text: String) -> String? {
        if let textSealer { return textSealer(text) }
        guard let publicKey = protectedPublicKey(sealedTextExists: items.contains { $0.sealedText != nil }) else {
            return nil
        }
        do {
            return try ProtectedTextCipher.seal(text, to: publicKey)
        } catch {
            NSLog("ClipboardManager: no se pudo cifrar el texto protegido: \(error.localizedDescription)")
            return nil
        }
    }

    /// El texto en claro de un item de texto, si se puede tener sin
    /// preguntar: el de un item normal, o el de uno protegido solo mientras la
    /// ventana de gracia mantiene la llave en memoria.
    private func plainTextIfAvailable(_ item: ClipboardItem) -> String? {
        guard let sealed = item.sealedText else { return item.textContent }
        guard ProtectedAccess.isUnlocked, let privateKey = ProtectedKey.shared.cachedPrivateKey else { return nil }
        return try? ProtectedTextCipher.open(sealed, with: privateKey)
    }

    // MARK: - Mutations

    /// Adds a new item, enforcing the per-type max count (oldest non-favourite drops).
    public func add(_ item: ClipboardItem) {
        guard !isPersistenceBlocked else { return }
        var incoming = item

        // Deduplicate: re-copying an item already in the list (e.g. clicking a
        // row puts it back on the pasteboard, which the monitor then re-reads)
        // must not create a second copy. Drop the old entry so only one remains;
        // the new one takes its place at the top (it has the newest date).
        // Carry over el favorito, el grupo Y la nota de detalle, para que
        // re-copiar un item (p. ej. pulsarlo para pegar) conserve su estrella,
        // su grupo y lo escrito en el editor — si no, la copia recién leída,
        // que no tiene nada de eso, sustituiría a la vieja y el dato guardado a
        // mano desaparecería en silencio.
        //
        // Un item protegido hereda también su texto cifrado (es el mismo texto
        // que el capturado: por eso son duplicados), así que la copia nueva no
        // queda en claro.
        //
        // La captura hereda también el `id` y las marcas del item que
        // sustituye: para la sincronización sigue siendo el mismo registro, y
        // pegar un favorito no lo convierte en un borrado más uno nuevo. Las
        // marcas se fijan con la fecha de creación vieja antes de que la nueva
        // la sustituya (`effectiveStamps`).
        if incoming.contentType == .image { fillMissingImageHashes() }
        if let existing = items.first(where: { isDuplicate($0, of: incoming) }) {
            incoming.id = existing.id
            incoming.stamps = existing.effectiveStamps()
            incoming.imageHash = incoming.imageHash ?? existing.imageHash
            incoming.isFavorite = existing.isFavorite
            incoming.groupID = existing.groupID
            incoming.detail = existing.detail
            incoming.title = existing.title
            incoming.isProtected = existing.isProtected
            if let sealed = existing.sealedText {
                incoming.sealedText = sealed
                incoming.textContent = nil
            }
            purge(id: existing.id)
        }

        // Cap only the type we just added; enforce the count *of that type*,
        // NOT the total across all types (the old bug compared the total item
        // count against a per-type limit, which deleted a freshly-added image
        // whenever the store already held more items than the image limit).
        let capped = cap(items + [incoming], type: incoming.contentType)
        items = sort(capped)
        persist()
    }

    /// True when two items hold the same content (same text, or same image
    /// bytes). Favourite flag and creation date are ignored.
    ///
    /// `b` es la captura nueva (siempre en claro). Contra un item protegido
    /// solo se puede comparar mientras la ventana de gracia tiene la llave en
    /// memoria; fuera de ella **no se deduplica**: la captura entra como item
    /// nuevo del historial y el protegido no cambia. Comparar con un resumen
    /// sin llave permitiría adivinar el texto protegido probando candidatos.
    private func isDuplicate(_ a: ClipboardItem, of b: ClipboardItem) -> Bool {
        guard a.contentType == b.contentType else { return false }
        switch a.contentType {
        case .text:
            guard let incomingText = b.textContent else { return false }
            return plainTextIfAvailable(a) == incomingText
        case .image:
            // Si cualquiera de las dos no se puede leer (archivo que falta, que
            // no descifra), no son duplicadas: dos `nil` iguales harían que
            // `add` borrase la imagen existente.
            guard let x = imageDigest(a), let y = imageDigest(b) else { return false }
            return x == y
        }
    }

    /// Resumen SHA-256 de los bytes ya descifrados de cada imagen, por nombre
    /// de archivo. El archivo cifrado lleva un nonce aleatorio, así que dos
    /// copias de la misma imagen nunca son iguales byte a byte en disco; sin
    /// esta caché, cada imagen copiada descifraría todas las demás. El nombre
    /// es un UUID nuevo por imagen y su archivo no cambia nunca, así que una
    /// entrada no caduca (la de una imagen borrada solo ocupa 64 caracteres). Solo
    /// vive en memoria.
    ///
    /// Es el mismo valor que `ClipboardItem.imageHash` (hexadecimal): si el
    /// item ya lo trae, no se lee el archivo.
    private var imageDigests: [String: String] = [:]

    private func imageDigest(_ item: ClipboardItem) -> String? {
        if let hash = item.imageHash { return hash }
        guard let filename = item.imageFilename else { return nil }
        if let cached = imageDigests[filename] { return cached }
        guard let data = ImageStorage.readData(filename: filename) else { return nil }
        let digest = ImageStorage.sha256Hex(data)
        imageDigests[filename] = digest
        return digest
    }

    /// Rellena `imageHash` en las imágenes guardadas antes de que existiera.
    /// Se llama al capturar una imagen, cuando la deduplicación las iba a
    /// descifrar de todos modos; lo guarda el `persist()` de `add`. Una imagen
    /// cuyo archivo no se puede leer se queda sin hash y se reintenta la
    /// próxima vez.
    private func fillMissingImageHashes() {
        for idx in items.indices where items[idx].contentType == .image && items[idx].imageHash == nil {
            if let hash = imageDigest(items[idx]) {
                items[idx].imageHash = hash
            }
        }
    }

    /// Removes an item from the list and deletes its image file, without
    /// triggering a persist (the caller persists after the surrounding change).
    private func purge(id: ClipboardItem.ID) {
        let toRemove = items.first { $0.id == id }
        items.removeAll { $0.id == id }
        if let filename = toRemove?.imageFilename {
            ImageStorage.delete(filename: filename)
        }
    }

    /// Maximum **non-favourite** items allowed for a given content type.
    private func maxCount(for contentType: ClipboardContentType) -> Int {
        switch contentType {
        case .text:  return maxTextItems
        case .image: return maxImageItems
        }
    }

    /// Drops oldest non-favourite items of `type` until the **non-favourites**
    /// of that type are within the limit. Favourites are not counted and never
    /// dropped: they can be hundreds without eating the history budget (the old
    /// behaviour counted them, so a list full of favourites left no room at all
    /// for freshly copied items). Deletes the image file of any dropped item.
    private func cap(_ list: [ClipboardItem], type: ClipboardContentType) -> [ClipboardItem] {
        var result = list
        let limit = maxCount(for: type)
        while result.filter({ $0.contentType == type && !$0.isFavorite }).count > limit {
            guard let drop = result
                .filter({ $0.contentType == type && !$0.isFavorite })
                .min(by: { $0.createdAt < $1.createdAt })
            else { break }
            result.removeAll { $0.id == drop.id }
            retire(drop)
        }
        return result
    }

    /// Lo que pasa con un item que sale de la lista (borrado, tope, vaciado):
    /// se borra su imagen del disco y, si es o fue favorito
    /// (`leavesTombstone`), queda su tombstone para la sincronización. El
    /// historial que nunca fue favorito desaparece sin rastro, como siempre.
    /// Quien llama lo quita de `items` y persiste.
    private func retire(_ item: ClipboardItem) {
        if let filename = item.imageFilename {
            ImageStorage.delete(filename: filename)
        }
        if item.leavesTombstone {
            itemTombstones.append(item.tombstone(newStamp()))
            itemTombstonesDirty = true
        }
    }

    /// Applies `cap` to every content type.
    private func capAllTypes(_ list: [ClipboardItem]) -> [ClipboardItem] {
        var result = list
        for type in [ClipboardContentType.text, .image] {
            result = cap(result, type: type)
        }
        return result
    }

    /// Removes a single item by id. Also deletes the image file from disk
    /// if the item was an image.
    public func remove(id: ClipboardItem.ID) {
        let before = items.count
        // Grab the item before removing it so we can clean up its file.
        let toRemove = items.first { $0.id == id }
        items.removeAll { $0.id == id }
        guard items.count != before, let removed = toRemove else { return }
        // Borra la imagen y, si era del conjunto sincronizado, deja tombstone.
        retire(removed)
        persist()
    }

    /// Toggles the favourite flag on an item. Un-favouriting also removes the
    /// item from any group, since group membership implies "favourite".
    public func toggleFavorite(id: ClipboardItem.ID) {
        guard let idx = items.firstIndex(where: { $0.id == id }) else { return }
        let stamp = newStamp()
        items[idx].isFavorite.toggle()
        items[idx].stamps.favorite = stamp
        // Quitar la estrella saca el item del conjunto sincronizado: para los
        // demás aparatos desaparece (`hasLeftSyncedSet`); aquí sigue en el
        // historial hasta que el tope lo recicle, y entonces deja tombstone.
        if !items[idx].isFavorite && items[idx].groupID != nil {
            items[idx].groupID = nil
            items[idx].stamps.group = stamp
        }
        items = sort(items)
        persist()
    }

    /// Rewrites the captured text of a text item (the right-click editor). Stored
    /// verbatim — only the emptiness check is trimmed, and a blank result is
    /// rejected rather than leaving a ghost row. Neither the date nor the order
    /// change: editing shouldn't bump an item to the top. Un item protegido
    /// sigue protegido y su texto nuevo se guarda cifrado.
    public func setTextContent(id: ClipboardItem.ID, text: String) {
        guard let item = items.first(where: { $0.id == id }) else { return }
        setText(id: id, text: text, isProtected: item.isProtected, title: item.title ?? "")
    }

    /// Guarda de una vez el texto, la protección y el título de un item de
    /// texto (lo que hace Guardar en el editor). Con `isProtected` el texto se
    /// cifra con la `protectedKey` y no queda en claro ni en memoria; sin él se
    /// guarda en claro y se descarta el cifrado.
    ///
    /// Si cambia algo de verdad (texto, protección o título), el item se hace
    /// favorito (con su marca); sin cambios no se toca, y quitar la estrella
    /// nunca es automático.
    ///
    /// Devuelve `false` sin tocar nada si el texto está en blanco, si se
    /// protege sin título o si no hay llave para cifrar: nunca se guarda en
    /// claro un texto que se pidió proteger.
    @discardableResult
    public func setText(id: ClipboardItem.ID, text: String, isProtected: Bool, title: String) -> Bool {
        guard let idx = items.firstIndex(where: { $0.id == id }),
              items[idx].contentType == .text,
              !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return false }
        let trimmedTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        if isProtected && trimmedTitle.isEmpty { return false }

        // Qué cambia de verdad, para marcar solo esos campos. Si no se puede
        // leer el texto anterior (protegido sin la ventana de gracia abierta),
        // se da por cambiado.
        let before = items[idx]
        let newTitle: String? = trimmedTitle.isEmpty ? nil : trimmedTitle
        let contentChanged = plainTextIfAvailable(before) != text
        let protectionChanged = before.isProtected != isProtected
        let titleChanged = before.title != newTitle

        if isProtected {
            guard let sealed = sealProtectedText(text) else { return false }
            items[idx].sealedText = sealed
            items[idx].textContent = nil
        } else {
            items[idx].textContent = text
            items[idx].sealedText = nil
        }
        items[idx].isProtected = isProtected
        items[idx].title = newTitle

        let stamp = newStamp()
        // Cualquier cambio real hecho desde el editor lo hace favorito: solo
        // los favoritos escapan al tope del historial. Sin cambios no se toca.
        if contentChanged || protectionChanged || titleChanged {
            markFavouriteIfNeeded(idx: idx, stamp: stamp)
        }
        if contentChanged || protectionChanged { items[idx].stamps.content = stamp }
        if protectionChanged { items[idx].stamps.protection = stamp }
        if titleChanged { items[idx].stamps.title = stamp }
        items = sort(items)
        persist()
        return true
    }

    /// Sets (or clears) the free-text detail note on an item. Whitespace-only
    /// input clears the note (stored as `nil`). Un cambio real hace favorito al
    /// item (y reordena); sin cambios no se toca nada.
    public func setDetail(id: ClipboardItem.ID, detail: String) {
        guard let idx = items.firstIndex(where: { $0.id == id }) else { return }
        let trimmed = detail.trimmingCharacters(in: .whitespacesAndNewlines)
        let newDetail: String? = trimmed.isEmpty ? nil : trimmed
        if items[idx].detail != newDetail {
            let stamp = newStamp()
            items[idx].detail = newDetail
            items[idx].stamps.detail = stamp
            markFavouriteIfNeeded(idx: idx, stamp: stamp)
            items = sort(items)
        }
        persist()
    }

    /// Hace favorito el item de `idx` si no lo era, sellando solo ese campo.
    /// No reordena: quien llama lo hace después.
    private func markFavouriteIfNeeded(idx: Int, stamp: SyncStamp) {
        guard !items[idx].isFavorite else { return }
        items[idx].isFavorite = true
        items[idx].stamps.favorite = stamp
    }

    /// Marca o desmarca un item de texto como protegido, con el título que la
    /// lista enseñará en lugar del contenido.
    ///
    /// **Solo items de texto**: una imagen se revela en su propia miniatura, así
    /// que esconder su texto no protegería nada. Proteger sin título dejaría la
    /// fila sin nada que mostrar, así que se exige título; al desproteger, el
    /// título se conserva por si vuelve a activarse.
    ///
    /// Proteger cifra el texto (no pide autenticación). Desproteger necesita
    /// el texto en claro, así que solo funciona con la ventana de gracia
    /// abierta; el editor usa `setText`, que ya trae el texto. Devuelve `false`
    /// si no ha cambiado nada.
    @discardableResult
    public func setProtection(id: ClipboardItem.ID, isProtected: Bool, title: String) -> Bool {
        guard let item = items.first(where: { $0.id == id }),
              item.contentType == .text,
              let text = plainTextIfAvailable(item) else { return false }
        return setText(id: id, text: text, isProtected: isProtected, title: title)
    }

    /// Crea a mano un item de texto que nunca pasó por el portapapeles (una
    /// contraseña generada, por ejemplo) y lo guarda.
    ///
    /// Nace **favorito**: solo los favoritos escapan al límite por tipo, y si
    /// no, el historial acabaría borrándolo. No pasa por la deduplicación de
    /// `add`: no es una captura, y no debe fundirse con otro item igual.
    /// Se rechaza (devuelve `nil`) un texto en blanco o, si va protegido, sin
    /// título, por las mismas razones que `setTextContent` y `setProtection`; y
    /// también, si va protegido, cuando no hay llave para cifrarlo.
    @discardableResult
    public func addManual(
        title: String,
        text: String,
        detail: String,
        groupID: ClipboardGroup.ID?,
        isProtected: Bool
    ) -> ClipboardItem.ID? {
        guard !isPersistenceBlocked else { return nil }
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }
        let trimmedTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        if isProtected && trimmedTitle.isEmpty { return nil }

        var item = ClipboardItem.text(text)
        item.isFavorite = true
        item.isProtected = isProtected
        if isProtected {
            guard let sealed = sealProtectedText(text) else { return nil }
            item.sealedText = sealed
            item.textContent = nil
        }
        item.title = trimmedTitle.isEmpty ? nil : trimmedTitle
        let note = detail.trimmingCharacters(in: .whitespacesAndNewlines)
        item.detail = note.isEmpty ? nil : note
        if let groupID = groupID, groups.contains(where: { $0.id == groupID }) {
            item.groupID = groupID
        }
        items = sort(items + [item])
        persist()
        return item.id
    }

    /// Clears all non-favourite items. Also deletes their image files from disk.
    public func clearNonFavorites() {
        let before = items.count
        let removed = items.filter { !$0.isFavorite }
        items = items.filter { $0.isFavorite }
        guard items.count != before else { return }
        // Borra sus imágenes; los que fueron favoritos dejan tombstone.
        for item in removed { retire(item) }
        persist()
    }

    /// Clears all non-favourite items of a single content type, leaving
    /// favourites and the other type untouched. Deletes any removed image files.
    public func clearNonFavorites(ofType type: ClipboardContentType) {
        let removed = items.filter { $0.contentType == type && !$0.isFavorite }
        guard !removed.isEmpty else { return }
        let removedIDs = Set(removed.map(\.id))
        items.removeAll { removedIDs.contains($0.id) }
        for item in removed { retire(item) }
        persist()
    }

    // MARK: - Groups

    /// Creates a new group with the given name (trimmed). Returns its id, or
    /// nil if the name is blank. Duplicate names are allowed (ids are unique).
    @discardableResult
    public func addGroup(name: String) -> UUID? {
        guard !isPersistenceBlocked else { return nil }
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        let group = ClipboardGroup(name: trimmed)
        groups.append(group)
        persistGroups()
        return group.id
    }

    /// Renames a group. No-op if the id is unknown or the name is blank.
    public func renameGroup(id: ClipboardGroup.ID, to name: String) {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        guard let idx = groups.firstIndex(where: { $0.id == id }) else { return }
        guard groups[idx].name != trimmed else { return }
        groups[idx].name = trimmed
        groups[idx].nameStamp = newStamp()
        persistGroups()
    }

    /// Deletes a group. Items assigned to it are kept and become ungrouped
    /// (their content — text/passwords and images — is untouched).
    ///
    /// Todos los grupos se sincronizan, así que borrar uno siempre deja su
    /// tombstone en `groupTombstones`.
    public func deleteGroup(id: ClipboardGroup.ID) {
        guard let group = groups.first(where: { $0.id == id }) else { return }
        let stamp = newStamp()
        groups.removeAll { $0.id == id }
        groupTombstones.append(group.tombstone(stamp))
        groupTombstonesDirty = true
        var itemsChanged = false
        for idx in items.indices where items[idx].groupID == id {
            items[idx].groupID = nil
            items[idx].stamps.group = stamp
            itemsChanged = true
        }
        persistGroups()
        if itemsChanged { persist() }
    }

    /// Toggles a group's filter checkbox (show/hide its favourites in the lists).
    public func toggleGroupFilter(id: ClipboardGroup.ID) {
        guard let idx = groups.firstIndex(where: { $0.id == id }) else { return }
        groups[idx].isFilterEnabled.toggle()
        persistGroups()
    }

    /// Clears the whole group filter selection (every chip off) so the lists
    /// show everything again. No-op — and no persist — when nothing is selected.
    public func clearGroupFilter() {
        guard isGroupFilterActive else { return }
        showUngrouped = false
        for idx in groups.indices where groups[idx].isFilterEnabled {
            groups[idx].isFilterEnabled = false
        }
        persistGroups()
    }

    /// Assigns an item to a group (or removes it from any group when `groupID`
    /// is nil). Assigning to a group also marks the item as a favourite, so it
    /// survives the per-type cap. Removing the group leaves the favourite flag
    /// untouched.
    public func assignGroup(itemID: ClipboardItem.ID, groupID: ClipboardGroup.ID?) {
        guard let idx = items.firstIndex(where: { $0.id == itemID }) else { return }
        // Ignore unknown group ids.
        if let gid = groupID, !groups.contains(where: { $0.id == gid }) { return }
        let stamp = newStamp()
        if items[idx].groupID != groupID {
            items[idx].groupID = groupID
            items[idx].stamps.group = stamp
        }
        if groupID != nil && !items[idx].isFavorite {
            items[idx].isFavorite = true
            items[idx].stamps.favorite = stamp
        }
        items = sort(items)
        persist()
    }

    // MARK: - Sorting

    /// Favourites first (descending date), then the rest (descending date).
    private func sort(_ list: [ClipboardItem]) -> [ClipboardItem] {
        list.sorted { a, b in
            if a.isFavorite != b.isFavorite {
                return a.isFavorite && !b.isFavorite
            }
            return a.createdAt > b.createdAt
        }
    }

    // MARK: - Persistence

    /// `true` si la persistencia se ha bloqueado al leer (datos que no se
    /// pudieron abrir). Entonces el store no añade nada ni guarda: el
    /// historial en memoria está vacío y escribirlo pisaría el de disco. Así
    /// un anfitrión que no mire `blockingError` tampoco captura a ciegas.
    public var isPersistenceBlocked: Bool {
        persistence.blockingError != nil
    }

    /// Encola el guardado desde el hilo principal, sin `Task` de por medio:
    /// así dos cambios seguidos se escriben en el orden en que ocurrieron y
    /// una foto vieja nunca pisa a la nueva.
    ///
    /// Los tombstones van a su propio archivo y se encolan **antes** que los
    /// vivos: si la app muere entre las dos escrituras, al arrancar hay un id
    /// vivo y borrado a la vez, y gana el borrado; al revés, el borrado se
    /// perdería sin rastro.
    private func persist() {
        guard hasLoadedFromDisk, !isPersistenceBlocked else { return }
        if itemTombstonesDirty {
            persistence.enqueueSaveItemTombstones(itemTombstones)
            itemTombstonesDirty = false
        }
        persistence.enqueueSave(items)
    }

    private func persistGroups() {
        guard hasLoadedFromDisk, !isPersistenceBlocked else { return }
        if groupTombstonesDirty {
            persistence.enqueueSaveGroupTombstones(groupTombstones)
            groupTombstonesDirty = false
        }
        persistence.enqueueSaveGroups(groups)
    }
}