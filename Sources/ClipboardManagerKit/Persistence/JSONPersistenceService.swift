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

    private let fileURL: URL
    private let groupsURL: URL
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

        self.fileURL = dir.appendingPathComponent("store.json")
        self.groupsURL = dir.appendingPathComponent("groups.json")
    }

    /// For testing with a custom URL. The groups file sits alongside it.
    public init(fileURL: URL) {
        self.fileURL = fileURL
        self.groupsURL = fileURL.deletingLastPathComponent().appendingPathComponent("groups.json")
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
                let items = self.readFile(self.fileURL, as: [ClipboardItem].self) ?? []
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

    // MARK: - Groups

    public func loadGroups() async -> [ClipboardGroup] {
        await withCheckedContinuation { continuation in
            queue.async { [weak self] in
                guard let self = self else {
                    continuation.resume(returning: [])
                    return
                }
                let groups = self.readFile(self.groupsURL, as: [ClipboardGroup].self) ?? []
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

    // MARK: - Lectura y escritura cifradas (siempre en `queue`)

    private func currentKey() throws -> SymmetricKey {
        try LocalKey.shared.key(alsoChecking: [fileURL, groupsURL])
    }

    /// Lee y decodifica un archivo. `nil` si no existe (primer arranque) o si
    /// no se pudo leer, en cuyo caso el servicio queda bloqueado. Un archivo en
    /// claro de una versión anterior se decodifica y se migra a cifrado.
    private func readFile<T: Decodable>(_ url: URL, as type: T.Type) -> T? {
        let raw: Data
        do {
            raw = try Data(contentsOf: url)
        } catch let error as CocoaError where error.code == .fileReadNoSuchFile {
            return nil
        } catch {
            block(url, error)
            return nil
        }

        do {
            if FileCipher.isEncrypted(raw) {
                let plaintext = try FileCipher.open(raw, using: currentKey())
                return try decoder.decode(T.self, from: plaintext)
            }
            // Formato heredado: JSON en claro. Primero se comprueba que se lee
            // bien; solo entonces se cifra.
            let value = try decoder.decode(T.self, from: raw)
            try migrateToEncrypted(url, plaintext: raw)
            return value
        } catch {
            block(url, error)
            return nil
        }
    }

    /// Codifica, cifra y escribe de forma atómica. Nunca escribe en claro y
    /// nunca escribe si el servicio está bloqueado.
    private func writeFile<T: Encodable>(_ url: URL, value: T) throws {
        guard !isBlocked else { throw PersistenceError.writesBlocked }
        let json = try encoder.encode(value)
        let sealed = try FileCipher.seal(json, using: currentKey())
        try sealed.write(to: url, options: .atomic)
    }

    /// Migra un archivo en claro: cifra en un temporal oculto de la misma
    /// carpeta, lo vuelve a leer, comprueba que descifra a los mismos bytes y
    /// solo entonces lo pone en el sitio del original con `rename` (atómico en
    /// el mismo volumen). Si la app muere a mitad, el original sigue en claro e
    /// intacto y la migración se repite en el siguiente arranque. No queda
    /// ninguna copia en claro aparte.
    private func migrateToEncrypted(_ url: URL, plaintext: Data) throws {
        let key = try currentKey()
        let sealed = try FileCipher.seal(plaintext, using: key)
        let temporary = url.deletingLastPathComponent()
            .appendingPathComponent(".\(url.lastPathComponent)\(JSONPersistenceService.migratingSuffix)")
        let fileManager = FileManager.default
        try? fileManager.removeItem(at: temporary)
        do {
            try sealed.write(to: temporary)
            let readBack = try Data(contentsOf: temporary)
            guard try FileCipher.open(readBack, using: key) == plaintext else {
                throw PersistenceError.migrationVerificationFailed(name: url.lastPathComponent)
            }
            guard rename(temporary.path, url.path) == 0 else {
                throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO)
            }
        } catch {
            try? fileManager.removeItem(at: temporary)
            throw error
        }
        NSLog("ClipboardManager: \(url.lastPathComponent) migrado a formato cifrado")
    }

    private static let migratingSuffix = ".migrating"

    /// Cifra los PNG en claro que queden en `images/` (también los huérfanos)
    /// y borra los temporales de una migración interrumpida. Un fallo en una
    /// imagen no bloquea nada: se queda en claro, se sigue leyendo y se
    /// reintenta en el siguiente arranque.
    private func migrateImages() {
        guard let directory = ImageStorage.directoryURL else { return }
        let fileManager = FileManager.default
        let names = (try? fileManager.contentsOfDirectory(atPath: directory.path)) ?? []
        for name in names {
            let url = directory.appendingPathComponent(name)
            if name.hasPrefix(".") {
                if name.hasSuffix(JSONPersistenceService.migratingSuffix) {
                    try? fileManager.removeItem(at: url)
                }
                continue
            }
            guard let raw = try? Data(contentsOf: url), !raw.isEmpty, !FileCipher.isEncrypted(raw) else {
                continue
            }
            do {
                try migrateToEncrypted(url, plaintext: raw)
            } catch {
                NSLog("ClipboardManager: no se pudo cifrar la imagen \(name): \(error.localizedDescription)")
            }
        }
    }
}
