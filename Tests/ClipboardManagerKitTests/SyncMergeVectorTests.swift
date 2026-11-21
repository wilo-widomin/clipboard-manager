//
//  SyncMergeVectorTests.swift
//  ClipboardManagerKitTests
//
//  Pasa los vectores compartidos de `Tests/vectors/merge-vectors.json` por
//  `SyncMerge`. Los mismos vectores los pasarán Kotlin y Rust (§9 del
//  blueprint): si aquí cambia una regla, cambia el archivo y los otros dos
//  repos lo copian.
//

import XCTest
import ClipboardManagerKit

final class SyncMergeVectorTests: XCTestCase {

    private struct VectorFile: Decodable {
        let itemCases: [VectorCase<ClipboardItem>]
        let groupCases: [VectorCase<ClipboardGroup>]
    }

    private struct VectorCase<Record: Codable>: Decodable {
        let name: String
        let local: [Record]
        let remote: [Record]
        let expected: [Record]
    }

    /// `Tests/vectors/merge-vectors.json`, buscado desde este archivo: sin
    /// recursos de SwiftPM, para que el JSON quede en una carpeta neutra.
    private static var vectorsURL: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()  // ClipboardManagerKitTests
            .deletingLastPathComponent()  // Tests
            .appendingPathComponent("vectors/merge-vectors.json")
    }

    private func loadVectors() throws -> VectorFile {
        let data = try Data(contentsOf: Self.vectorsURL)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .millisecondsSince1970
        return try decoder.decode(VectorFile.self, from: data)
    }

    /// Compara codificando: JSON con claves ordenadas, para que un fallo
    /// enseñe exactamente qué campo difiere.
    private func encoded<T: Encodable>(_ value: T) throws -> String {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .millisecondsSince1970
        encoder.outputFormatting = [.sortedKeys, .prettyPrinted]
        return String(decoding: try encoder.encode(value), as: UTF8.self)
    }

    func testItemVectors() throws {
        let vectors = try loadVectors()
        XCTAssertFalse(vectors.itemCases.isEmpty)
        for vector in vectors.itemCases {
            let merged = SyncMerge.merge(local: vector.local, remote: vector.remote)
            let got = try encoded(merged)
            let expected = try encoded(vector.expected)
            XCTAssertEqual(got, expected, vector.name)
        }
    }

    func testGroupVectors() throws {
        let vectors = try loadVectors()
        XCTAssertFalse(vectors.groupCases.isEmpty)
        for vector in vectors.groupCases {
            let merged = SyncMerge.merge(local: vector.local, remote: vector.remote)
            let got = try encoded(merged)
            let expected = try encoded(vector.expected)
            XCTAssertEqual(got, expected, vector.name)
        }
    }

    /// En los vectores de items el orden de los lados no cambia el resultado:
    /// donde dos marcas empatan del todo, los dos lados tienen el mismo valor.
    /// (Con valores distintos y marcas idénticas ganaría `local`, a propósito;
    /// en los grupos, `isFilterEnabled` es siempre el local.)
    func testItemVectorsAreSymmetric() throws {
        let vectors = try loadVectors()
        for vector in vectors.itemCases {
            let ab = try encoded(SyncMerge.merge(local: vector.local, remote: vector.remote))
            let ba = try encoded(SyncMerge.merge(local: vector.remote, remote: vector.local))
            XCTAssertEqual(ab, ba, vector.name)
        }
    }
}
