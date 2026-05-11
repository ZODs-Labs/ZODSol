import XCTest
@testable import SolanaKit

final class WalletAddressTests: XCTestCase {
    // Real 32-byte Solana addresses; valid base58 with decoded length 32.
    private let usdcMint = "EPjFWdd5AufqSSqeM2qN1xzybapC8G4wEGGkZwyTDt1v"
    private let wrappedSol = "So11111111111111111111111111111111111111112"
    private let systemProgram = "11111111111111111111111111111111"

    func testValid32ByteAddressIsAccepted() throws {
        let address = try WalletAddress(base58: usdcMint)
        XCTAssertEqual(address.base58, usdcMint)
        XCTAssertEqual(address.description, usdcMint)
    }

    func testValidAddressWithLeadingOnes() throws {
        // The system program address decodes to 32 zero bytes — exercises the
        // leading-zero path of the Base58 decoder.
        let address = try WalletAddress(base58: systemProgram)
        XCTAssertEqual(address.base58, systemProgram)
    }

    func testValidWrappedSolAddress() throws {
        let address = try WalletAddress(base58: wrappedSol)
        XCTAssertEqual(address.base58, wrappedSol)
    }

    func testRejects31BytePayload() {
        // Encode 31 random-looking bytes as base58 and confirm it is rejected.
        let bytes = Data((0..<31).map { UInt8($0 + 1) })
        let encoded = Base58.encode(bytes)
        XCTAssertEqual(try Base58.decode(encoded).count, 31)
        XCTAssertThrowsError(try WalletAddress(base58: encoded)) { error in
            assertInvalidInput(error)
        }
    }

    func testRejects33BytePayload() {
        let bytes = Data((0..<33).map { UInt8($0 + 1) })
        let encoded = Base58.encode(bytes)
        XCTAssertEqual(try Base58.decode(encoded).count, 33)
        XCTAssertThrowsError(try WalletAddress(base58: encoded)) { error in
            assertInvalidInput(error)
        }
    }

    func testRejectsInvalidAlphabetCharacters() {
        // The Bitcoin base58 alphabet omits '0', 'O', 'I', and 'l'.
        let invalidSamples = [
            "0PjFWdd5AufqSSqeM2qN1xzybapC8G4wEGGkZwyTDt1v",   // '0'
            "OPjFWdd5AufqSSqeM2qN1xzybapC8G4wEGGkZwyTDt1v",   // 'O'
            "IPjFWdd5AufqSSqeM2qN1xzybapC8G4wEGGkZwyTDt1v",   // 'I'
            "lPjFWdd5AufqSSqeM2qN1xzybapC8G4wEGGkZwyTDt1v",   // 'l'
        ]
        for sample in invalidSamples {
            XCTAssertThrowsError(try WalletAddress(base58: sample),
                                 "Expected rejection of '\(sample)'") { error in
                assertInvalidInput(error)
            }
        }
    }

    func testRejectsEmptyString() {
        XCTAssertThrowsError(try WalletAddress(base58: "")) { error in
            assertInvalidInput(error)
        }
    }

    func testShortenedDefaultPrefixAndSuffix() throws {
        let address = try WalletAddress(base58: usdcMint)
        XCTAssertEqual(address.shortened(), "EPjF…Dt1v")
    }

    func testShortenedCustomPrefixAndSuffix() throws {
        let address = try WalletAddress(base58: usdcMint)
        XCTAssertEqual(address.shortened(prefix: 6, suffix: 2), "EPjFWd…1v")
    }

    func testCodableRoundTripPreservesAndRevalidates() throws {
        let original = try WalletAddress(base58: usdcMint)
        let encoded = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(WalletAddress.self, from: encoded)
        XCTAssertEqual(original, decoded)
    }

    func testCodableDecodeRejectsInvalidPayload() {
        let payload = Data(#""not_base58_0OIl""#.utf8)
        XCTAssertThrowsError(try JSONDecoder().decode(WalletAddress.self, from: payload))
    }

    func testHashableSemantics() throws {
        let a = try WalletAddress(base58: usdcMint)
        let b = try WalletAddress(base58: usdcMint)
        let c = try WalletAddress(base58: wrappedSol)
        XCTAssertEqual(a, b)
        XCTAssertEqual(a.hashValue, b.hashValue)
        XCTAssertNotEqual(a, c)
    }

    // MARK: - Helpers

    private func assertInvalidInput(_ error: any Error,
                                    file: StaticString = #filePath,
                                    line: UInt = #line) {
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
