//
//  ProtectedTextCipher.swift
//  ClipboardManagerKit
//
//  Cifrado del texto de los items protegidos con la `protectedKey` (ver
//  `ProtectedKey` y docs/05-blueprint-sync-android.md, §3.2).
//
//  Por qué con llave pública y privada (X25519) y no con una sola llave AES:
//  cifrar necesita solo la parte pública, que se lee sin pedir nada; descifrar
//  necesita la privada, que solo sale del Llavero tras Touch ID o la
//  contraseña del Mac. Así proteger un item, crear una contraseña a mano o
//  migrar los items antiguos no piden el dedo; solo lo pide **ver** el texto.
//
//  Cada cifrado usa una llave efímera nueva (ECIES clásico):
//
//      secreto  = X25519(efímera privada, protectedKey pública)
//      llaveAES = HKDF-SHA256(secreto, sal = efímera pública ‖ protectedKey pública,
//                             info = "ClipboardManager protected text v1", 32 bytes)
//
//  Formato (en base64 dentro de `ClipboardItem.sealedText`):
//
//      "CLPP" (4)  versión (1, hoy 0x01)  efímera pública (32)  AES.GCM combined
//                                                               (nonce 12 + cifrado + etiqueta 16)
//
//  Cabecera y llave efímera van además como dato autenticado: tocarlas hace
//  fallar el descifrado.
//

import Foundation
import CryptoKit

/// Errores al cifrar o descifrar el texto de un item protegido.
public enum ProtectedTextCipherError: Error, LocalizedError {
    case malformed
    case unsupportedVersion(UInt8)
    case sealFailed
    case notUTF8

    public var errorDescription: String? {
        switch self {
        case .malformed:
            return "El texto protegido guardado no tiene el formato esperado."
        case .unsupportedVersion(let version):
            return "El texto protegido está cifrado con un formato desconocido (versión \(version)); lo escribió una versión más nueva de la app."
        case .sealFailed:
            return "No se pudo cifrar el texto protegido."
        case .notUTF8:
            return "El texto protegido descifrado no es texto válido."
        }
    }
}

enum ProtectedTextCipher {

    /// "CLPP": marca de texto protegido de Clipboard Manager.
    static let magic = Data([0x43, 0x4C, 0x50, 0x50])

    static let currentVersion: UInt8 = 1

    private static let publicKeyLength = 32
    private static let info = Data("ClipboardManager protected text v1".utf8)

    private static func header(version: UInt8 = currentVersion) -> Data {
        var header = magic
        header.append(version)
        return header
    }

    private static var headerLength: Int { magic.count + 1 }

    /// Cifra `text` para el dueño de `recipient`. Solo hace falta la llave
    /// pública: no pide autenticación.
    static func seal(_ text: String, to recipient: Curve25519.KeyAgreement.PublicKey) throws -> String {
        let ephemeral = Curve25519.KeyAgreement.PrivateKey()
        let ephemeralPublic = ephemeral.publicKey.rawRepresentation
        let secret = try ephemeral.sharedSecretFromKeyAgreement(with: recipient)
        let key = derivedKey(from: secret,
                             ephemeralPublic: ephemeralPublic,
                             recipientPublic: recipient.rawRepresentation)

        var authenticated = header()
        authenticated.append(ephemeralPublic)
        let box = try AES.GCM.seal(Data(text.utf8), using: key, authenticating: authenticated)
        guard let combined = box.combined else { throw ProtectedTextCipherError.sealFailed }

        var output = authenticated
        output.append(combined)
        return output.base64EncodedString()
    }

    /// Descifra con la llave privada (la que solo entrega el Llavero tras
    /// autenticar). Lanza si el formato no cuadra o la llave no es la suya.
    static func open(_ sealed: String, with privateKey: Curve25519.KeyAgreement.PrivateKey) throws -> String {
        guard let data = Data(base64Encoded: sealed),
              data.count > headerLength + publicKeyLength,
              data.starts(with: magic)
        else { throw ProtectedTextCipherError.malformed }

        let version = data[magic.count]
        guard version == currentVersion else {
            throw ProtectedTextCipherError.unsupportedVersion(version)
        }

        let ephemeralEnd = headerLength + publicKeyLength
        let ephemeralPublic = data.subdata(in: headerLength..<ephemeralEnd)
        let body = data.subdata(in: ephemeralEnd..<data.count)

        let ephemeral = try Curve25519.KeyAgreement.PublicKey(rawRepresentation: ephemeralPublic)
        let secret = try privateKey.sharedSecretFromKeyAgreement(with: ephemeral)
        let key = derivedKey(from: secret,
                             ephemeralPublic: ephemeralPublic,
                             recipientPublic: privateKey.publicKey.rawRepresentation)

        var authenticated = header(version: version)
        authenticated.append(ephemeralPublic)
        let box = try AES.GCM.SealedBox(combined: body)
        let plaintext = try AES.GCM.open(box, using: key, authenticating: authenticated)
        guard let text = String(data: plaintext, encoding: .utf8) else {
            throw ProtectedTextCipherError.notUTF8
        }
        return text
    }

    private static func derivedKey(from secret: SharedSecret,
                                   ephemeralPublic: Data,
                                   recipientPublic: Data) -> SymmetricKey {
        var salt = ephemeralPublic
        salt.append(recipientPublic)
        return secret.hkdfDerivedSymmetricKey(using: SHA256.self,
                                              salt: salt,
                                              sharedInfo: info,
                                              outputByteCount: 32)
    }
}
