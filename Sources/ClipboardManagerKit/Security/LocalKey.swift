//
//  LocalKey.swift
//  ClipboardManager
//
//  `localKey`: la llave AES-256 de este Mac con la que se cifran store.json,
//  groups.json y las imágenes. 32 bytes aleatorios, creados la primera vez y
//  guardados en el Keychain como contraseña genérica. Nunca sale del aparato y
//  no es la llave del sync (ver docs/05-blueprint-sync-android.md, §3.1).
//
//  Qué Keychain y por qué:
//
//  - Se usa el **llavero de sesión de siempre** (el «login» de Acceso a
//    Llaveros), con `kSecUseDataProtectionKeychain = false` explícito. El
//    llavero de protección de datos exige que la app lleve el entitlement
//    `keychain-access-groups` / `application-identifier`, que en macOS solo
//    vale con un perfil de aprovisionamiento; `scripts/build-release.sh` firma
//    a mano sin perfil, y ahí `SecItemAdd` devolvería `errSecMissingEntitlement`
//    (-34018). Fijar el llavero explícitamente evita además que un cambio de
//    firma haga buscar la llave en el otro llavero, no encontrarla y crear una
//    nueva (eso dejaría los datos ilegibles).
//  - Se pide `kSecAttrAccessibleWhenUnlockedThisDeviceOnly`, como dice el
//    blueprint, pero en el llavero de sesión macOS no lo aplica: ahí la llave
//    está disponible mientras la sesión de Willy esté abierta, no se sincroniza
//    con iCloud, y el archivo del llavero va cifrado con la contraseña de la
//    sesión (también dentro de Time Machine).
//  - El acceso lo decide la lista de control del elemento, atada a la firma de
//    la app que lo creó. Otra app (Widomin) o una build firmada con otro
//    certificado provoca un aviso del sistema la primera vez («… quiere usar
//    información confidencial…»); con «Permitir siempre» no vuelve a salir.
//
//  El nombre del servicio es fijo y no depende del bundle id: la app suelta y
//  Widomin leen la misma carpeta de datos y tienen que encontrar la misma llave.
//

import Foundation
import Security
import CryptoKit

/// Errores al leer o crear la `localKey`.
public enum LocalKeyError: Error, LocalizedError {
    case keychainRead(OSStatus)
    case keychainWrite(OSStatus)
    case invalidKeyData
    case keyMissingButEncryptedDataExists

    public var errorDescription: String? {
        switch self {
        case .keychainRead(let status):
            return "No se pudo leer la llave del Llavero (\(status): \(LocalKeyError.message(for: status)))."
        case .keychainWrite(let status):
            return "No se pudo guardar la llave en el Llavero (\(status): \(LocalKeyError.message(for: status)))."
        case .invalidKeyData:
            return "La llave guardada en el Llavero no tiene el tamaño esperado."
        case .keyMissingButEncryptedDataExists:
            return "Hay datos cifrados en disco pero su llave no está en el Llavero. No se crea otra para no dejarlos ilegibles."
        }
    }

    private static func message(for status: OSStatus) -> String {
        (SecCopyErrorMessageString(status, nil) as String?) ?? "error desconocido"
    }
}

/// Acceso a la `localKey`, con caché en memoria. Seguro desde cualquier hilo.
final class LocalKey: @unchecked Sendable {

    static let shared = LocalKey()

    /// Servicio del elemento en el Llavero. Fijo y compartido por todos los
    /// anfitriones del paquete: no cambiarlo nunca, o la llave «desaparece».
    static let keychainService = "com.widomin.clipboard-manager.local-key"
    static let keychainAccount = "localKey"

    private static let keyByteCount = 32

    private let lock = NSLock()
    private var cachedKey: SymmetricKey?

    private init() {}

    /// Devuelve la llave: de la caché, del Llavero o —solo si no existe en el
    /// Llavero **y** no hay ningún archivo cifrado en disco— recién creada.
    ///
    /// Nunca crea una llave nueva si el Llavero contesta con un error distinto
    /// de «no encontrado» (aviso rechazado, llavero bloqueado…): lanza. Así un
    /// fallo pasajero no acaba en una llave nueva que deje los datos ilegibles.
    ///
    /// - Parameter extraFiles: archivos de datos además de los de la carpeta
    ///   estándar (para un `JSONPersistenceService(fileURL:)` en otra ruta).
    func key(alsoChecking extraFiles: [URL] = []) throws -> SymmetricKey {
        lock.lock()
        defer { lock.unlock() }

        if let cached = cachedKey {
            return cached
        }
        if let stored = try readFromKeychain() {
            cachedKey = stored
            return stored
        }
        // No hay llave. Si ya hay algo cifrado, la llave se ha perdido o no la
        // estamos viendo (otro llavero, otra firma): crear otra sería tirar los
        // datos en la próxima escritura.
        if encryptedDataExists(extraFiles: extraFiles) {
            throw LocalKeyError.keyMissingButEncryptedDataExists
        }
        let created = try createInKeychain()
        cachedKey = created
        return created
    }

    // MARK: - Llavero

    private func baseQuery() -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: LocalKey.keychainService,
            kSecAttrAccount as String: LocalKey.keychainAccount,
            kSecUseDataProtectionKeychain as String: false,
        ]
    }

    /// `nil` solo si el elemento no existe. Cualquier otro fallo lanza.
    private func readFromKeychain() throws -> SymmetricKey? {
        var query = baseQuery()
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne

        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        switch status {
        case errSecSuccess:
            guard let data = result as? Data, data.count == LocalKey.keyByteCount else {
                throw LocalKeyError.invalidKeyData
            }
            return SymmetricKey(data: data)
        case errSecItemNotFound:
            return nil
        default:
            throw LocalKeyError.keychainRead(status)
        }
    }

    /// Genera 32 bytes aleatorios, los guarda y los vuelve a leer para devolver
    /// exactamente lo que quedó en el Llavero.
    private func createInKeychain() throws -> SymmetricKey {
        let fresh = SymmetricKey(size: .bits256)
        let keyData = fresh.withUnsafeBytes { Data($0) }

        var attributes = baseQuery()
        attributes[kSecAttrAccessible as String] = kSecAttrAccessibleWhenUnlockedThisDeviceOnly
        attributes[kSecAttrLabel as String] = "Clipboard Manager — llave local"
        attributes[kSecAttrDescription as String] = "Cifra el historial del portapapeles en este Mac"
        attributes[kSecValueData as String] = keyData

        let status = SecItemAdd(attributes as CFDictionary, nil)
        // `errSecDuplicateItem`: otro anfitrión (o otra instancia) la ha creado
        // en este mismo instante. Vale la suya.
        guard status == errSecSuccess || status == errSecDuplicateItem else {
            throw LocalKeyError.keychainWrite(status)
        }
        guard let stored = try readFromKeychain() else {
            throw LocalKeyError.keychainWrite(errSecItemNotFound)
        }
        return stored
    }

    // MARK: - Datos en disco

    /// `true` si algún archivo de datos ya está cifrado: los de la carpeta
    /// estándar (store.json, groups.json, images/*) y los extra.
    private func encryptedDataExists(extraFiles: [URL]) -> Bool {
        var candidates = extraFiles
        if let imagesDirectory = ImageStorage.directoryURL {
            let dataDirectory = imagesDirectory.deletingLastPathComponent()
            candidates.append(dataDirectory.appendingPathComponent("store.json"))
            candidates.append(dataDirectory.appendingPathComponent("groups.json"))
            let names = (try? FileManager.default.contentsOfDirectory(atPath: imagesDirectory.path)) ?? []
            for name in names {
                candidates.append(imagesDirectory.appendingPathComponent(name))
            }
        }
        return candidates.contains { FileCipher.fileIsEncrypted(at: $0) }
    }
}
