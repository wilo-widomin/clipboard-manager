//
//  PersistenceService.swift
//  ClipboardManager
//
//  Protocol + JSON implementation for loading/saving clipboard items.
//
//  Los archivos se escriben cifrados (AES-256-GCM con la `localKey`, ver
//  `FileCipher` y `LocalKey`). En memoria todo sigue en claro: el cifrado vive
//  solo aquí, en el borde con el disco.
//
//  Nombres en disco: `store.enc` y `groups.enc`. Los cifrados **no** se llaman
//  `store.json`/`groups.json` a propósito: una versión anterior de la app (sin
//  cifrado) que se abra después de migrar no encuentra su archivo, arranca con
//  el historial vacío y escribe un `store.json` nuevo en claro, en vez de tomar
//  el cifrado por corrupto y pisarlo. En el siguiente arranque de esta versión
//  ese `store.json` se funde con `store.enc` y se borra (ver `loadMerging`).
//
//  Regla de oro: si algo existente no se puede leer (llave ausente, descifrado
//  que falla, JSON roto), el servicio **se bloquea**: no vuelve a escribir
//  ningún archivo y lo dice en `blockingError`. Perder datos es peor que no
//  arrancar.
//

import Foundation
import CryptoKit

/// Abstraction over the persistence backend (injectable for testing).
public protocol PersistenceService: Sendable {
    func load() async -> [ClipboardItem]
    func save(_ items: [ClipboardItem]) async throws
    func loadGroups() async -> [ClipboardGroup]
    func saveGroups(_ groups: [ClipboardGroup]) async throws

    /// El primer error que bloqueó la escritura, o `nil` si todo se leyó bien.
    /// Con un valor distinto de `nil` el historial en memoria está vacío pero
    /// los archivos siguen intactos en disco: `ClipboardStore` deja de añadir y
    /// de guardar, y el anfitrión debe avisar y no seguir capturando.
    var blockingError: Error? { get }

    /// Encola el guardado de los items **sin esperar** y respetando el orden de
    /// llamada: dos guardados seguidos llegan al disco en el mismo orden en que
    /// se pidieron, así que una foto vieja nunca pisa a una nueva. Los errores
    /// solo se registran. Es lo que usa `ClipboardStore` desde el hilo
    /// principal.
    func enqueueSave(_ items: [ClipboardItem])
    /// Lo mismo que `enqueueSave(_:)` para los grupos.
    func enqueueSaveGroups(_ groups: [ClipboardGroup])
}

/// Implementación por defecto para servicios escritos antes de existir
/// `enqueueSave`: llama al `save` asíncrono en una `Task`. **No** garantiza el
/// orden; un servicio con una cola propia debe sobrescribirla.
public extension PersistenceService {
    func enqueueSave(_ items: [ClipboardItem]) {
        Task {
            do {
                try await save(items)
            } catch {
                NSLog("ClipboardManager: failed to persist: \(error.localizedDescription)")
            }
        }
    }

    func enqueueSaveGroups(_ groups: [ClipboardGroup]) {
        Task {
            do {
                try await saveGroups(groups)
            } catch {
                NSLog("ClipboardManager: failed to persist groups: \(error.localizedDescription)")
            }
        }
    }
}

/// Errores propios de la persistencia.
public enum PersistenceError: Error, LocalizedError {
    /// Un archivo existente no se pudo leer y el servicio ha dejado de escribir.
    case unreadableFile(name: String, underlying: Error)
    /// El archivo cifrado recién escrito no devolvía los mismos bytes al leerlo.
    case migrationVerificationFailed(name: String)
    /// Se ha pedido guardar estando bloqueado.
    case writesBlocked

    public var errorDescription: String? {
        switch self {
        case .unreadableFile(let name, let underlying):
            return "No se pudo leer \(name): \(underlying.localizedDescription)"
        case .migrationVerificationFailed(let name):
            return "Al cifrar \(name), la copia cifrada no coincidía con el original. Se ha dejado el original como estaba."
        case .writesBlocked:
            return "La escritura está bloqueada porque los datos existentes no se pudieron leer."
        }
    }
}

/// JSON-file based persistence. Reads/writes an array of ClipboardItem to a
/// file in the app's Application Support directory, cifrado.
public final class JSONPersistenceService: PersistenceService, @unchecked Sendable {

    /// `store.enc`: los items, cifrados.
    private let fileURL: URL
    /// `groups.enc`: los grupos, cifrados.
    private let groupsURL: URL
    /// `store.json`: el nombre de siempre. Lo dejan una versión anterior (en
    /// claro) o una build sin publicar de §3.1 (ya cifrado). Si existe, se funde
    /// en `store.enc` y se borra.
    private let legacyFileURL: URL
    /// `groups.json`: lo mismo para los grupos.
    private let legacyGroupsURL: URL

    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()
    private let queue = DispatchQueue(label: "com.clipboardmanager.persistence", qos: .utility)

    private let stateLock = NSLock()
    private var firstBlockingError: Error?

    public init() {
        let appSupport = FileManager.default.urls(
            for: .applicationSupportDirectory, in: .userDomainMask
        ).first!
        let dir = appSupport.appendingPathComponent("ClipboardManager", isDirectory: true)
        // Ensure the directory exists.
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)

        self.fileURL = dir.appendingPathComponent("store.enc")
        self.groupsURL = dir.appendingPathComponent("groups.enc")
        self.legacyFileURL = dir.appendingPathComponent("store.json")
        self.legacyGroupsURL = dir.appendingPathComponent("groups.json")
    }

    /// For testing with a custom URL. `fileURL` da el nombre base: los items
    /// cifrados van en `<base>.enc`, el heredado se busca en `<base>.json` y los
    /// grupos en `groups.enc` / `groups.json` de la misma carpeta.
    public init(fileURL: URL) {
        let base = fileURL.deletingPathExtension()
        let dir = fileURL.deletingLastPathComponent()
        self.fileURL = base.appendingPathExtension("enc")
        self.legacyFileURL = base.appendingPathExtension("json")
        self.groupsURL = dir.appendingPathComponent("groups.enc")
        self.legacyGroupsURL = dir.appendingPathComponent("groups.json")
    }

    // MARK: - Estado de bloqueo

    /// El primer error que bloqueó la escritura, o `nil` si todo se leyó bien.
    /// Un anfitrión debe mirarlo después de `load()`/`loadGroups()` y, si no es
    /// `nil`, avisar y no seguir: el historial que ve está vacío pero los
    /// archivos siguen intactos en disco.
    public var blockingError: Error? {
        stateLock.lock()
        defer { stateLock.unlock() }
        return firstBlockingError
    }

    private func block(_ url: URL, _ error: Error) {
        NSLog("ClipboardManager: \(url.lastPathComponent) no se puede leer; se bloquea la escritura: \(error.localizedDescription)")
        // Las imágenes también dejan de escribirse: sin historial no hay quién
        // las referencie.
        ImageStorage.blockWrites()
        stateLock.lock()
        defer { stateLock.unlock() }
        if firstBlockingError == nil {
            firstBlockingError = PersistenceError.unreadableFile(name: url.lastPathComponent, underlying: error)
        }
    }

    private var isBlocked: Bool { blockingError != nil }

    // MARK: - Items

    public func load() async -> [ClipboardItem] {
        await withCheckedContinuation { continuation in
            queue.async { [weak self] in
                guard let self = self else {
                    continuation.resume(returning: [])
                    return
                }
                // Copias en claro que Quick Look dejara de la sesión anterior.
                QuickLookTemporaryFiles.purge()
                self.removeStaleTemporaries(in: self.fileURL.deletingLastPathComponent())
                let items = self.loadMerging(
                    current: self.fileURL,
                    legacy: self.legacyFileURL,
                    as: ClipboardItem.self,
                    prepare: { ProtectedTextCipher.sealLegacyProtectedTexts($0).items }
                )
                if !self.isBlocked {
                    self.migrateImages()
                }
                continuation.resume(returning: items)
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
                    try self.writeFile(self.fileURL, value: items)
                    continuation.resume()
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }

    /// Encola la escritura en la cola serie **ya**, en el hilo de quien llama:
    /// el orden de las llamadas es el orden de las escrituras.
    public func enqueueSave(_ items: [ClipboardItem]) {
        queue.async { [weak self] in
            guard let self = self else { return }
            do {
                try self.writeFile(self.fileURL, value: items)
            } catch {
                NSLog("ClipboardManager: failed to persist: \(error.localizedDescription)")
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
                let groups = self.loadMerging(
                    current: self.groupsURL,
                    legacy: self.legacyGroupsURL,
                    as: ClipboardGroup.self
                )
                continuation.resume(returning: groups)
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
                    try self.writeFile(self.groupsURL, value: groups)
                    continuation.resume()
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }

    /// Lo mismo que `enqueueSave(_:)` para los grupos.
    public func enqueueSaveGroups(_ groups: [ClipboardGroup]) {
        queue.async { [weak self] in
            guard let self = self else { return }
            do {
                try self.writeFile(self.groupsURL, value: groups)
            } catch {
                NSLog("ClipboardManager: failed to persist groups: \(error.localizedDescription)")
            }
        }
    }

    // MARK: - Lectura, fusión y escritura cifradas (siempre en `queue`)

    private func currentKey() throws -> SymmetricKey {
        try LocalKey.shared.key(alsoChecking: [fileURL, groupsURL, legacyFileURL, legacyGroupsURL])
    }

    /// Lee la lista cifrada (`current`) y, si además existe el archivo con el
    /// nombre antiguo (`legacy`), la funde con él:
    ///
    /// - Solo `current`: se devuelve tal cual (el caso normal).
    /// - Solo `legacy`, en claro: la migración de una versión anterior.
    /// - Solo `legacy`, ya cifrado: lo dejó una build sin publicar que escribía
    ///   cifrado con el nombre antiguo.
    /// - Los dos: una versión anterior se abrió después de migrar y creó un
    ///   archivo nuevo. No se pierde ninguno: se suman los elementos de `legacy`
    ///   cuyo `id` no está ya en `current`.
    ///
    /// Con `legacy` presente, el resultado (pasado por `prepare`) se escribe
    /// cifrado en `current`, se relee y se comprueba, y solo entonces se borra
    /// `legacy`. Si la app muere a mitad, `legacy` sigue ahí y la fusión se
    /// repite (por `id`, así que repetirla no duplica nada). Cualquier fallo de
    /// lectura bloquea el servicio y devuelve una lista vacía sin tocar disco.
    private func loadMerging<T: Codable & Identifiable>(
        current: URL,
        legacy: URL,
        as type: T.Type,
        prepare: ([T]) -> [T] = { $0 }
    ) -> [T] {
        let currentList = readEncrypted(current, as: [T].self)
        if isBlocked { return [] }
        let legacyList = readLegacy(legacy, as: [T].self)
        if isBlocked { return [] }
        guard let legacyList = legacyList else { return currentList ?? [] }

        let base = currentList ?? []
        let knownIDs = Set(base.map { $0.id })
        let added = legacyList.filter { !knownIDs.contains($0.id) }
        let merged = prepare(base + added)

        do {
            let key = try currentKey()
            let json = try encoder.encode(merged)
            let sealed = try FileCipher.seal(json, using: key)
            try Self.writeDurably(sealed, to: current) { readBack in
                guard try FileCipher.open(readBack, using: key) == json else {
                    throw PersistenceError.migrationVerificationFailed(name: legacy.lastPathComponent)
                }
            }
        } catch {
            block(legacy, error)
            return []
        }

        do {
            try FileManager.default.removeItem(at: legacy)
        } catch {
            // `current` ya lo tiene todo; la próxima vez se vuelve a fundir.
            NSLog("ClipboardManager: no se pudo borrar \(legacy.lastPathComponent) tras pasarlo a \(current.lastPathComponent): \(error.localizedDescription)")
        }
        if currentList == nil {
            NSLog("ClipboardManager: \(legacy.lastPathComponent) migrado a \(current.lastPathComponent) (cifrado)")
        } else {
            NSLog("ClipboardManager: \(legacy.lastPathComponent) fundido en \(current.lastPathComponent): \(added.count) elementos nuevos")
        }
        return merged
    }

    /// Los bytes de un archivo, o `nil` si no existe. Cualquier otro error al
    /// leerlo bloquea el servicio (y también devuelve `nil`).
    private func readRaw(_ url: URL) -> Data? {
        do {
            return try Data(contentsOf: url)
        } catch let error as CocoaError where error.code == .fileReadNoSuchFile {
            return nil
        } catch {
            block(url, error)
            return nil
        }
    }

    /// Lee un archivo que tiene que estar cifrado (`store.enc`, `groups.enc`).
    /// `nil` si no existe o si no se pudo leer (y entonces bloquea).
    private func readEncrypted<T: Decodable>(_ url: URL, as type: T.Type) -> T? {
        guard let raw = readRaw(url) else { return nil }
        do {
            let plaintext = try FileCipher.open(raw, using: currentKey())
            return try decoder.decode(T.self, from: plaintext)
        } catch {
            block(url, error)
            return nil
        }
    }

    /// Lee un archivo con el nombre antiguo, en claro o ya cifrado. `nil` si no
    /// existe o si no se pudo leer (y entonces bloquea).
    private func readLegacy<T: Decodable>(_ url: URL, as type: T.Type) -> T? {
        guard let raw = readRaw(url) else { return nil }
        do {
            let json = FileCipher.isEncrypted(raw) ? try FileCipher.open(raw, using: currentKey()) : raw
            return try decoder.decode(T.self, from: json)
        } catch {
            block(url, error)
            return nil
        }
    }

    /// Codifica, cifra y escribe de forma atómica y llevada al disco. Nunca
    /// escribe en claro y nunca escribe si el servicio está bloqueado.
    private func writeFile<T: Encodable>(_ url: URL, value: T) throws {
        guard !isBlocked else { throw PersistenceError.writesBlocked }
        let json = try encoder.encode(value)
        let sealed = try FileCipher.seal(json, using: currentKey())
        try Self.writeDurably(sealed, to: url)
    }

    // MARK: - Escritura durable

    /// Sufijo de los temporales de escritura. Cada uno lleva además un UUID en
    /// el nombre, para que dos instancias (la app suelta y Widomin) no se pisen.
    private static let temporarySuffix = ".migrating"

    /// Un temporal más viejo que esto es de una escritura que murió a mitad.
    private static let staleTemporaryAge: TimeInterval = 10 * 60

    /// Escribe `data` en un temporal oculto de la misma carpeta, lo lleva al
    /// disco físico (`F_FULLFSYNC`), opcionalmente lo relee y lo comprueba con
    /// `verify`, y solo entonces lo pone en el sitio de `destination` con
    /// `rename` (atómico en el mismo volumen). Después sincroniza la carpeta
    /// para que el cambio de nombre sobreviva a un corte de luz. Si algo falla,
    /// borra el temporal y `destination` queda como estaba.
    private static func writeDurably(_ data: Data, to destination: URL, verify: ((Data) throws -> Void)? = nil) throws {
        let directory = destination.deletingLastPathComponent()
        let temporary = directory.appendingPathComponent(
            ".\(destination.lastPathComponent).\(UUID().uuidString)\(temporarySuffix)"
        )
        let fileManager = FileManager.default
        guard fileManager.createFile(atPath: temporary.path, contents: nil, attributes: [.posixPermissions: 0o600]) else {
            throw CocoaError(.fileWriteUnknown)
        }
        do {
            let handle = try FileHandle(forWritingTo: temporary)
            do {
                try handle.write(contentsOf: data)
                try fullSync(handle.fileDescriptor)
                try handle.close()
            } catch {
                try? handle.close()
                throw error
            }
            if let verify = verify {
                try verify(try Data(contentsOf: temporary))
            }
            guard rename(temporary.path, destination.path) == 0 else {
                throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO)
            }
        } catch {
            try? fileManager.removeItem(at: temporary)
            throw error
        }
        syncDirectory(directory)
    }

    /// `F_FULLFSYNC` pide al disco que vacíe también su caché; un `fsync` en
    /// macOS solo llega hasta la controladora. Si el volumen no lo admite (algún
    /// disco de red), se cae a `fsync`.
    private static func fullSync(_ descriptor: Int32) throws {
        if fcntl(descriptor, F_FULLFSYNC) != -1 { return }
        guard fsync(descriptor) == 0 else {
            throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO)
        }
    }

    /// Sincroniza la entrada de la carpeta (el `rename`). Sin éxito no pasa
    /// nada grave: el archivo ya está en disco, como mucho con el nombre viejo.
    private static func syncDirectory(_ directory: URL) {
        let descriptor = open(directory.path, O_RDONLY)
        guard descriptor >= 0 else { return }
        _ = fsync(descriptor)
        close(descriptor)
    }

    /// Borra los temporales de escritura de `directory` que llevan más de diez
    /// minutos ahí: los de una escritura interrumpida. Los recientes pueden ser
    /// de otra instancia que está escribiendo ahora mismo y no se tocan.
    private func removeStaleTemporaries(in directory: URL) {
        let fileManager = FileManager.default
        let names = (try? fileManager.contentsOfDirectory(atPath: directory.path)) ?? []
        let cutoff = Date().addingTimeInterval(-Self.staleTemporaryAge)
        for name in names where name.hasPrefix(".") && name.hasSuffix(Self.temporarySuffix) {
            let url = directory.appendingPathComponent(name)
            guard let modified = (try? fileManager.attributesOfItem(atPath: url.path))?[.modificationDate] as? Date,
                  modified < cutoff else { continue }
            try? fileManager.removeItem(at: url)
        }
    }

    // MARK: - Imágenes

    /// Cifra los PNG en claro que queden en `images/` (también los huérfanos)
    /// y borra los temporales viejos de una migración interrumpida. Para saber
    /// si una imagen ya está cifrada solo lee su cabecera. Un fallo en una
    /// imagen no bloquea nada: se queda en claro, se sigue leyendo y se
    /// reintenta en el siguiente arranque.
    ///
    /// Las imágenes conservan su nombre: una versión anterior de la app nunca
    /// reescribe un archivo de imagen existente (cada captura usa un UUID nuevo
    /// y solo borra las de sus propios items), así que no puede pisarlas.
    private func migrateImages() {
        guard let directory = ImageStorage.directoryURL else { return }
        removeStaleTemporaries(in: directory)
        let fileManager = FileManager.default
        let names = (try? fileManager.contentsOfDirectory(atPath: directory.path)) ?? []
        for name in names where !name.hasPrefix(".") {
            let url = directory.appendingPathComponent(name)
            if FileCipher.fileIsEncrypted(at: url) { continue }
            guard let raw = try? Data(contentsOf: url), !raw.isEmpty, !FileCipher.isEncrypted(raw) else {
                continue
            }
            do {
                let key = try currentKey()
                let sealed = try FileCipher.seal(raw, using: key)
                try Self.writeDurably(sealed, to: url) { readBack in
                    guard try FileCipher.open(readBack, using: key) == raw else {
                        throw PersistenceError.migrationVerificationFailed(name: name)
                    }
                }
                NSLog("ClipboardManager: imagen \(name) migrada a formato cifrado")
            } catch {
                NSLog("ClipboardManager: no se pudo cifrar la imagen \(name): \(error.localizedDescription)")
            }
        }
    }
}
