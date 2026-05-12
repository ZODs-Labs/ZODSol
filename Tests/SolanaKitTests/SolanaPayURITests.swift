import XCTest
@testable import SolanaKit

final class SolanaPayURITests: XCTestCase {
    private let recipientBase58 = "So11111111111111111111111111111111111111112"
    private let usdcMintBase58 = "EPjFWdd5AufqSSqeM2qN1xzybapC8G4wEGGkZwyTDt1v"
    private let firstReferenceBase58 = "11111111111111111111111111111111"
    private let secondReferenceBase58 = "metaqbxxUerdq28cj1RbAWkYQm3ybzjb6a8bt518x1s"

    private func makeRecipient() throws -> WalletAddress {
        try WalletAddress(base58: recipientBase58)
    }

    func testRoundTripRecipientOnly() throws {
        let recipient = try makeRecipient()
        let url = try SolanaPayURIBuilder.build(recipient: recipient)
        XCTAssertEqual(url.absoluteString, "solana:\(recipientBase58)")

        let parsed = try SolanaPayURIParser.parse(url.absoluteString)
        let expected = SolanaPayURI(
            recipient: recipient,
            amount: nil,
            splToken: nil,
            label: nil,
            message: nil,
            memo: nil,
            references: []
        )
        XCTAssertEqual(parsed, expected)
    }

    func testRoundTripWithAmount() throws {
        let recipient = try makeRecipient()
        let url = try SolanaPayURIBuilder.build(recipient: recipient, amount: Decimal(string: "1.5"))
        XCTAssertTrue(url.absoluteString.contains("amount=1.5"))

        let parsed = try SolanaPayURIParser.parse(url.absoluteString)
        XCTAssertEqual(parsed.recipient, recipient)
        XCTAssertEqual(parsed.amount, Decimal(string: "1.5"))
        XCTAssertNil(parsed.splToken)
    }

    func testRoundTripWithSplToken() throws {
        let recipient = try makeRecipient()
        let usdc = try Mint(base58: usdcMintBase58)
        let url = try SolanaPayURIBuilder.build(recipient: recipient, splToken: usdc)
        XCTAssertTrue(url.absoluteString.contains("spl-token=\(usdcMintBase58)"))

        let parsed = try SolanaPayURIParser.parse(url.absoluteString, expectedDecimals: 6)
        XCTAssertEqual(parsed.recipient, recipient)
        XCTAssertEqual(parsed.splToken, usdc)
        XCTAssertNil(parsed.amount)
    }

    func testRoundTripWithLabelMessageMemo() throws {
        let recipient = try makeRecipient()
        let label = "Thanks for fish"
        let message = "Order #12345"
        let memo = "memo with \"quotes\""
        let url = try SolanaPayURIBuilder.build(
            recipient: recipient,
            label: label,
            message: message,
            memo: memo
        )
        // Each value must be percent-encoded in the URL representation.
        XCTAssertFalse(url.absoluteString.contains("Thanks for fish"))
        XCTAssertFalse(url.absoluteString.contains("Order #12345"))

        let parsed = try SolanaPayURIParser.parse(url.absoluteString)
        XCTAssertEqual(parsed.label, label)
        XCTAssertEqual(parsed.message, message)
        XCTAssertEqual(parsed.memo, memo)
    }

    func testRoundTripWithTwoReferences() throws {
        let recipient = try makeRecipient()
        let first = try WalletAddress(base58: firstReferenceBase58)
        let second = try WalletAddress(base58: secondReferenceBase58)
        let url = try SolanaPayURIBuilder.build(
            recipient: recipient,
            references: [first, second]
        )
        let parsed = try SolanaPayURIParser.parse(url.absoluteString)
        XCTAssertEqual(parsed.references, [first, second])
    }

    func testMissingOptionalFields() throws {
        let parsed = try SolanaPayURIParser.parse("solana:\(recipientBase58)")
        XCTAssertEqual(parsed.recipient.base58, recipientBase58)
        XCTAssertNil(parsed.amount)
        XCTAssertNil(parsed.splToken)
        XCTAssertNil(parsed.label)
        XCTAssertNil(parsed.message)
        XCTAssertNil(parsed.memo)
        XCTAssertEqual(parsed.references, [])
    }

    func testMalformedSchemeRejected() {
        XCTAssertThrowsError(try SolanaPayURIParser.parse("https://example.com")) { error in
            XCTAssertEqual(error as? SolanaPayParseError, .notASolanaPayURI)
        }
    }

    func testUppercaseSchemeRejected() {
        XCTAssertThrowsError(try SolanaPayURIParser.parse("SOLANA:\(recipientBase58)")) { error in
            XCTAssertEqual(error as? SolanaPayParseError, .notASolanaPayURI)
        }
    }

    func testWhitespaceAcceptedAfterTrim() throws {
        let parsed = try SolanaPayURIParser.parse("  solana:\(recipientBase58)  ")
        XCTAssertEqual(parsed.recipient.base58, recipientBase58)
    }

    func testExcessDecimalsRejected() {
        let raw = "solana:\(recipientBase58)?amount=0.0000000001"
        XCTAssertThrowsError(try SolanaPayURIParser.parse(raw, expectedDecimals: 9)) { error in
            XCTAssertEqual(error as? SolanaPayParseError, .excessDecimals(expected: 9, got: 10))
        }
    }

    func testScientificNotationRejected() {
        let raw = "solana:\(recipientBase58)?amount=1e6"
        XCTAssertThrowsError(try SolanaPayURIParser.parse(raw)) { error in
            XCTAssertEqual(error as? SolanaPayParseError, .invalidAmount("1e6"))
        }
    }

    func testLeadingDotAmountRejected() {
        let raw = "solana:\(recipientBase58)?amount=.5"
        XCTAssertThrowsError(try SolanaPayURIParser.parse(raw)) { error in
            XCTAssertEqual(error as? SolanaPayParseError, .invalidAmount(".5"))
        }
    }

    func testMissingRecipientRejected() {
        XCTAssertThrowsError(try SolanaPayURIParser.parse("solana:")) { error in
            XCTAssertEqual(error as? SolanaPayParseError, .missingRecipient)
        }
    }

    func testInvalidRecipientRejected() {
        let raw = "solana:not_base58_0OIl"
        XCTAssertThrowsError(try SolanaPayURIParser.parse(raw)) { error in
            guard case .invalidRecipient(let value) = error as? SolanaPayParseError else {
                XCTFail("expected invalidRecipient, got \(error)")
                return
            }
            XCTAssertEqual(value, "not_base58_0OIl")
        }
    }

    func testInvalidSplTokenRejected() {
        let raw = "solana:\(recipientBase58)?spl-token=not_base58_0OIl"
        XCTAssertThrowsError(try SolanaPayURIParser.parse(raw)) { error in
            guard case .invalidSplToken(let value) = error as? SolanaPayParseError else {
                XCTFail("expected invalidSplToken, got \(error)")
                return
            }
            XCTAssertEqual(value, "not_base58_0OIl")
        }
    }

    func testInvalidReferenceRejected() {
        let raw = "solana:\(recipientBase58)?reference=not_base58_0OIl"
        XCTAssertThrowsError(try SolanaPayURIParser.parse(raw)) { error in
            guard case .invalidReference(let value) = error as? SolanaPayParseError else {
                XCTFail("expected invalidReference, got \(error)")
                return
            }
            XCTAssertEqual(value, "not_base58_0OIl")
        }
    }
}
