import Foundation
import XCTest
@testable import SolanaRPC

final class AnyJSONTests: XCTestCase {
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    // MARK: - Per-case round trip

    func test_string_roundTrip() throws {
        try assertRoundTrip(.string("hello"), expectedJSON: "\"hello\"")
    }

    func test_number_roundTrip_integerPreserved() throws {
        try assertRoundTrip(.number(Decimal(42)), expectedJSON: "42")
    }

    func test_number_roundTrip_largeUInt64Decimal() throws {
        // 18446744073709551615 is UInt64.max — Double would lose precision.
        let decimal = Decimal(string: "18446744073709551615")!
        try assertRoundTrip(.number(decimal), expectedJSON: "18446744073709551615")
    }

    func test_bool_true_roundTrip() throws {
        try assertRoundTrip(.bool(true), expectedJSON: "true")
    }

    func test_bool_false_roundTrip() throws {
        try assertRoundTrip(.bool(false), expectedJSON: "false")
    }

    func test_null_roundTrip() throws {
        try assertRoundTrip(.null, expectedJSON: "null")
    }

    func test_array_nested_roundTrip() throws {
        let value: AnyJSON = .array([.string("a"), .number(1), .bool(true), .null, .array([.string("b")])])
        let data = try encoder.encode(value)
        let decoded = try decoder.decode(AnyJSON.self, from: data)
        XCTAssertEqual(decoded, value)
    }

    func test_object_nested_roundTrip() throws {
        let value: AnyJSON = .object([
            "name": .string("zodsol"),
            "count": .number(3),
            "active": .bool(true),
            "missing": .null,
            "nested": .object(["a": .array([.number(1), .number(2)])]),
        ])
        let data = try encoder.encode(value)
        let decoded = try decoder.decode(AnyJSON.self, from: data)
        XCTAssertEqual(decoded, value)
    }

    // MARK: - Decode-ordering correctness

    func test_decode_jsonTrue_decodesAsBoolNotNumber() throws {
        let data = "true".data(using: .utf8)!
        let decoded = try decoder.decode(AnyJSON.self, from: data)
        XCTAssertEqual(decoded, .bool(true), "JSON true must decode as .bool(true) — not .number(1)")
        if case .number = decoded {
            XCTFail("JSON true must not decode as .number")
        }
    }

    func test_decode_jsonFalse_decodesAsBoolNotNumber() throws {
        let data = "false".data(using: .utf8)!
        let decoded = try decoder.decode(AnyJSON.self, from: data)
        XCTAssertEqual(decoded, .bool(false))
        if case .number = decoded {
            XCTFail("JSON false must not decode as .number")
        }
    }

    // MARK: - Helius-style round trip

    func test_heliusStyleFragment_roundTrip() throws {
        let json = #"""
        {
          "items": [
            {
              "id": "asset-1",
              "interface": "ProgrammableNFT",
              "ownership": {
                "owner": "owner-pubkey",
                "delegate": null
              },
              "compression": {
                "compressed": false,
                "seq": 0
              },
              "supply": null,
              "burnt": false
            }
          ],
          "total": 1,
          "limit": 100,
          "cursor": "abc"
        }
        """#.data(using: .utf8)!

        let decoded = try decoder.decode(AnyJSON.self, from: json)
        let reEncoded = try encoder.encode(decoded)
        let decodedAgain = try decoder.decode(AnyJSON.self, from: reEncoded)
        XCTAssertEqual(decoded, decodedAgain, "Helius-style payload must round-trip losslessly")

        // Spot checks on the decoded structure.
        guard case .object(let root) = decoded else {
            XCTFail("expected object root")
            return
        }
        XCTAssertEqual(root["total"], .number(1))
        XCTAssertEqual(root["cursor"], .string("abc"))
        guard case .array(let items) = root["items"] ?? .null,
              case .object(let first) = items.first ?? .null else {
            XCTFail("expected items[0] to be an object")
            return
        }
        XCTAssertEqual(first["id"], .string("asset-1"))
        XCTAssertEqual(first["burnt"], .bool(false))
        guard case .object(let ownership) = first["ownership"] ?? .null else {
            XCTFail("expected ownership object")
            return
        }
        XCTAssertEqual(ownership["delegate"], .null)
        XCTAssertEqual(ownership["owner"], .string("owner-pubkey"))
    }

    // MARK: - Helpers

    private func assertRoundTrip(_ value: AnyJSON, expectedJSON: String, file: StaticString = #filePath, line: UInt = #line) throws {
        let data = try encoder.encode(value)
        let json = try XCTUnwrap(String(data: data, encoding: .utf8), file: file, line: line)
        XCTAssertEqual(json, expectedJSON, file: file, line: line)
        let decoded = try decoder.decode(AnyJSON.self, from: data)
        XCTAssertEqual(decoded, value, file: file, line: line)
    }
}
