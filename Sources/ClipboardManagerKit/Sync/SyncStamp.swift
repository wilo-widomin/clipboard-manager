//
//  SyncStamp.swift
//  ClipboardManager
//
//  Marca de cambio para la futura sincronización (§6 del blueprint): cuándo se
//  cambió un campo y en qué aparato. Todavía no viaja a ningún sitio; existe
//  para que el modelo local guarde ya la historia mínima que la fusión necesita.
//

import Foundation

/// `(updatedAt, deviceId)` de un cambio. Ordena primero por fecha y, si dos
/// relojes coinciden, por `deviceId`: así la fusión es determinista en
/// cualquier aparato y en cualquier lenguaje.
public struct SyncStamp: Codable, Hashable, Sendable, Comparable {

    /// Momento del cambio, redondeado a milisegundos (`now(deviceId:)`) para
    /// que viaje sin pérdida como entero entre Swift, Kotlin y Rust.
    public var updatedAt: Date

    /// Aparato que hizo el cambio (`DeviceIdentity`). Cadena ASCII —un UUID en
    /// mayúsculas— que se compara byte a byte. Vacía en las marcas derivadas
    /// de datos anteriores a las marcas (`legacy(at:)`), que así pierden ante
    /// cualquier aparato real con la misma fecha.
    public var deviceId: String

    public init(updatedAt: Date, deviceId: String) {
        self.updatedAt = updatedAt
        self.deviceId = deviceId
    }

    /// Marca de un cambio hecho ahora en este aparato.
    public static func now(deviceId: String) -> SyncStamp {
        let milliseconds = (Date().timeIntervalSince1970 * 1000).rounded(.down)
        return SyncStamp(updatedAt: Date(timeIntervalSince1970: milliseconds / 1000), deviceId: deviceId)
    }

    /// Marca implícita de un campo que nunca se ha cambiado desde que existen
    /// las marcas: fecha dada y aparato vacío.
    public static func legacy(at date: Date) -> SyncStamp {
        SyncStamp(updatedAt: date, deviceId: "")
    }

    /// Marca implícita del nombre de un grupo sin marca: el 1-1-1970. Los
    /// grupos no tienen fecha de creación, y usar la de carga haría que la
    /// marca cambiase en cada arranque; con una fecha fija, cualquier cambio
    /// real hecho en cualquier aparato le gana.
    public static let legacyGroup = SyncStamp.legacy(at: Date(timeIntervalSince1970: 0))

    public static func < (lhs: SyncStamp, rhs: SyncStamp) -> Bool {
        if lhs.updatedAt != rhs.updatedAt { return lhs.updatedAt < rhs.updatedAt }
        return lhs.deviceId.utf8.lexicographicallyPrecedes(rhs.deviceId.utf8)
    }
}

/// Las marcas de cada campo mutable de un `ClipboardItem`. `nil` significa
/// «no ha cambiado desde que se creó el item (o desde antes de que hubiera
/// marcas)»: su marca efectiva es `SyncStamp.legacy(at: createdAt)`
/// (ver `ClipboardItem.effectiveStamps()`). Nada se reescribe al cargar: la
/// marca solo se guarda cuando el campo cambia de verdad.
public struct ItemFieldStamps: Codable, Hashable, Sendable {
    /// El contenido: `textContent`, `sealedText` e `isProtected` van juntos
    /// (el mismo texto en claro o cifrado, y si está protegido). Proteger o
    /// desproteger también cambia esta marca.
    public var content: SyncStamp?
    public var detail: SyncStamp?
    public var title: SyncStamp?
    /// `isFavorite`. Si existe y el item no es favorito, el item **salió** del
    /// conjunto sincronizado (ver `ClipboardItem.hasLeftSyncedSet`).
    public var favorite: SyncStamp?
    /// Cuándo cambió `isProtected` por última vez. Solo informativa: en la
    /// fusión `isProtected` sigue a `content` y esta marca se queda con la
    /// mayor de los dos lados. Se conserva para que los archivos ya escritos
    /// se lean igual.
    public var protection: SyncStamp?
    /// `groupID`.
    public var group: SyncStamp?

    public init(
        content: SyncStamp? = nil,
        detail: SyncStamp? = nil,
        title: SyncStamp? = nil,
        favorite: SyncStamp? = nil,
        protection: SyncStamp? = nil,
        group: SyncStamp? = nil
    ) {
        self.content = content
        self.detail = detail
        self.title = title
        self.favorite = favorite
        self.protection = protection
        self.group = group
    }
}
