import XCTest
@testable import SolanaKit

final class LamportsTests: XCTestCase {
    func testExpressibleByIntegerLiteral() {
        let value: Lamports = 1_000_000_000
        XCTAssertEqual(value.rawValue, 1_000_000_000)
    }

    func testInitializerStoresRawValue() {
        let value = Lamports(rawValue: 42)
        XCTAssertEqual(value.rawValue, 42)
    }

    func testLamportsPerSolConstant() {
        XCTAssertEqual(Lamports.lamportsPerSol, 1_000_000_000)
    }

    func testSolValueForOneSol() {
        let oneSol: Lamports = 1_000_000_000
        XCTAssertEqual(oneSol.solValue, 1.0, accuracy: 1e-12)
    }

    func testSolValueForFractionalSol() {
        let half: Lamports = 500_000_000
        XCTAssertEqual(half.solValue, 0.5, accuracy: 1e-12)
    }

    func testSolValueForZero() {
        let zero: Lamports = 0
        XCTAssertEqual(zero.solValue, 0.0, accuracy: 1e-12)
    }

    func testSolValueForLargeAmount() {
        // 12.345 SOL in lamports.
        let value: Lamports = 12_345_000_000
        XCTAssertEqual(value.solValue, 12.345, accuracy: 1e-9)
    }

    func testHashableAndEquatable() {
        let a: Lamports = 100
        let b: Lamports = 100
        let c: Lamports = 200
        XCTAssertEqual(a, b)
        XCTAssertEqual(a.hashValue, b.hashValue)
        XCTAssertNotEqual(a, c)
    }

    func testCodableRoundTrip() throws {
        let original: Lamports = 9_876_543_210
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(Lamports.self, from: data)
        XCTAssertEqual(original, decoded)
    }

    func testCodableEncodesAsScalarUInt64() throws {
        let value: Lamports = 1_234_567_890
        let data = try JSONEncoder().encode(value)
        XCTAssertEqual(String(data: data, encoding: .utf8), "1234567890")
    }
}
