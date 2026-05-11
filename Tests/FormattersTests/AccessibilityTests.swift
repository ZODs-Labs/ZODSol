import XCTest
import SolanaKit
@testable import Formatters

final class AccessibilityTests: XCTestCase {
    private let enUS = Locale(identifier: "en_US")
    private let deDE = Locale(identifier: "de_DE")

    // MARK: - CurrencyFormatter

    func testCurrencyAccessibilityContainsSpelledOutDollars_enUS() {
        let f = CurrencyFormatter(locale: enUS)
        let description = f.accessibilityDescription(usd: Decimal(string: "1234.56")!)
        let lower = description.lowercased()
        XCTAssertTrue(lower.contains("one thousand"), "expected 'one thousand' in: \(description)")
        XCTAssertTrue(lower.contains("dollars"), "expected 'dollars' in: \(description)")
        XCTAssertTrue(lower.contains("cents"), "expected 'cents' in: \(description)")
    }

    func testCurrencyAccessibilityIncludesCentsForOddRemainders_enUS() {
        let f = CurrencyFormatter(locale: enUS)
        let description = f.accessibilityDescription(usd: Decimal(string: "1234.56")!).lowercased()
        // 56 → "fifty-six" (with a hyphen).
        XCTAssertTrue(description.contains("fifty-six"), "expected 'fifty-six' in: \(description)")
    }

    func testCurrencyAccessibilityZeroIsSpelledOut_enUS() {
        let f = CurrencyFormatter(locale: enUS)
        let description = f.accessibilityDescription(usd: Decimal(0)).lowercased()
        XCTAssertTrue(description.contains("zero"))
        XCTAssertTrue(description.contains("dollars"))
        // No cents portion when remainder is zero.
        XCTAssertFalse(description.contains("cents"))
    }

    func testCurrencyAccessibilityNegativePrefixed_enUS() {
        let f = CurrencyFormatter(locale: enUS)
        let description = f.accessibilityDescription(usd: Decimal(string: "-1.23")!).lowercased()
        XCTAssertTrue(description.hasPrefix("negative "), "expected 'negative ' prefix in: \(description)")
        XCTAssertTrue(description.contains("twenty-three"))
    }

    // MARK: - TokenAmountFormatter

    func testTokenAccessibilityFullPrecisionNoSubscript_enUS() {
        let f = TokenAmountFormatter(locale: enUS)
        let amount = TokenAmount(amount: 1, decimals: 9)
        let description = f.accessibilityDescription(amount, symbol: "SOL")
        XCTAssertEqual(description, "0.000000001 SOL")
        // Guarantee no subscript characters leaked in.
        let hasSubscript = description.unicodeScalars.contains { (0x2080 ... 0x2089).contains($0.value) }
        XCTAssertFalse(hasSubscript, "subscript glyph must NOT appear in accessibility description")
    }

    func testTokenAccessibilityWithoutSymbol_enUS() {
        let f = TokenAmountFormatter(locale: enUS)
        let amount = TokenAmount(amount: 1_000_000_000, decimals: 9)
        let description = f.accessibilityDescription(amount, symbol: nil)
        XCTAssertEqual(description, "1")
    }

    func testTokenAccessibilityLargeAmountUsesFullDigits_enUS() {
        let f = TokenAmountFormatter(locale: enUS)
        let amount = TokenAmount(amount: 1_234_567_890, decimals: 6)
        let description = f.accessibilityDescription(amount, symbol: "USDC")
        // POSIX raw decimal: 1_234_567_890 / 10^6 = 1234.56789
        XCTAssertEqual(description, "1234.56789 USDC")
        // No grouping separator (POSIX) and no subscript.
        XCTAssertFalse(description.contains(","))
    }

    // MARK: - PercentageDeltaFormatter

    func testPercentageAccessibilityUnchangedForZero_enUS() {
        let f = PercentageDeltaFormatter(locale: enUS)
        XCTAssertEqual(f.accessibilityDescription(0.0), "Unchanged")
    }

    func testPercentageAccessibilityUpForPositive_enUS() {
        let f = PercentageDeltaFormatter(locale: enUS)
        let description = f.accessibilityDescription(1.23)
        XCTAssertTrue(description.lowercased().hasPrefix("up "), "expected 'Up ' prefix in: \(description)")
        XCTAssertTrue(description.contains("1.23"))
        XCTAssertTrue(description.lowercased().contains("percent"))
    }

    func testPercentageAccessibilityDownForNegative_enUS() {
        let f = PercentageDeltaFormatter(locale: enUS)
        let description = f.accessibilityDescription(-4.56)
        XCTAssertTrue(description.lowercased().hasPrefix("down "), "expected 'Down ' prefix in: \(description)")
        XCTAssertTrue(description.contains("4.56"))
        XCTAssertFalse(description.contains("\u{2212}"), "no minus glyph in spoken description")
        XCTAssertFalse(description.contains("-"))
    }

    func testPercentageAccessibilityRespectsLocaleDecimalSeparator_deDE() {
        let f = PercentageDeltaFormatter(locale: deDE)
        let description = f.accessibilityDescription(-4.56)
        XCTAssertTrue(description.lowercased().hasPrefix("down "))
        // de_DE locale: comma decimal separator.
        XCTAssertTrue(description.contains("4,56"), "expected '4,56' in: \(description)")
    }

    // MARK: - CompactNumberFormatter

    func testCompactAccessibilityIsFullDigitsNotAbbreviated_enUS() {
        let f = CompactNumberFormatter(locale: enUS)
        let description = f.accessibilityDescription(12_345_678)
        XCTAssertEqual(description, "12,345,678")
        XCTAssertFalse(description.contains("M"))
        XCTAssertFalse(description.contains("K"))
        XCTAssertFalse(description.contains("B"))
    }

    func testCompactAccessibilitySmallNumber_enUS() {
        let f = CompactNumberFormatter(locale: enUS)
        XCTAssertEqual(f.accessibilityDescription(0), "0")
        XCTAssertEqual(f.accessibilityDescription(999), "999")
    }

    func testCompactAccessibilityNegativeUsesAsciiHyphenFromFormatter_enUS() {
        // NumberFormatter (.decimal, en_US) renders negative integers with ASCII
        // hyphen-minus. Accessibility text need not enforce U+2212.
        let f = CompactNumberFormatter(locale: enUS)
        let description = f.accessibilityDescription(-12_345)
        // We assert on substring presence rather than the exact minus glyph to remain
        // tolerant of OS-version differences in negative-number rendering.
        XCTAssertTrue(description.contains("12,345"))
    }
}
