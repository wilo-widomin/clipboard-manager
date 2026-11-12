//
//  PasswordGenerator.swift
//  ClipboardManagerKit
//
//  Generador de contraseñas del modal «Nueva contraseña». Es un valor puro
//  (sin AppKit ni estado) para poder probarlo aparte.
//

import Foundation

/// Opciones y generación de una contraseña aleatoria.
///
/// El azar sale de `SystemRandomNumberGenerator`, que en macOS es el generador
/// criptográfico del sistema, y se elige con `randomElement`, que no sufre el
/// sesgo del módulo.
public struct PasswordGenerator: Equatable, Sendable {

    /// Rango que ofrece el control deslizante del modal.
    public static let lengthRange = 8...64

    /// Símbolos que entran con el interruptor «Símbolos».
    public static let defaultSymbols = "!@#$%^&*()-_=+[]{};:,.?/"

    private static let uppercase = Array("ABCDEFGHIJKLMNOPQRSTUVWXYZ")
    private static let lowercase = Array("abcdefghijklmnopqrstuvwxyz")
    private static let digits = Array("0123456789")

    public var length: Int
    public var useUppercase: Bool
    public var useLowercase: Bool
    public var useDigits: Bool
    public var useSymbols: Bool

    /// Símbolos que escribe el usuario. Se suman a los de serie y, si el
    /// interruptor «Símbolos» está apagado, son los únicos que se usan.
    public var extraSymbols: String

    public init(
        length: Int = 16,
        useUppercase: Bool = true,
        useLowercase: Bool = true,
        useDigits: Bool = true,
        useSymbols: Bool = true,
        extraSymbols: String = ""
    ) {
        self.length = length
        self.useUppercase = useUppercase
        self.useLowercase = useLowercase
        self.useDigits = useDigits
        self.useSymbols = useSymbols
        self.extraSymbols = extraSymbols
    }

    /// Los símbolos en juego: los de serie (si toca) más los del usuario, sin
    /// espacios ni repetidos.
    var symbolPool: [Character] {
        let source = (useSymbols ? Self.defaultSymbols : "") + extraSymbols
        return Self.unique(Array(source).filter { !$0.isWhitespace })
    }

    /// Un grupo de caracteres por cada categoría activa y no vacía.
    private var pools: [[Character]] {
        var result: [[Character]] = []
        if useUppercase { result.append(Self.uppercase) }
        if useLowercase { result.append(Self.lowercase) }
        if useDigits { result.append(Self.digits) }
        let symbols = symbolPool
        if !symbols.isEmpty { result.append(symbols) }
        return result
    }

    /// False cuando no hay ninguna categoría activa: no hay con qué generar.
    public var canGenerate: Bool { !pools.isEmpty }

    /// Genera una contraseña con al menos un carácter de cada categoría activa.
    /// Si el largo pedido no llega para una por categoría, se sube al mínimo.
    /// Devuelve `nil` si no hay ninguna categoría activa.
    public func generate() -> String? {
        let pools = self.pools
        guard !pools.isEmpty else { return nil }

        let size = max(length, pools.count)
        let everything = Self.unique(pools.flatMap { $0 })
        var rng = SystemRandomNumberGenerator()

        // Uno de cada categoría, para que «con números» nunca salga sin ninguno.
        var chars = pools.compactMap { $0.randomElement(using: &rng) }
        while chars.count < size {
            if let next = everything.randomElement(using: &rng) { chars.append(next) }
        }
        chars.shuffle(using: &rng)
        return String(chars)
    }

    private static func unique(_ chars: [Character]) -> [Character] {
        var seen = Set<Character>()
        return chars.filter { seen.insert($0).inserted }
    }
}
