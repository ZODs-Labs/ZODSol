import XCTest
@testable import SolanaKit

final class TokenAmountTests: XCTestCase {
    func testInitializerStoresFields() {
        let amount = TokenAmount(amount: 12_345, decimals: 6)
        XCTAssertEqual(amount.amount, 12_345)
        XCTAssertEqual(amount.decimals, 6)
    }

    func testUIAmountForUSDCStyleSixDecimals() {
        // 1.234567 USDC -> 1_234_567 raw atomic units at 6 decimals.
        let amount = TokenAmount(amount: 1_234_567, decimals: 6)
        XCTAssertEqual(amount.uiAmount, Decimal(string: "1.234567"))
    }

    func testUIAmountForNineDecimals() {
        // 0.123456789 with 9 decimals.
        let amount = TokenAmount(amount: 123_456_789, decimals: 9)
        XCTAssertEqual(amount.uiAmount, Decimal(string: "0.123456789"))
    }

    func testUIAmountForZeroDecimals() {
        let amount = TokenAmount(amount: 42, decimals: 0)
        XCTAssertEqual(amount.uiAmount, Decimal(42))
    }

    func testUIAmountForZeroAmount() {
        let amount = TokenAmount(amount: 0, decimals: 6)
        XCTAssertEqual(amount.uiAmount, Decimal(0))
    }

    func testUIAmountUsesDecimalNotDouble() {
        // 1 atomic unit at 9 decimals == 0.000000001 — survives without
        // binary floating point rounding.
        let amount = TokenAmount(amount: 1, decimals: 9)
        XCTAssertEqual(amount.uiAmount, Decimal(string: "0.000000001"))
    }

    func testUIAmountForLargeAmount() {
        // 1 SOL == 1_000_000_000 lamports at 9 decimals == 1 SOL.
        let amount = TokenAmount(amount: 1_000_000_000, decimals: 9)
        XCTAssertEqual(amount.uiAmount, Decimal(1))
    }

    func testHashableAndEquatable() {
        let a = TokenAmount(amount: 100, decimals: 6)
        let b = TokenAmount(amount: 100, decimals: 6)
        let c = TokenAmount(amount: 100, decimals: 9)
        XCTAssertEqual(a, b)
        XCTAssertEqual(a.hashValue, b.hashValue)
        XCTAssertNotEqual(a, c)
    }

    func testCodableRoundTrip() throws {
        let original = TokenAmount(amount: 9_876_543, decimals: 8)
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(TokenAmount.self, from: data)
        XCTAssertEqual(original, decoded)
    }
}
