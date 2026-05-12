import CryptoKit
import SolanaKit
import XCTest
@testable import WalletOverviewDomain

final class ImportedPrivateKeyTests: XCTestCase {
    func testParseValidBase58Succeeds() throws {
        let material = makeTestPrivateKey()
        let imported = try ImportedPrivateKey.parse(material.base58Key)
        XCTAssertEqual(imported.publicAddress.base58, material.base58Address)
        XCTAssertEqual(imported.secretKey64, material.secretKey64)
    }

    func testParseValidJSONArraySucceeds() throws {
        let material = makeTestPrivateKey()
        let bytes = Array(material.secretKey64)
        let json = "[\(bytes.map { String($0) }.joined(separator: ","))]"
        let imported = try ImportedPrivateKey.parse(json)
        XCTAssertEqual(imported.publicAddress.base58, material.base58Address)
        XCTAssertEqual(imported.secretKey64, material.secretKey64)
    }

    func testParseJSONArrayHandlesWhitespacePrefix() throws {
        let material = makeTestPrivateKey()
        let bytes = Array(material.secretKey64)
        let json = "  \n[\(bytes.map { String($0) }.joined(separator: ","))]\n"
        let imported = try ImportedPrivateKey.parse(json)
        XCTAssertEqual(imported.publicAddress.base58, material.base58Address)
    }

    func testParseTooShortBase58Throws() {
        let short = Base58.encode(Data(repeating: 0xAB, count: 63))
        XCTAssertThrowsError(try ImportedPrivateKey.parse(short)) { error in
            guard case let WalletOverviewError.malformedResponse(message) = error else {
                return XCTFail("expected malformedResponse, got \(error)")
            }
            XCTAssertTrue(message.contains("64"), "got message: \(message)")
        }
    }

    func testParseTooLongBase58Throws() {
        let long = Base58.encode(Data(repeating: 0xAB, count: 65))
        XCTAssertThrowsError(try ImportedPrivateKey.parse(long)) { error in
            guard case let WalletOverviewError.malformedResponse(message) = error else {
                return XCTFail("expected malformedResponse, got \(error)")
            }
            XCTAssertTrue(message.contains("64"), "got message: \(message)")
        }
    }

    func testParseTooShortJSONArrayThrows() {
        let bytes = Array(repeating: UInt8(1), count: 63)
        let json = "[\(bytes.map { String($0) }.joined(separator: ","))]"
        XCTAssertThrowsError(try ImportedPrivateKey.parse(json)) { error in
            guard case let WalletOverviewError.malformedResponse(message) = error else {
                return XCTFail("expected malformedResponse, got \(error)")
            }
            XCTAssertTrue(message.contains("64"), "got message: \(message)")
        }
    }

    func testParseTooLongJSONArrayThrows() {
        let bytes = Array(repeating: UInt8(1), count: 65)
        let json = "[\(bytes.map { String($0) }.joined(separator: ","))]"
        XCTAssertThrowsError(try ImportedPrivateKey.parse(json)) { error in
            guard case WalletOverviewError.malformedResponse = error else {
                return XCTFail("expected malformedResponse, got \(error)")
            }
        }
    }

    func testParsePublicKeyMismatchThrows() {
        let material = makeTestPrivateKey()
        var corrupted = material.secretKey64
        corrupted[corrupted.count - 1] ^= 0xFF
        let encoded = Base58.encode(corrupted)
        XCTAssertThrowsError(try ImportedPrivateKey.parse(encoded)) { error in
            guard case let WalletOverviewError.malformedResponse(message) = error else {
                return XCTFail("expected malformedResponse, got \(error)")
            }
            XCTAssertTrue(message.lowercased().contains("public key"))
        }
    }

    func testParseInvalidBase58CharThrows() {
        let invalid = "ThisHasInvalid0OIlChars"
        XCTAssertThrowsError(try ImportedPrivateKey.parse(invalid)) { error in
            guard case WalletOverviewError.malformedResponse = error else {
                return XCTFail("expected malformedResponse, got \(error)")
            }
        }
    }
}
