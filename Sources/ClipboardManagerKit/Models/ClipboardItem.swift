//
//  ClipboardItem.swift
//  ClipboardManager
//
//  Model for a single clipboard entry: text or image, with favorites support.
//  Images are stored as individual files on disk, cifrados con la `localKey`
//  (ver `FileCipher`); the model only keeps the filename reference.
//

import Foundation
import AppKit  // for NSImage used by loadImage()
import CryptoKit

/// The type of content stored in a clipboard item.
public enum ClipboardContentType: String, Codable, Sendable {
    case text
    case image
}

/// A single clipboard entry captured by the monitor.
public struct ClipboardItem: Identifiable, Codable, Sendable {

    /// `var` solo dentro del paquete: al deduplicar, la captura nueva hereda el
    /// `id` del item al que sustituye, para que siga siendo el mismo registro
    /// de cara a la sincronización (ver `ClipboardStore.add`).
    public internal(set) var id: UUID
    public let contentType: ClipboardContentType
    /// `var` solo dentro del paquete: la fusión (`SyncMerge`) se queda con la
    /// más reciente de las dos. Solo ordena la lista; no se sincroniza como campo.
    public internal(set) var createdAt: Date

    /// The text content (nil for image items). Mutable because the right-click
    /// editor lets the user rewrite what was captured.
    ///
    /// **`nil` también en un item protegido**: su texto va cifrado en
    /// `sealedText` y solo se obtiene en claro con `ProtectedAccess.reveal`.
    public var textContent: String?

    /// Texto de un item protegido, cifrado con la `protectedKey` (formato en
    /// `ProtectedTextCipher`, en base64). `nil` en todo lo demás. Opcional para
    /// que los `store.json` anteriores decodifiquen; un item protegido antiguo
    /// llega con `textContent` en claro y `ClipboardStore.load()` lo cifra.
    public var sealedText: String? = nil

    /// Filename of the PNG file on disk, relative to the images directory.
    /// Example: "E621F1A2-4B3C-4D5E-8F9A-0B1C2D3E4F5F.png"
    public let imageFilename: String?

    /// Whether the user has starred this item as a favourite.
    public var isFavorite: Bool

    /// The group this item is assigned to, if any. An item belongs to at most
    /// one group. `nil` means "ungrouped". Optional so items persisted by an
    /// older build (which lack this key) decode cleanly as ungrouped.
    public var groupID: UUID? = nil

    /// Free-text note the user attaches to the item via the right-click editor.
    /// Optional & defaulted so older `store.json` files decode cleanly, and so
    /// the factory methods below need no extra argument.
    public var detail: String? = nil

    /// Short label shown in the list **instead of** the captured text when the
    /// item is protected. Optional so older `store.json` files decode cleanly.
    public var title: String? = nil

    /// Protected items hide their captured text: the list shows `title`, and
    /// opening the editor or pasting the item asks for the macOS user password
    /// / Touch ID first. Text items only — an image reveals itself in its own
    /// thumbnail, so hiding its text would protect nothing. Su texto vive en
    /// `sealedText`, cifrado.
    public var isProtected: Bool = false

    // MARK: - Sincronización (§6 del blueprint)

    /// SHA-256 en hexadecimal (minúsculas) de los bytes **en claro** del PNG.
    /// Es la identidad de la imagen entre aparatos; `imageFilename` sigue siendo
    /// solo el nombre del archivo local. Se calcula al capturar, y para las
    /// imágenes anteriores la primera vez que el store deduplica una imagen.
    /// `nil` en textos y en una imagen cuyo archivo no se pudo leer.
    public var imageHash: String? = nil

    /// Marca `(updatedAt, deviceId)` de cada campo mutable. Ver `ItemFieldStamps`.
    public var stamps: ItemFieldStamps = ItemFieldStamps()

    /// Si existe, el item está **borrado** (tombstone): se conserva el registro,
    /// sin contenido, para que el borrado gane a cualquier edición de otro
    /// aparato. El store no lo enseña nunca: vive aparte, en
    /// `ClipboardStore.itemTombstones`.
    public var deletion: SyncStamp? = nil

    /// Cuándo se borró, o `nil` si está vivo.
    public var deletedAt: Date? { deletion?.updatedAt }

    /// `true` si es un tombstone.
    public var isDeleted: Bool { deletion != nil }

    /// Está en el conjunto que se sincroniza (§2): favorito y vivo.
    public var isInSyncedSet: Bool { isFavorite && !isDeleted }

    /// Fue favorito y Willy le quitó la estrella: para los demás aparatos ha
    /// salido del conjunto sincronizado (`isFavorite = false` con su marca),
    /// pero aquí sigue en el historial hasta que el tope lo recicle.
    public var hasLeftSyncedSet: Bool { !isFavorite && stamps.favorite != nil && !isDeleted }

    /// Si al quitarlo de la lista hay que dejar tombstone: es o fue favorito.
    /// El historial que nunca fue favorito no se sincroniza y se borra de verdad.
    var leavesTombstone: Bool { isFavorite || stamps.favorite != nil }

    /// Las marcas con las vacías rellenas con `SyncStamp.legacy(at: createdAt)`.
    /// Hay que fijarlas así antes de cambiar `createdAt`, o las implícitas
    /// cambiarían con ella.
    public func effectiveStamps() -> ItemFieldStamps {
        let implicit = SyncStamp.legacy(at: createdAt)
        return ItemFieldStamps(
            content: stamps.content ?? implicit,
            detail: stamps.detail ?? implicit,
            title: stamps.title ?? implicit,
            favorite: stamps.favorite ?? implicit,
            protection: stamps.protection ?? implicit,
            group: stamps.group ?? implicit
        )
    }

    /// El tombstone de este item: conserva `id`, `contentType` y `createdAt` y
    /// tira todo lo demás (texto, texto cifrado, nota, título, imagen, marcas),
    /// para que un borrado no deje contraseñas guardadas.
    public func tombstone(_ deletion: SyncStamp) -> ClipboardItem {
        ClipboardItem(
            id: id,
            contentType: contentType,
            createdAt: createdAt,
            textContent: nil,
            imageFilename: nil,
            isFavorite: false,
            deletion: deletion
        )
    }

    /// Whether the item carries a non-empty detail note.
    public var hasDetail: Bool {
        guard let detail = detail else { return false }
        return !detail.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    /// El título, ya recortado, o `nil` si está vacío.
    public var trimmedTitle: String? {
        guard let title = title else { return nil }
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    // MARK: - Preview helpers

    /// Texto completo en una sola línea (saltos y tabuladores colapsados a
    /// espacios). Pensado para filas que ya recortan con `lineLimit(1)`: la
    /// vista decide dónde cortar según el ancho real, no un límite fijo.
    public var textLine: String {
        guard let text = textContent else { return "" }
        return text
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .split(whereSeparator: { $0.isWhitespace })
            .joined(separator: " ")
    }

    /// Lo que la fila enseña: el texto capturado, o el título cuando el item
    /// está protegido. Nunca devuelve el contenido de un item protegido — es la
    /// única propiedad que deben usar las filas.
    public var displayLine: String {
        if isProtected {
            return trimmedTitle ?? "Elemento protegido"
        }
        return textLine
    }

    /// First 40 characters of the text, followed by "..." if truncated.
    public var textPreview: String {
        guard let text = textContent else { return "" }
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.count > 40 {
            return String(trimmed.prefix(40)) + "..."
        }
        return trimmed
    }

    // MARK: - Image loading

    /// URL del archivo de la imagen en disco. **Está cifrado**: no sirve para
    /// abrirlo con otra app ni con Quick Look. Para leer los bytes usa
    /// `ImageStorage.readData(filename:)`; para Quick Look,
    /// `QuickLookTemporaryFiles.makePlainCopy(ofImage:)`.
    public var imageFileURL: URL? {
        guard let filename = imageFilename else { return nil }
        return ImageStorage.directoryURL?.appendingPathComponent(filename)
    }

    /// Carga la imagen ya descifrada. `nil` si el archivo no existe, no se
    /// puede descifrar o no es una imagen válida. The original file size is
    /// preserved; callers scale for display as needed.
    public func loadImage() -> NSImage? {
        guard let filename = imageFilename else { return nil }
        return ImageStorage.loadImage(filename: filename)
    }

    // MARK: - Factory

    /// Creates a text clipboard item.
    public static func text(_ text: String) -> ClipboardItem {
        ClipboardItem(
            id: UUID(),
            contentType: .text,
            createdAt: Date(),
            textContent: text,
            imageFilename: nil,
            isFavorite: false
        )
    }

    /// Creates an image clipboard item. The PNG data is saved to disk,
    /// cifrada; the model stores only the filename. Si no se puede cifrar (sin
    /// llave), no se escribe nada —nunca en claro— y la fila sale sin miniatura.
    public static func image(pngData: Data) -> ClipboardItem {
        let id = UUID()
        let filename = "\(id.uuidString).png"
        // Sin archivo no hay hash: así una captura que no se pudo guardar no
        // se toma por duplicada de otra (y no la borra al deduplicar).
        var hash: String? = nil
        do {
            try ImageStorage.write(pngData: pngData, filename: filename)
            hash = ImageStorage.sha256Hex(pngData)
        } catch {
            NSLog("ClipboardManager: no se pudo guardar la imagen cifrada: \(error.localizedDescription)")
        }
        return ClipboardItem(
            id: id,
            contentType: .image,
            createdAt: Date(),
            textContent: nil,
            imageFilename: filename,
            isFavorite: false,
            imageHash: hash
        )
    }
}

// MARK: - Codable tolerante

extension ClipboardItem {

    /// Decodificación tolerante con los `store.json` escritos por versiones
    /// anteriores. El `init(from:)` sintetizado exige que **todas** las claves no
    /// opcionales estén presentes —los valores por defecto de las propiedades no
    /// se aplican al decodificar—, así que un archivo sin `isProtected` fallaría
    /// entero y el historial aparecería vacío. Va en una extensión para no
    /// suprimir el init por miembros que usan las factorías.
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        contentType = try container.decode(ClipboardContentType.self, forKey: .contentType)
        createdAt = try container.decode(Date.self, forKey: .createdAt)
        textContent = try container.decodeIfPresent(String.self, forKey: .textContent)
        imageFilename = try container.decodeIfPresent(String.self, forKey: .imageFilename)
        isFavorite = try container.decodeIfPresent(Bool.self, forKey: .isFavorite) ?? false
        groupID = try container.decodeIfPresent(UUID.self, forKey: .groupID)
        detail = try container.decodeIfPresent(String.self, forKey: .detail)
        title = try container.decodeIfPresent(String.self, forKey: .title)
        isProtected = try container.decodeIfPresent(Bool.self, forKey: .isProtected) ?? false
        sealedText = try container.decodeIfPresent(String.self, forKey: .sealedText)
        imageHash = try container.decodeIfPresent(String.self, forKey: .imageHash)
        stamps = try container.decodeIfPresent(ItemFieldStamps.self, forKey: .stamps) ?? ItemFieldStamps()
        deletion = try container.decodeIfPresent(SyncStamp.self, forKey: .deletion)
    }
}

/// Manages the images directory on disk. Cada archivo va cifrado con
/// `FileCipher`; los PNG en claro de versiones anteriores se siguen leyendo
/// hasta que `JSONPersistenceService.load()` los migra.
public enum ImageStorage {

    /// Imágenes ya descifradas, por nombre de archivo. Los archivos no cambian
    /// nunca (el nombre es un UUID nuevo por imagen), así que la caché solo se
    /// invalida al borrar. Evita descifrar cada miniatura en cada repintado.
    private static let decodedImages = NSCache<NSString, NSImage>()

    /// URL of the images directory, creating it if needed.
    public static var directoryURL: URL? {
        let appSupport = FileManager.default.urls(
            for: .applicationSupportDirectory, in: .userDomainMask
        ).first
        guard let base = appSupport else { return nil }
        let dir = base.appendingPathComponent("ClipboardManager/images", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    /// Deletes an image file from disk. The filename must be a bare filename
    /// (not a path) to prevent directory traversal.
    public static func delete(filename: String) {
        guard let dir = directoryURL else { return }
        // Basic path sanitisation: ensure no directory separators.
        guard !filename.contains("/") else { return }
        decodedImages.removeObject(forKey: filename as NSString)
        let fileURL = dir.appendingPathComponent(filename)
        try? FileManager.default.removeItem(at: fileURL)
    }

    /// SHA-256 en hexadecimal (minúsculas) de unos bytes: el `imageHash`.
    public static func sha256Hex(_ data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }

    private static let writesLock = NSLock()
    private static var writesBlocked = false

    /// `true` desde que la persistencia se ha bloqueado (datos que no se
    /// pudieron leer, llave que no está). Con él `write` no escribe nada.
    static var areWritesBlocked: Bool {
        writesLock.lock()
        defer { writesLock.unlock() }
        return writesBlocked
    }

    /// Lo llama `JSONPersistenceService` al bloquearse. No hay vuelta atrás en
    /// la misma ejecución, igual que con el resto de la persistencia.
    static func blockWrites() {
        writesLock.lock()
        defer { writesLock.unlock() }
        writesBlocked = true
    }

    /// Cifra los bytes de la imagen y los escribe de forma atómica. Lanza si
    /// la persistencia está bloqueada, si no hay llave o si no se puede
    /// escribir; nunca deja el PNG en claro.
    public static func write(pngData: Data, filename: String) throws {
        guard !areWritesBlocked else { throw PersistenceError.writesBlocked }
        guard let dir = directoryURL else { throw CocoaError(.fileNoSuchFile) }
        guard !filename.contains("/") else { throw CocoaError(.fileWriteInvalidFileName) }
        let key = try LocalKey.shared.key()
        let sealed = try FileCipher.seal(pngData, using: key)
        try sealed.write(to: dir.appendingPathComponent(filename), options: .atomic)
    }

    /// Bytes de la imagen ya descifrados. Un archivo en claro de una versión
    /// anterior (aún sin migrar) se devuelve tal cual. `nil` si no existe o no
    /// se puede descifrar.
    public static func readData(filename: String) -> Data? {
        guard let dir = directoryURL, !filename.contains("/") else { return nil }
        guard let raw = try? Data(contentsOf: dir.appendingPathComponent(filename)) else {
            return nil
        }
        guard FileCipher.isEncrypted(raw) else { return raw }
        do {
            let key = try LocalKey.shared.key()
            return try FileCipher.open(raw, using: key)
        } catch {
            NSLog("ClipboardManager: no se pudo descifrar la imagen \(filename): \(error.localizedDescription)")
            return nil
        }
    }

    /// La imagen descifrada como `NSImage`, desde la caché si ya se leyó.
    public static func loadImage(filename: String) -> NSImage? {
        if let cached = decodedImages.object(forKey: filename as NSString) {
            return cached
        }
        guard let data = readData(filename: filename), let image = NSImage(data: data) else {
            return nil
        }
        decodedImages.setObject(image, forKey: filename as NSString)
        return image
    }
}