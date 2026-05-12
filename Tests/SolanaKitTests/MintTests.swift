import XCTest
@testable import SolanaKit

final class MintTests: XCTestCase {
    private let usdcMint = "EPjFWdd5AufqSSqeM2qN1xzybapC8G4wEGGkZwyTDt1v"
    private let wrappedSol = "So11111111111111111111111111111111111111112"

    func testValid32ByteMintIsAccepted() throws {
        let mint = try Mint(base58: usdcMint)
        XCTAssertEqual(mint.base58, self.usdcMint)
    }

    func testRejects31BytePayload() {
        let bytes = Data((0..<31).map { UInt8($0 + 1) })
        let encoded = Base58.encode(bytes)
        XCTAssertEqual(try Base58.decode(encoded).count, 31)
        XCTAssertThrowsError(try Mint(base58: encoded)) { error in
            self.assertInvalidInput(error)
        }
    }

    func testRejects33BytePayload() {
        let bytes = Data((0..<33).map { UInt8($0 + 1) })
        let encoded = Base58.encode(bytes)
        XCTAssertEqual(try Base58.decode(encoded).count, 33)
        XCTAssertThrowsError(try Mint(base58: encoded)) { error in
            self.assertInvalidInput(error)
        }
    }

    func testRejectsInvalidAlphabetCharacters() {
        let invalidSamples = [
            "0PjFWdd5AufqSSqeM2qN1xzybapC8G4wEGGkZwyTDt1v",
            "OPjFWdd5AufqSSqeM2qN1xzybapC8G4wEGGkZwyTDt1v",
            "IPjFWdd5AufqSSqeM2qN1xzybapC8G4wEGGkZwyTDt1v",
            "lPjFWdd5AufqSSqeM2qN1xzybapC8G4wEGGkZwyTDt1v",
        ]
        for sample in invalidSamples {
            XCTAssertThrowsError(
                try Mint(base58: sample),
                "Expected rejection of '\(sample)'")
            { error in
                self.assertInvalidInput(error)
            }
        }
    }

    func testHashableUsableAsDictionaryKey() throws {
        let a = try Mint(base58: usdcMint)
        let b = try Mint(base58: usdcMint)
        let c = try Mint(base58: wrappedSol)
        var bucket: [Mint: Int] = [:]
        bucket[a] = 1
        bucket[b] = 2 // Overwrites — same key.
        bucket[c] = 3
        XCTAssertEqual(bucket.count, 2)
        XCTAssertEqual(bucket[a], 2)
        XCTAssertEqual(bucket[c], 3)
    }

    func testCodableRoundTripPreservesAndRevalidates() throws {
        let original = try Mint(base58: usdcMint)
        let encoded = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(Mint.self, from: encoded)
        XCTAssertEqual(original, decoded)
    }

    func testCodableDecodeRejectsInvalidPayload() {
        let payload = Data(#""not_base58_0OIl""#.utf8)
        XCTAssertThrowsError(try JSONDecoder().decode(Mint.self, from: payload))
    }

    // MARK: - Helpers

    private func assertInvalidInput(
        _ error: any Error,
        file: StaticString = #filePath,
        line: UInt = #line)
    {
        guard let providerError = error as? SolanaProviderError else {
            XCTFail("Expected SolanaProviderError, got \(error)", file: file, line: line)
            return
        }
        if case .invalidInput = providerError {
            // ok
        } else {
            XCTFail("Expected .invalidInput, got \(providerError)", file: file, line: line)
        }
    }
}
