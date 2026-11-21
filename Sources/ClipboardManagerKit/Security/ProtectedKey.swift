//
//  ProtectedKey.swift
//  ClipboardManagerKit
//
//  `protectedKey`: el par de llaves X25519 con el que se cifra el texto de los
//  items protegidos (ver `ProtectedTextCipher` y
//  docs/05-blueprint-sync-android.md, §3.2). La parte privada son 32 bytes
//  aleatorios; la pública se deriva de ella.
//
//  Dónde se guarda cada parte, y qué impone de verdad el sistema:
//
//  - **La pública** va en el llavero de sesión de siempre
//    (`kSecUseDataProtectionKeychain = false`), como la `localKey`. No es
//    secreta: sirve para cifrar, no para leer. Se lee sin pedir nada.
//
//  - **La privada** se intenta guardar en el **llavero de protección de datos**
//    con un `SecAccessControl` de presencia (`.userPresence`: Touch ID o la
//    contraseña del Mac). Ahí es el propio macOS quien se niega a entregarla
//    sin autenticar. Pero ese llavero exige que la app lleve el entitlement
//    `keychain-access-groups`, que en macOS solo vale con un perfil de
//    aprovisionamiento; `scripts/build-release.sh` firma sin perfil y entonces
//    `SecItemAdd` devuelve `errSecMissingEntitlement` (-34018). El llavero de
//    sesión, por su parte, no admite `kSecAttrAccessControl` (lo ignora).
//
//  - Sin ese entitlement la privada cae al **llavero de sesión, sin control de
//    presencia**. Entonces el sistema solo impone lo mismo que con la
//    `localKey` (sesión abierta y lista de acceso atada a la firma de la app),
//    y quien exige Touch ID antes de leerla es **la app** (`ProtectedAccess`).
//    Lo que sí se gana: el texto protegido ya no está en claro en memoria ni
//    dentro del `store.json` descifrado; hace falta además esta otra llave.
//
//  Al leer la privada se mira primero el llavero de protección de datos y
//  después el de sesión, así que una build con el entitlement encuentra
//  también una llave creada antes sin él (no la mueve: eso queda pendiente).
//
//  El nombre del servicio es fijo y no depende del bundle id, por la misma
//  razón que el de `LocalKey`: la app suelta y Widomin comparten los datos.
//

import Foundation
import Security
import CryptoKit
import LocalAuthentication

/// Errores al leer o crear la `protectedKey`.
public enum ProtectedKeyError: Error, LocalizedError {
    case keychainRead(OSStatus)
    case keychainWrite(OSStatus)
    case invalidKeyData
    case keyMissingButSealedTextExists
    case privateKeyMissing
    case publicKeyMismatch
    case cancelled

    public var errorDescription: String? {
        switch self {
        case .keychainRead(let status):
            return "No se pudo leer la llave de los elementos protegidos del Llavero (\(status): \(ProtectedKeyError.message(for: status)))."
        case .keychainWrite(let status):
            return "No se pudo guardar la llave de los elementos protegidos en el Llavero (\(status): \(ProtectedKeyError.message(for: status)))."
        case .invalidKeyData:
            return "La llave de los elementos protegidos guardada en el Llavero no es válida."
        case .keyMissingButSealedTextExists:
            return "Hay elementos protegidos cifrados pero su llave no está en el Llavero. No se crea otra para no dejarlos ilegibles."
        case .privateKeyMissing:
            return "La parte privada de la llave de los elementos protegidos no está en el Llavero. No se cifra nada más con ella."
        case .publicKeyMismatch:
            return "Las dos partes de la llave de los elementos protegidos no casan entre sí."
        case .cancelled:
            return "Autenticación cancelada."
        }
    }

    private static func message(for status: OSStatus) -> String {
        (SecCopyErrorMessageString(status, nil) as String?) ?? "error desconocido"
    }
}

/// Acceso a la `protectedKey`. La pública se cachea para siempre; la privada,
/// solo mientras `ProtectedAccess` mantiene abierta la ventana de gracia.
/// Seguro desde cualquier hilo.
final class ProtectedKey: @unchecked Sendable {

    static let shared = ProtectedKey()

    /// Servicio de los dos elementos en el Llavero. Fijo: no cambiarlo nunca.
    static let keychainService = "com.widomin.clipboard-manager.protected-key"
    static let privateKeyAccount = "protectedKey"
    static let publicKeyAccount = "protectedPublicKey"

    private static let keyByteCount = 32

    private let lock = NSLock()
    private var cachedPublicKey: Curve25519.KeyAgreement.PublicKey?
    private var unlockedPrivateKey: Curve25519.KeyAgreement.PrivateKey?

    private init() {}

    // MARK: - Parte pública (cifrar)

    /// La llave pública con la que se cifra. La crea (par completo) solo si no
    /// existe **y** no hay ya ningún texto cifrado (`sealedTextExists`). Nunca
    /// pide autenticación.
    ///
    /// Antes de devolver una pública ya guardada comprueba que su privada sigue
    /// en el Llavero y que es **la suya**: cifrar hacia una llave cuya privada
    /// se ha perdido (o ha sido sustituida por otra) sería tirar el texto.
    func publicKey(sealedTextExists: Bool) throws -> Curve25519.KeyAgreement.PublicKey {
        lock.lock()
        defer { lock.unlock() }

        if let cached = cachedPublicKey {
            return cached
        }
        if let stored = try readPublicKey() {
            guard try privateKeyExists(matching: stored) else { throw ProtectedKeyError.privateKeyMissing }
            cachedPublicKey = stored
            return stored
        }
        if sealedTextExists {
            throw ProtectedKeyError.keyMissingButSealedTextExists
        }
        let created = try createKeyPair()
        cachedPublicKey = created
        return created
    }

    // MARK: - Parte privada (descifrar)

    /// La privada si está desbloqueada (ventana de gracia abierta), o `nil`.
    var cachedPrivateKey: Curve25519.KeyAgreement.PrivateKey? {
        lock.lock()
        defer { lock.unlock() }
        return unlockedPrivateKey
    }

    /// Olvida la privada: el próximo descifrado tendrá que volver a pedirla.
    func forgetPrivateKey() {
        lock.lock()
        defer { lock.unlock() }
        unlockedPrivateKey = nil
    }

    /// Saca la privada del Llavero y la deja en memoria. **Bloquea** el hilo
    /// (si está en el llavero de protección de datos, el sistema puede pedir
    /// Touch ID aquí mismo): llámala fuera del hilo principal.
    ///
    /// - Parameter context: un `LAContext` ya autenticado con
    ///   `evaluatePolicy`, para que el Llavero no vuelva a preguntar. Sin él,
    ///   el sistema pregunta con `reason`.
    /// - Returns: `nil` si no hay llave en ningún llavero (nunca se protegió
    ///   nada).
    func unlockPrivateKey(context: LAContext?, reason: String) throws -> Curve25519.KeyAgreement.PrivateKey? {
        if let cached = cachedPrivateKey {
            return cached
        }
        // Sin el candado puesto: la lectura puede quedarse esperando al dedo y
        // el hilo principal no debe bloquearse por pedir la pública.
        guard let key = try readPrivateKey(context: context, reason: reason) else {
            return nil
        }
        // La privada tiene que ser la pareja de la pública con la que se cifra.
        // Si no hay pública guardada no se ha cifrado nada con ninguna: se acepta.
        if let stored = try readPublicKey(),
           stored.rawRepresentation != key.publicKey.rawRepresentation {
            throw ProtectedKeyError.publicKeyMismatch
        }
        lock.lock()
        defer { lock.unlock() }
        unlockedPrivateKey = key
        return key
    }

    // MARK: - Llavero

    private func baseQuery(account: String, dataProtection: Bool) -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: ProtectedKey.keychainService,
            kSecAttrAccount as String: account,
            kSecUseDataProtectionKeychain as String: dataProtection,
        ]
    }

    /// `nil` solo si no existe. Siempre en el llavero de sesión.
    private func readPublicKey() throws -> Curve25519.KeyAgreement.PublicKey? {
        var query = baseQuery(account: ProtectedKey.publicKeyAccount, dataProtection: false)
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne

        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        switch status {
        case errSecSuccess:
            guard let data = result as? Data, data.count == ProtectedKey.keyByteCount,
                  let key = try? Curve25519.KeyAgreement.PublicKey(rawRepresentation: data)
            else { throw ProtectedKeyError.invalidKeyData }
            return key
        case errSecItemNotFound:
            return nil
        default:
            throw ProtectedKeyError.keychainRead(status)
        }
    }

    /// Lee la privada: primero del llavero de protección de datos (donde el
    /// sistema exige presencia), después del de sesión. `nil` si no está en
    /// ninguno.
    private func readPrivateKey(context: LAContext?, reason: String) throws -> Curve25519.KeyAgreement.PrivateKey? {
        let authContext = context ?? LAContext()
        if context == nil {
            authContext.localizedReason = reason
        }

        var protected = baseQuery(account: ProtectedKey.privateKeyAccount, dataProtection: true)
        protected[kSecReturnData as String] = true
        protected[kSecMatchLimit as String] = kSecMatchLimitOne
        protected[kSecUseAuthenticationContext as String] = authContext

        var result: CFTypeRef?
        let status = SecItemCopyMatching(protected as CFDictionary, &result)
        switch status {
        case errSecSuccess:
            return try privateKey(from: result)
        case errSecUserCanceled, errSecAuthFailed:
            throw ProtectedKeyError.cancelled
        case errSecItemNotFound, errSecMissingEntitlement:
            break  // no está ahí, o esta build no puede usar ese llavero
        default:
            throw ProtectedKeyError.keychainRead(status)
        }

        var login = baseQuery(account: ProtectedKey.privateKeyAccount, dataProtection: false)
        login[kSecReturnData as String] = true
        login[kSecMatchLimit as String] = kSecMatchLimitOne

        result = nil
        let loginStatus = SecItemCopyMatching(login as CFDictionary, &result)
        switch loginStatus {
        case errSecSuccess:
            return try privateKey(from: result)
        case errSecItemNotFound:
            return nil
        case errSecUserCanceled:
            throw ProtectedKeyError.cancelled
        default:
            throw ProtectedKeyError.keychainRead(loginStatus)
        }
    }

    private func privateKey(from result: CFTypeRef?) throws -> Curve25519.KeyAgreement.PrivateKey {
        guard let data = result as? Data, data.count == ProtectedKey.keyByteCount,
              let key = try? Curve25519.KeyAgreement.PrivateKey(rawRepresentation: data)
        else { throw ProtectedKeyError.invalidKeyData }
        return key
    }

    /// Comprueba que la privada existe **sin pedir autenticación**: solo
    /// atributos, nunca los datos, y con un `LAContext` que no permite
    /// interacción (si el sistema quisiera preguntar, devuelve
    /// `errSecInteractionNotAllowed` en vez de enseñar nada).
    ///
    /// Además compara la pública que la privada lleva apuntada en
    /// `kSecAttrGeneric` con `publicKey`, y lanza `.publicKeyMismatch` si no
    /// casan. Pasa cuando la app suelta y Widomin crean el par a la vez la
    /// primera vez: el segundo puede sustituir la privada del primero mientras
    /// la pública guardada sigue siendo la del primero.
    private func privateKeyExists(matching publicKey: Curve25519.KeyAgreement.PublicKey) throws -> Bool {
        let silent = LAContext()
        silent.interactionNotAllowed = true

        var protected = baseQuery(account: ProtectedKey.privateKeyAccount, dataProtection: true)
        protected[kSecReturnAttributes as String] = true
        protected[kSecMatchLimit as String] = kSecMatchLimitOne
        protected[kSecUseAuthenticationContext as String] = silent

        var result: CFTypeRef?
        let status = SecItemCopyMatching(protected as CFDictionary, &result)
        switch status {
        case errSecSuccess:
            try checkStoredPublicKey(in: result, against: publicKey)
            return true
        case errSecInteractionNotAllowed:
            return true  // existe, pero sin atributos que comparar
        case errSecItemNotFound, errSecMissingEntitlement:
            break
        default:
            throw ProtectedKeyError.keychainRead(status)
        }

        var login = baseQuery(account: ProtectedKey.privateKeyAccount, dataProtection: false)
        login[kSecReturnAttributes as String] = true
        login[kSecMatchLimit as String] = kSecMatchLimitOne

        result = nil
        let loginStatus = SecItemCopyMatching(login as CFDictionary, &result)
        switch loginStatus {
        case errSecSuccess:
            try checkStoredPublicKey(in: result, against: publicKey)
            return true
        case errSecItemNotFound:
            return false
        default:
            throw ProtectedKeyError.keychainRead(loginStatus)
        }
    }

    /// Compara la pública apuntada en la privada (`kSecAttrGeneric`) con la
    /// guardada. Una privada sin ese atributo se creó con una build anterior
    /// que no lo escribía: no se sabe, y se acepta para no romper nada.
    private func checkStoredPublicKey(in attributes: CFTypeRef?,
                                      against publicKey: Curve25519.KeyAgreement.PublicKey) throws {
        guard let dict = attributes as? [String: Any],
              let recorded = dict[kSecAttrGeneric as String] as? Data
        else { return }
        guard recorded == publicKey.rawRepresentation else {
            throw ProtectedKeyError.publicKeyMismatch
        }
    }

    /// Crea el par: guarda primero la privada y después la pública, y relee la
    /// pública para devolver exactamente lo que quedó en el Llavero. Si la app
    /// muere entre las dos escrituras, la privada suelta se sustituye en el
    /// siguiente intento (nada se había cifrado aún con ella).
    private func createKeyPair() throws -> Curve25519.KeyAgreement.PublicKey {
        let privateKey = Curve25519.KeyAgreement.PrivateKey()
        let publicData = privateKey.publicKey.rawRepresentation
        try storePrivateKey(privateKey.rawRepresentation, publicData: publicData)

        var attributes = baseQuery(account: ProtectedKey.publicKeyAccount, dataProtection: false)
        attributes[kSecAttrAccessible as String] = kSecAttrAccessibleWhenUnlockedThisDeviceOnly
        attributes[kSecAttrLabel as String] = "Clipboard Manager — llave pública de elementos protegidos"
        attributes[kSecAttrDescription as String] = "Cifra el texto de los elementos protegidos (no es secreta)"
        attributes[kSecValueData as String] = publicData

        let status = SecItemAdd(attributes as CFDictionary, nil)
        guard status == errSecSuccess || status == errSecDuplicateItem else {
            throw ProtectedKeyError.keychainWrite(status)
        }
        guard let stored = try readPublicKey() else {
            throw ProtectedKeyError.keychainWrite(errSecItemNotFound)
        }
        // Otro anfitrión creó el par en el mismo instante: su pública no es de
        // nuestra privada. No se cifra nada; el siguiente intento leerá el suyo.
        guard stored.rawRepresentation == publicData else {
            throw ProtectedKeyError.publicKeyMismatch
        }
        return stored
    }

    /// Guarda la privada con presencia obligatoria en el llavero de protección
    /// de datos; si esta build no tiene el entitlement, en el de sesión.
    /// En los dos casos apunta su pública en `kSecAttrGeneric` (no es secreta)
    /// para poder comprobar después, sin autenticar, que la pública guardada
    /// es su pareja.
    private func storePrivateKey(_ keyData: Data, publicData: Data) throws {
        var error: Unmanaged<CFError>?
        if let access = SecAccessControlCreateWithFlags(
            kCFAllocatorDefault,
            kSecAttrAccessibleWhenUnlockedThisDeviceOnly,
            .userPresence,
            &error
        ) {
            var attributes = baseQuery(account: ProtectedKey.privateKeyAccount, dataProtection: true)
            attributes[kSecAttrAccessControl as String] = access
            attributes[kSecAttrLabel as String] = "Clipboard Manager — llave de elementos protegidos"
            attributes[kSecAttrGeneric as String] = publicData
            attributes[kSecValueData as String] = keyData

            let status = addReplacingLeftover(attributes,
                                              matching: baseQuery(account: ProtectedKey.privateKeyAccount, dataProtection: true))
            if status == errSecSuccess {
                NSLog("ClipboardManager: protectedKey creada con presencia obligatoria (llavero de protección de datos)")
                return
            }
            guard status == errSecMissingEntitlement else {
                throw ProtectedKeyError.keychainWrite(status)
            }
        } else {
            NSLog("ClipboardManager: no se pudo crear el control de acceso: \(String(describing: error?.takeRetainedValue()))")
        }

        var attributes = baseQuery(account: ProtectedKey.privateKeyAccount, dataProtection: false)
        attributes[kSecAttrAccessible as String] = kSecAttrAccessibleWhenUnlockedThisDeviceOnly
        attributes[kSecAttrLabel as String] = "Clipboard Manager — llave de elementos protegidos"
        attributes[kSecAttrDescription as String] = "Descifra el texto de los elementos protegidos"
        attributes[kSecAttrGeneric as String] = publicData
        attributes[kSecValueData as String] = keyData

        let status = addReplacingLeftover(attributes,
                                          matching: baseQuery(account: ProtectedKey.privateKeyAccount, dataProtection: false))
        guard status == errSecSuccess else {
            throw ProtectedKeyError.keychainWrite(status)
        }
        NSLog("ClipboardManager: protectedKey creada en el llavero de sesión (sin entitlement; la presencia la exige la app)")
    }

    /// `SecItemAdd`; si ya existe una privada, es el resto de una creación
    /// interrumpida (solo se llega aquí sin pública y sin nada cifrado), así
    /// que se borra y se vuelve a añadir.
    private func addReplacingLeftover(_ attributes: [String: Any], matching: [String: Any]) -> OSStatus {
        var status = SecItemAdd(attributes as CFDictionary, nil)
        if status == errSecDuplicateItem {
            SecItemDelete(matching as CFDictionary)
            status = SecItemAdd(attributes as CFDictionary, nil)
        }
        return status
    }
}
