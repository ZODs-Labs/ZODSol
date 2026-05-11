import XCTest
import SolanaKit
@testable import Formatters

final class TokenAmountFormatterTests: XCTestCase {
    private let enUS = Locale(identifier: "en_US")
    private let deDE = Locale(identifier: "de_DE")
    private let trTR = Locale(identifier: "tr_TR")

    // MARK: - Zero

    func testZeroWithSymbolHasSpaceSeparator_enUS() {
        let f = TokenAmountFormatter(locale: enUS)
        let amount = TokenAmount(amount: 0, decimals: 9)
        XCTAssertEqual(f.string(amount, symbol: "SOL"), "0 SOL")
    }

    func testZeroWithoutSymbolHasNoTrailingSpace_enUS() {
        let f = TokenAmountFormatter(locale: enUS)
        let amount = TokenAmount(amount: 0, decimals: 9)
        XCTAssertEqual(f.string(amount, symbol: nil), "0")
    }

    // MARK: - >= 1 branch (≤ 2 fraction digits, grouped — trailing zeros stripped)

    func testOneWholeUnitMatchesSpecExample_enUS() {
        let f = TokenAmountFormatter(locale: enUS)
        let amount = TokenAmount(amount: 1_000_000_000, decimals: 9)
        // Per spec example: TokenAmount(1_000_000_000, 9) -> "1 SOL".
        // Implementation uses min=0/max=2 fraction digits, so 1.0 renders as "1".
        XCTAssertEqual(f.string(amount, symbol: "SOL"), "1 SOL")
    }

    func testLargeAmountUsesGroupingAndTwoFractionDigits_enUS() {
        let f = TokenAmountFormatter(locale: enUS)
        // 1_234_567_890 / 10^6 = 1234.56789 → rounds to 2 frac digits.
        let amount = TokenAmount(amount: 1_234_567_890, decimals: 6)
        let reference = NumberFormatter()
        reference.numberStyle = .decimal
        reference.locale = enUS
        reference.minimumFractionDigits = 0
        reference.maximumFractionDigits = 2
        reference.usesGroupingSeparator = true
        let body = reference.string(from: NSDecimalNumber(decimal: amount.uiAmount))!
        XCTAssertEqual(f.string(amount, symbol: "USDC"), "\(body) USDC")
        XCTAssertTrue(body.contains(","), "expected grouping separator in \(body)")
    }

    // MARK: - [0.001, 1) branch (4 significant digits)

    func testSubOneAboveMillionthUsesFourSignificantDigits_enUS() {
        let f = TokenAmountFormatter(locale: enUS)
        // 1234 / 10^6 = 0.001234 → 4 sig digits → "0.001234"
        let amount = TokenAmount(amount: 1234, decimals: 6)
        XCTAssertEqual(f.string(amount, symbol: "USDC"), "0.001234 USDC")
    }

    // MARK: - Subscript-zero branch

    func testTinyValueUsesSubscriptZeroNotation_oneOverBillion_enUS() {
        let f = TokenAmountFormatter(locale: enUS)
        // 1 / 10^9 = 0.000000001 → 8 leading zeros after the decimal → "0.0₈1 SOL"
        let amount = TokenAmount(amount: 1, decimals: 9)
        XCTAssertEqual(f.string(amount, symbol: "SOL"), "0.0\u{2088}1 SOL")
    }

    func testTinyValueSubscriptCount_twelveDecimals_enUS() {
        let f = TokenAmountFormatter(locale: enUS)
        // 1234 / 10^12 = 0.000000001234 → 8 leading zeros, 4 sig digits → "0.0₈1234 SYM"
        let amount = TokenAmount(amount: 1234, decimals: 12)
        XCTAssertEqual(f.string(amount, symbol: "SYM"), "0.0\u{2088}1234 SYM")
    }

    func testTinyValueSubscriptCount_nineDecimalsFourZeros_enUS() {
        let f = TokenAmountFormatter(locale: enUS)
        // 12345 / 10^9 = 0.000012345 → 4 leading zeros, 4 sig digits → "0.0₄1234 SYM"
        let amount = TokenAmount(amount: 12345, decimals: 9)
        let result = f.string(amount, symbol: "SYM")
        XCTAssertEqual(result, "0.0\u{2084}1234 SYM")
        // Sanity: there is exactly one subscript-digit character (₄).
        let subscriptChars = result.unicodeScalars.filter { (0x2080 ... 0x2089).contains($0.value) }
        XCTAssertEqual(subscriptChars.count, 1)
        XCTAssertEqual(subscriptChars.first?.value, 0x2084)
    }

    // MARK: - Symbol handling

    func testNilSymbolOmitsTrailingSpace_aboveOne_enUS() {
        let f = TokenAmountFormatter(locale: enUS)
        let amount = TokenAmount(amount: 1_000_000_000, decimals: 9)
        XCTAssertEqual(f.string(amount, symbol: nil), "1")
    }

    func testEmptySymbolTreatedAsNone_enUS() {
        let f = TokenAmountFormatter(locale: enUS)
        let amount = TokenAmount(amount: 1_000_000_000, decimals: 9)
        // Implementation collapses empty string to no suffix (no trailing space).
        XCTAssertEqual(f.string(amount, symbol: ""), "1")
    }

    // MARK: - Locale awareness

    func testDeDEUsesCommaDecimalSeparator_aboveOne() {
        let f = TokenAmountFormatter(locale: deDE)
        let amount = TokenAmount(amount: 1_234_567_890, decimals: 6)
        // Verify via reference NumberFormatter to avoid baking in fragile separators.
        let reference = NumberFormatter()
        reference.numberStyle = .decimal
        reference.locale = deDE
        reference.minimumFractionDigits = 0
        reference.maximumFractionDigits = 2
        reference.usesGroupingSeparator = true
        let expectedBody = reference.string(from: NSDecimalNumber(decimal: amount.uiAmount))!
        XCTAssertEqual(f.string(amount, symbol: "USDC"), "\(expectedBody) USDC")
    }

    func testDeDESubscriptZeroUsesLocaleDecimalSeparator() {
        let f = TokenAmountFormatter(locale: deDE)
        let amount = TokenAmount(amount: 1, decimals: 9)
        // de_DE decimal separator is ",". Result should be "0,0₈1 SOL".
        XCTAssertEqual(f.string(amount, symbol: "SOL"), "0,0\u{2088}1 SOL")
    }

    func testTrTRSubOneBranchConsistentWithReference() {
        let f = TokenAmountFormatter(locale: trTR)
        // 1234 / 10^6 = 0.001234 — 4 sig digits via reference formatter.
        let amount = TokenAmount(amount: 1234, decimals: 6)
        let reference = NumberFormatter()
        reference.numberStyle = .decimal
        reference.locale = trTR
        reference.usesSignificantDigits = true
        reference.minimumSignificantDigits = 1
        reference.maximumSignificantDigits = 4
        let expectedBody = reference.string(from: NSDecimalNumber(decimal: amount.uiAmount))!
        XCTAssertEqual(f.string(amount, symbol: "USDC"), "\(expectedBody) USDC")
    }
}
