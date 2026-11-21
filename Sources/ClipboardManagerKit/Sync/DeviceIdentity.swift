//
//  DeviceIdentity.swift
//  ClipboardManager
//
//  Identificador estable de esta instalación, el `deviceId` de las marcas de
//  cambio (`SyncStamp`).
//

import Foundation

/// El `deviceId` de este Mac: un UUID aleatorio que se crea la primera vez y
/// se guarda en `~/Library/Application Support/ClipboardManager/device-id`,
/// junto a `store.enc`.
///
/// **Por qué en esa carpeta y no en `UserDefaults`**: la app suelta y Widomin
/// comparten la carpeta de datos pero no las preferencias (cada una tiene su
/// bundle id). Los dos escriben el mismo historial, así que son la misma
/// instalación y deben firmar con el mismo `deviceId`.
///
/// Va en claro: no es secreto (el servidor lo verá) y no protege nada. Si el
/// archivo falta o no contiene un UUID, se crea uno nuevo; si no se puede
/// escribir, se usa uno solo en memoria durante esa ejecución. Un `deviceId`
/// que cambia solo afecta a los desempates, nunca a los datos.
public enum DeviceIdentity {

    private static let lock = NSLock()
    private static var cached: String?

    /// Ruta del archivo, sin crear nada.
    static var fileURL: URL? {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)
            .first?
            .appendingPathComponent("ClipboardManager/device-id")
    }

    /// El `deviceId` de esta instalación, en mayúsculas.
    public static func current() -> String {
        lock.lock()
        defer { lock.unlock() }
        if let cached = cached { return cached }
        let id = readOrCreate()
        cached = id
        return id
    }

    private static func readOrCreate() -> String {
        guard let url = fileURL else { return UUID().uuidString }
        if let data = try? Data(contentsOf: url),
           let text = String(data: data, encoding: .utf8),
           let uuid = UUID(uuidString: text.trimmingCharacters(in: .whitespacesAndNewlines)) {
            return uuid.uuidString
        }
        let created = UUID().uuidString
        do {
            try FileManager.default.createDirectory(
                at: url.deletingLastPathComponent(), withIntermediateDirectories: true
            )
            try Data(created.utf8).write(to: url, options: .atomic)
        } catch {
            NSLog("ClipboardManager: no se pudo guardar el deviceId: \(error.localizedDescription)")
        }
        return created
    }
}
