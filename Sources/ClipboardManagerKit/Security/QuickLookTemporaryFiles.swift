//
//  QuickLookTemporaryFiles.swift
//  ClipboardManager
//
//  Quick Look necesita la ruta de un archivo, y las imágenes están cifradas en
//  disco. Para enseñarlas se descifra una copia en una carpeta temporal privada
//  (permisos 0700, archivo 0600) y se borra al cerrar la vista rápida o, como
//  muy tarde, en el siguiente arranque (`purge`, que llama
//  `JSONPersistenceService.load()`).
//

import Foundation

public enum QuickLookTemporaryFiles {

    /// Carpeta privada dentro del `$TMPDIR` del usuario (que ya es solo suyo).
    /// Lleva el bundle id para que dos anfitriones abiertos a la vez (la app
    /// suelta y Widomin) no se borren las copias el uno al otro.
    static var directoryURL: URL {
        let host = Bundle.main.bundleIdentifier ?? "host"
        return FileManager.default.temporaryDirectory
            .appendingPathComponent("ClipboardManagerKit-QuickLook-\(host)", isDirectory: true)
    }

    /// Descifra la imagen `filename` en una copia temporal con extensión
    /// `.png` y devuelve su URL. Quien la abre debe llamar a `remove(_:)` al
    /// terminar. `nil` si la imagen no se puede leer o la copia no se puede
    /// escribir.
    public static func makePlainCopy(ofImage filename: String) -> URL? {
        guard let data = ImageStorage.readData(filename: filename) else { return nil }
        let fileManager = FileManager.default
        let directory = directoryURL
        do {
            try fileManager.createDirectory(
                at: directory,
                withIntermediateDirectories: true,
                attributes: [.posixPermissions: 0o700]
            )
            // Por si la carpeta ya existía con otros permisos.
            try fileManager.setAttributes([.posixPermissions: 0o700], ofItemAtPath: directory.path)
        } catch {
            NSLog("ClipboardManager: no se pudo preparar la carpeta temporal de Quick Look: \(error.localizedDescription)")
            return nil
        }
        let url = directory.appendingPathComponent("\(UUID().uuidString).png")
        let created = fileManager.createFile(
            atPath: url.path,
            contents: data,
            attributes: [.posixPermissions: 0o600]
        )
        return created ? url : nil
    }

    /// Borra una copia hecha por `makePlainCopy`. Se puede llamar desde
    /// cualquier hilo.
    public static func remove(_ url: URL) {
        try? FileManager.default.removeItem(at: url)
    }

    /// Borra todas las copias que quedaran de una sesión anterior.
    public static func purge() {
        try? FileManager.default.removeItem(at: directoryURL)
    }
}
