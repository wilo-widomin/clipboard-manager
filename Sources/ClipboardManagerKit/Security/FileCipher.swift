//
//  FileCipher.swift
//  ClipboardManager
//
//  Cifrado de los archivos de datos en el borde de la persistencia.
//
//  Formato de un archivo cifrado (store.enc, groups.enc y cada imagen):
//
//      "CLPE" (4 bytes)  versión (1 byte, hoy 0x01)  AES.GCM combined
//                                                    (nonce 12 + cifrado + etiqueta 16)
//
//  La cabecera (los 5 primeros bytes) va además como dato autenticado (AAD): si
//  alguien la toca, el descifrado falla. Un archivo antiguo en claro nunca
//  empieza por "CLPE" (un JSON empieza por `[` y un PNG por 0x89 'P' 'N' 'G'),
//  así que el lector distingue sin ambigüedad lo cifrado de lo heredado.
//

import Foundation
import CryptoKit

/// Errores al cifrar o descifrar un archivo de datos.
public enum FileCipherError: Error, LocalizedError {
    case notEncrypted
    case unsupportedVersion(UInt8)
    case sealFailed

    public var errorDescription: String? {
        switch self {
        case .notEncrypted:
            return "El archivo no tiene la cabecera de cifrado."
        case .unsupportedVersion(let version):
            return "El archivo está cifrado con un formato desconocido (versión \(version)); lo escribió una versión más nueva de la app."
        case .sealFailed:
            return "No se pudo cifrar el archivo."
        }
    }
}

/// AES-256-GCM con nonce aleatorio por escritura. Sin estado: la llave la
/// pone quien llama (ver `LocalKey`).
enum FileCipher {

    /// "CLPE": marca de archivo cifrado de Clipboard Manager.
    static let magic = Data([0x43, 0x4C, 0x50, 0x45])

    /// Versión del formato que se escribe hoy.
    static let currentVersion: UInt8 = 1

    /// Cabecera completa (marca + versión) para una versión dada.
    static func header(version: UInt8 = currentVersion) -> Data {
        var header = magic
        header.append(version)
        return header
    }

    /// Longitud de la cabecera: marca + 1 byte de versión.
    static var headerLength: Int { magic.count + 1 }

    /// `true` si los bytes empiezan por la marca de cifrado. No comprueba que
    /// el resto sea válido: eso lo hace `open`.
    static func isEncrypted(_ data: Data) -> Bool {
        data.starts(with: magic)
    }

    /// Cifra `plaintext` con un nonce aleatorio nuevo y devuelve el archivo
    /// completo, cabecera incluida.
    static func seal(_ plaintext: Data, using key: SymmetricKey) throws -> Data {
        let head = Self.header()
        // Sin `nonce:` CryptoKit genera uno aleatorio de 12 bytes en cada llamada.
        let box = try AES.GCM.seal(plaintext, using: key, authenticating: head)
        guard let combined = box.combined else { throw FileCipherError.sealFailed }
        var output = head
        output.append(combined)
        return output
    }

    /// Descifra un archivo completo (cabecera incluida). Lanza si no está
    /// cifrado, si la versión es desconocida o si la etiqueta GCM no cuadra
    /// (llave equivocada o archivo manipulado).
    static func open(_ data: Data, using key: SymmetricKey) throws -> Data {
        guard data.count > headerLength, isEncrypted(data) else {
            throw FileCipherError.notEncrypted
        }
        let version = data[data.index(data.startIndex, offsetBy: magic.count)]
        guard version == currentVersion else {
            throw FileCipherError.unsupportedVersion(version)
        }
        let body = Data(data.dropFirst(headerLength))
        let box = try AES.GCM.SealedBox(combined: body)
        return try AES.GCM.open(box, using: key, authenticating: header(version: version))
    }

    /// Lee solo los primeros bytes de un archivo para saber si está cifrado,
    /// sin cargarlo entero. `false` si no existe o no se puede leer.
    static func fileIsEncrypted(at url: URL) -> Bool {
        guard let handle = try? FileHandle(forReadingFrom: url) else { return false }
        defer { try? handle.close() }
        guard let head = try? handle.read(upToCount: magic.count) else { return false }
        return isEncrypted(head)
    }
}
