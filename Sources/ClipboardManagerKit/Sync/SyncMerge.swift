//
//  SyncMerge.swift
//  ClipboardManager
//
//  Las reglas de fusión del §6 del blueprint, como funciones puras: sin disco,
//  sin red, sin reloj. Todavía no las llama nadie; existen para que las reglas
//  queden fijadas y probadas (`Tests/vectors/merge-vectors.json`) antes de que
//  haya sincronización, y para que Kotlin y Rust las copien igual.
//

import Foundation

/// Fusión last-write-wins **por campo**.
///
/// Reglas, en este orden:
/// 1. Si cualquiera de los dos registros está borrado (`deletion`), el
///    resultado es un tombstone con la marca de borrado mayor: el borrado gana
///    a cualquier edición, sea más vieja o más nueva.
/// 2. Si no, cada campo mutable se queda con el valor del lado cuya marca
///    efectiva `(updatedAt, deviceId)` es mayor (`SyncStamp.<`), y el resultado
///    lleva esa marca. Con marcas idénticas gana `local` (solo pasa con datos
///    de antes de las marcas, que son iguales en los dos lados).
/// 3. El resultado lleva **todas** las marcas explícitas (las implícitas,
///    rellenas con la fecha de creación de su lado), porque `createdAt` puede
///    cambiar y con ella cambiarían las implícitas.
///
/// Los campos de contenido van juntos: `textContent`, `sealedText` e
/// `isProtected` son un solo campo (`content`) y se toman los tres del lado que
/// gana esa marca; la marca `protection` del resultado es la mayor de las dos,
/// pero no decide nada. `url` y `username` son campos independientes, cada uno
/// con su marca. `imageHash` no cambia nunca (se toma el de
/// `local`, o el de `remote` si `local` no lo tiene); `imageFilename` es un
/// nombre de archivo local y se conserva el de `local`. `createdAt` es la mayor
/// de las dos. `isFilterEnabled` de los grupos no se sincroniza: se conserva el
/// de `local`.
public enum SyncMerge {

    // MARK: - Items

    /// Fusiona dos versiones del mismo item. Si los `id` no coinciden devuelve
    /// `local` sin tocar.
    public static func merge(local: ClipboardItem, remote: ClipboardItem) -> ClipboardItem {
        guard local.id == remote.id else { return local }
        let createdAt = max(local.createdAt, remote.createdAt)

        if let deletion = latest(local.deletion, remote.deletion) {
            var dead = local.tombstone(deletion)
            dead.createdAt = createdAt
            return dead
        }

        let l = local.effectiveStamps()
        let r = remote.effectiveStamps()
        var merged = local
        merged.createdAt = createdAt
        merged.deletion = nil
        merged.imageHash = local.imageHash ?? remote.imageHash

        // El contenido y la protección son un solo bloque: el texto en claro,
        // el texto cifrado y `isProtected` se toman del mismo lado, el que gana
        // la marca `content`. Fusionarlos por separado podría dejar un item
        // sin proteger con el texto solo cifrado (una fila en blanco que no se
        // puede pegar) o uno protegido con el texto en claro. Proteger o
        // desproteger ya marca `content` (`ClipboardStore.setText`).
        let content = winner(l.content, r.content, local)
        if content.remoteWins {
            merged.textContent = remote.textContent
            merged.sealedText = remote.sealedText
            merged.isProtected = remote.isProtected
        }
        let detail = winner(l.detail, r.detail, local)
        if detail.remoteWins { merged.detail = remote.detail }
        let title = winner(l.title, r.title, local)
        if title.remoteWins { merged.title = remote.title }
        let favorite = winner(l.favorite, r.favorite, local)
        if favorite.remoteWins { merged.isFavorite = remote.isFavorite }
        // La marca `protection` ya no decide nada; se conserva la mayor para
        // que el resultado no pierda historia y los archivos sigan siendo los
        // mismos.
        let protection = winner(l.protection, r.protection, local)
        let group = winner(l.group, r.group, local)
        if group.remoteWins { merged.groupID = remote.groupID }
        let url = winner(l.url, r.url, local)
        if url.remoteWins { merged.url = remote.url }
        let username = winner(l.username, r.username, local)
        if username.remoteWins { merged.username = remote.username }

        merged.stamps = ItemFieldStamps(
            content: content.stamp,
            detail: detail.stamp,
            title: title.stamp,
            favorite: favorite.stamp,
            protection: protection.stamp,
            group: group.stamp,
            url: url.stamp,
            username: username.stamp
        )
        return merged
    }

    /// Fusiona dos listas de items por `id`. Lo que solo está en un lado pasa
    /// tal cual (también un tombstone que solo trae `remote`: hay que
    /// recordarlo). El resultado va ordenado por `id.uuidString`, para que sea
    /// el mismo en cualquier aparato; quien lo use reordena a su gusto.
    public static func merge(local: [ClipboardItem], remote: [ClipboardItem]) -> [ClipboardItem] {
        var byID: [UUID: ClipboardItem] = [:]
        for item in local { byID[item.id] = item }
        for item in remote {
            if let existing = byID[item.id] {
                byID[item.id] = merge(local: existing, remote: item)
            } else {
                byID[item.id] = item
            }
        }
        return byID.values.sorted { $0.id.uuidString < $1.id.uuidString }
    }

    /// La mayor de dos marcas de borrado, o `nil` si ninguno está borrado.
    private static func latest(_ a: SyncStamp?, _ b: SyncStamp?) -> SyncStamp? {
        guard let a = a else { return b }
        guard let b = b else { return a }
        return max(a, b)
    }

    /// Compara la marca de un campo en los dos lados. `effectiveStamps()` ya
    /// las rellena todas; el `??` solo evita forzar el opcional.
    private static func winner(
        _ local: SyncStamp?, _ remote: SyncStamp?, _ localItem: ClipboardItem
    ) -> (stamp: SyncStamp, remoteWins: Bool) {
        let l = local ?? .legacy(at: localItem.createdAt)
        let r = remote ?? .legacy(at: localItem.createdAt)
        return r > l ? (r, true) : (l, false)
    }

    // MARK: - Grupos

    /// Fusiona dos versiones del mismo grupo. Si los `id` no coinciden devuelve
    /// `local` sin tocar.
    public static func merge(local: ClipboardGroup, remote: ClipboardGroup) -> ClipboardGroup {
        guard local.id == remote.id else { return local }

        if let deletion = latest(local.deletion, remote.deletion) {
            return local.tombstone(deletion)
        }

        let l = local.effectiveNameStamp
        let r = remote.effectiveNameStamp
        var merged = local
        merged.deletion = nil
        if r > l { merged.name = remote.name }
        merged.nameStamp = max(l, r)
        return merged
    }

    /// Fusiona dos listas de grupos por `id`, con las mismas reglas que
    /// `merge(local:remote:)` de items.
    public static func merge(local: [ClipboardGroup], remote: [ClipboardGroup]) -> [ClipboardGroup] {
        var byID: [UUID: ClipboardGroup] = [:]
        for group in local { byID[group.id] = group }
        for group in remote {
            if let existing = byID[group.id] {
                byID[group.id] = merge(local: existing, remote: group)
            } else {
                byID[group.id] = group
            }
        }
        return byID.values.sorted { $0.id.uuidString < $1.id.uuidString }
    }
}
