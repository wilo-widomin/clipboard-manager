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

/// The type of content stored in a clipboard item.
public enum ClipboardContentType: String, Codable, Sendable {
    case text
    case image
}

/// A single clipboard entry captured by the monitor.
public struct ClipboardItem: Identifiable, Codable, Sendable {

    public let id: UUID
    public let contentType: ClipboardContentType
    public let createdAt: Date

    /// The text content (nil for image items). Mutable because the right-click
    /// editor lets the user rewrite what was captured.
    public var textContent: String?

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
    /// thumbnail, so hiding its text would protect nothing.
    public var isProtected: Bool = false

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
        do {
            try ImageStorage.write(pngData: pngData, filename: filename)
        } catch {
            NSLog("ClipboardManager: no se pudo guardar la imagen cifrada: \(error.localizedDescription)")
        }
        return ClipboardItem(
            id: id,
            contentType: .image,
            createdAt: Date(),
            textContent: nil,
            imageFilename: filename,
            isFavorite: false
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

    /// Cifra los bytes de la imagen y los escribe de forma atómica. Lanza si
    /// no hay llave o no se puede escribir; nunca deja el PNG en claro.
    public static func write(pngData: Data, filename: String) throws {
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