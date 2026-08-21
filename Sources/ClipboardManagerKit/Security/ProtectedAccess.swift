//
//  ProtectedAccess.swift
//  ClipboardManagerKit
//
//  Gate for protected items: Touch ID / macOS user password, with a grace
//  window so a burst of actions doesn't ask on every click.
//

import Foundation
import LocalAuthentication

/// Puerta de acceso a los items protegidos.
///
/// Pide **la credencial del propio Mac** (`deviceOwnerAuthentication`: Touch ID
/// con contraseña de usuario como alternativa) — no una contraseña propia de la
/// app, que habría que guardar en algún sitio y verificar a mano.
///
/// Tras un desbloqueo correcto no vuelve a preguntar durante `graceInterval`.
/// La ventana vive **solo en memoria**: al cerrar la app se pierde, así que un
/// arranque nuevo siempre pregunta.
///
/// Lo que esto protege es la **lectura desde la interfaz**. El texto sigue
/// guardado en claro en `store.json`: quien tenga acceso al archivo lo lee sin
/// pasar por aquí. Cifrarlo en disco es el paso siguiente (ver
/// `docs/05-blueprint-sync-android.md`).
@MainActor
public enum ProtectedAccess {

    /// Cuánto dura un desbloqueo antes de volver a preguntar.
    public static let graceInterval: TimeInterval = 15 * 60

    /// Momento del último desbloqueo correcto, o `nil` si nunca hubo uno.
    private static var lastUnlock: Date?

    /// True mientras el último desbloqueo siga dentro de la ventana de gracia.
    public static var isUnlocked: Bool {
        guard let lastUnlock = lastUnlock else { return false }
        return Date().timeIntervalSince(lastUnlock) < graceInterval
    }

    /// Olvida el desbloqueo: la próxima acción protegida volverá a preguntar.
    public static func lock() {
        lastUnlock = nil
    }

    /// Ejecuta `action` si el item no está protegido, si la ventana de gracia
    /// sigue abierta, o si el usuario supera la autenticación.
    ///
    /// `action` corre siempre en el hilo principal. Si la autenticación falla o
    /// se cancela no pasa nada más: no hay mensaje de error, porque cancelar es
    /// el caso normal y el sistema ya ha mostrado su propio diálogo.
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

    /// Pide la credencial del sistema salvo que la ventana de gracia siga abierta.
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
            Task { @MainActor in
                if success { lastUnlock = Date() }
                completion(success)
            }
        }
    }
}
