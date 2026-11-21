//
//  ProtectedAccess.swift
//  ClipboardManagerKit
//
//  Puerta de los items protegidos: Touch ID / contraseña del Mac, con una
//  ventana de gracia para que una ráfaga de acciones no pregunte en cada clic.
//  Además de dejar pasar, **abre la llave**: tras autenticar saca la
//  `protectedKey` privada del Llavero y descifra el texto (ver `ProtectedKey`).
//

import Foundation
import AppKit
import LocalAuthentication
import CryptoKit

/// Puerta de acceso a los items protegidos.
///
/// Pide **la credencial del propio Mac** (`deviceOwnerAuthentication`: Touch ID
/// con contraseña de usuario como alternativa) — no una contraseña propia de la
/// app, que habría que guardar en algún sitio y verificar a mano.
///
/// Tras un desbloqueo correcto no vuelve a preguntar durante `graceInterval`, y
/// durante ese tiempo la llave privada de los items protegidos se queda en
/// memoria. Al cumplirse se olvidan las dos cosas. La ventana vive **solo en
/// memoria**: al cerrar la app se pierde, así que un arranque nuevo siempre
/// pregunta.
///
/// En memoria y en `store.json` el texto de un item protegido va cifrado
/// (`ClipboardItem.sealedText`). Si el sistema impone o no la presencia al
/// sacar la llave depende de dónde la guardó `ProtectedKey`.
@MainActor
public enum ProtectedAccess {

    /// Cuánto dura un desbloqueo antes de volver a preguntar.
    public static let graceInterval: TimeInterval = 15 * 60

    /// Momento del último desbloqueo correcto, o `nil` si nunca hubo uno.
    private static var lastUnlock: Date?

    /// Distingue cada desbloqueo, para que el aviso de caducidad de uno viejo
    /// no cierre una ventana abierta después.
    private static var unlockGeneration = 0

    /// True mientras el último desbloqueo siga dentro de la ventana de gracia.
    /// Si ya ha caducado (p. ej. tras dormir el Mac), cierra y olvida la llave.
    public static var isUnlocked: Bool {
        guard let lastUnlock = lastUnlock else { return false }
        if Date().timeIntervalSince(lastUnlock) < graceInterval { return true }
        lock()
        return false
    }

    /// Olvida el desbloqueo y la llave: la próxima acción protegida volverá a
    /// preguntar.
    public static func lock() {
        lastUnlock = nil
        ProtectedKey.shared.forgetPrivateKey()
    }

    /// Ejecuta `action` si el item no está protegido, si la ventana de gracia
    /// sigue abierta, o si se supera la autenticación. **No descifra**: para
    /// pegar o editar usa `reveal`, que entrega el texto ya en claro.
    public static func run(
        for item: ClipboardItem,
        reason: String,
        action: @escaping () -> Void
    ) {
        guard item.isProtected else { action(); return }
        authenticate(reason: reason) { granted in
            if granted { action() }
        }
    }

    /// Entrega a `action` el item con el texto en claro en `textContent`.
    ///
    /// Un item no protegido pasa tal cual. Uno protegido pide autenticación
    /// (salvo ventana de gracia), saca la llave privada y descifra **una copia**:
    /// el item del almacén sigue cifrado. Cancelar no hace nada más; si la
    /// llave no se puede obtener o el descifrado falla, se avisa y no se ejecuta
    /// `action`. `action` corre siempre en el hilo principal.
    public static func reveal(
        _ item: ClipboardItem,
        reason: String,
        action: @escaping (ClipboardItem) -> Void
    ) {
        guard item.isProtected else { action(item); return }
        authenticate(reason: reason) { granted in
            guard granted else { return }
            // Item protegido de una versión anterior aún sin cifrar (la
            // migración no pudo hacerse): se comporta como antes.
            guard let sealed = item.sealedText else { action(item); return }

            withPrivateKey(reason: reason) { result in
                switch result {
                case .success(let privateKey):
                    do {
                        var revealed = item
                        revealed.textContent = try ProtectedTextCipher.open(sealed, with: privateKey)
                        revealed.sealedText = nil
                        action(revealed)
                    } catch {
                        showError(error)
                    }
                case .failure(let error):
                    // Cancelar el aviso del Llavero es el caso normal: sin mensaje.
                    if let keyError = error as? ProtectedKeyError, case .cancelled = keyError { return }
                    showError(error)
                }
            }
        }
    }

    /// Pide la credencial del sistema salvo que la ventana de gracia siga
    /// abierta. Con la misma autenticación saca del Llavero la llave privada
    /// (si existe), para que no haya un segundo aviso.
    public static func authenticate(reason: String, completion: @escaping (Bool) -> Void) {
        if isUnlocked { completion(true); return }

        let context = LAContext()
        context.localizedCancelTitle = "Cancelar"

        var error: NSError?
        // Sin ninguna política evaluable no hay forma de comprobar nada, así que
        // se deniega: fallar abierto convertiría el candado en decoración.
        guard context.canEvaluatePolicy(.deviceOwnerAuthentication, error: &error) else {
            completion(false)
            return
        }

        context.evaluatePolicy(.deviceOwnerAuthentication, localizedReason: reason) { success, _ in
            guard success else {
                Task { @MainActor in completion(false) }
                return
            }
            DispatchQueue.global(qos: .userInitiated).async {
                do {
                    _ = try ProtectedKey.shared.unlockPrivateKey(context: context, reason: reason)
                } catch {
                    // No impide abrir la ventana: `reveal` lo reintentará y
                    // avisará si hace falta la llave.
                    NSLog("ClipboardManager: no se pudo sacar la protectedKey: \(error.localizedDescription)")
                }
                Task { @MainActor in
                    startGraceWindow()
                    completion(true)
                }
            }
        }
    }

    // MARK: - Interno

    private static func startGraceWindow() {
        lastUnlock = Date()
        unlockGeneration += 1
        let generation = unlockGeneration
        // Olvida la llave a los 15 minutos aunque nadie vuelva a preguntar.
        // Con hora real (`wallDeadline`), que sigue corriendo con el Mac
        // dormido; `isUnlocked` además lo comprueba en cada uso.
        DispatchQueue.main.asyncAfter(wallDeadline: .now() + graceInterval) {
            Task { @MainActor in
                if unlockGeneration == generation { lock() }
            }
        }
    }

    /// La llave privada: de memoria si la ventana sigue abierta y ya se sacó,
    /// o del Llavero (fuera del hilo principal: puede esperar al dedo).
    private static func withPrivateKey(
        reason: String,
        completion: @escaping (Result<Curve25519.KeyAgreement.PrivateKey, Error>) -> Void
    ) {
        if let cached = ProtectedKey.shared.cachedPrivateKey {
            completion(.success(cached))
            return
        }
        DispatchQueue.global(qos: .userInitiated).async {
            let result: Result<Curve25519.KeyAgreement.PrivateKey, Error>
            do {
                if let key = try ProtectedKey.shared.unlockPrivateKey(context: nil, reason: reason) {
                    result = .success(key)
                } else {
                    result = .failure(ProtectedKeyError.keyMissingButSealedTextExists)
                }
            } catch {
                result = .failure(error)
            }
            Task { @MainActor in completion(result) }
        }
    }

    private static func showError(_ error: Error) {
        NSLog("ClipboardManager: no se pudo descifrar un elemento protegido: \(error.localizedDescription)")
        NSApp.activate(ignoringOtherApps: true)
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = "No se puede abrir el elemento protegido"
        alert.informativeText = """
            \(error.localizedDescription)

            El texto sigue guardado y cifrado; no se ha borrado nada.
            """
        alert.addButton(withTitle: "Aceptar")
        alert.runModal()
    }
}
