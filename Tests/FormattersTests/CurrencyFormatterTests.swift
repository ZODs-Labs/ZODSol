import XCTest
@testable import Formatters

final class CurrencyFormatterTests: XCTestCase {
    private let enUS = Locale(identifier: "en_US")
    private let deDE = Locale(identifier: "de_DE")
    private let trTR = Locale(identifier: "tr_TR")

    // MARK: - string(usd:) en_US

    func testZeroRendersAsDollarZeroPointZeroZero_enUS() {
        let f = CurrencyFormatter(locale: enUS)
        XCTAssertEqual(f.string(usd: Decimal(0)), "$0.00")
    }

    func testSmallValueOneFractionDigitsBecomeTwo_enUS() {
        let f = CurrencyFormatter(locale: enUS)
        XCTAssertEqual(f.string(usd: Decimal(string: "1.23")!), "$1.23")
    }

    func testThousandsGroupingInsertsComma_enUS() {
        let f = CurrencyFormatter(locale: enUS)
        XCTAssertEqual(f.string(usd: Decimal(string: "1234.56")!), "$1,234.56")
    }

    func testMillionsGroupingInsertsCommas_enUS() {
        let f = CurrencyFormatter(locale: enUS)
        XCTAssertEqual(f.string(usd: Decimal(string: "1234567.89")!), "$1,234,567.89")
    }

    func testNegativeUsesUnicodeMinusGlyph_enUS() {
        let f = CurrencyFormatter(locale: enUS)
        let result = f.string(usd: Decimal(string: "-1.23")!)
        // We don't insist on the exact placement of the glyph (NumberFormatter places
        // it before the currency symbol in en_US: "−$1.23"); we just require U+2212
        // somewhere and no ASCII hyphen.
        XCTAssertTrue(result.contains("\u{2212}"), "expected U+2212 minus glyph in \(result)")
        XCTAssertFalse(result.contains("-"), "ASCII hyphen must not appear in \(result)")
        XCTAssertTrue(result.contains("1.23"))
    }

    // MARK: - string(usd:) consistency in non-en locales

    func testDeDEConsistentWithReferenceFormatter() {
        let f = CurrencyFormatter(locale: deDE)
        let reference = Self.referenceCurrency(locale: deDE)
        let value = Decimal(string: "1234.56")!
        let expected = reference.string(from: value as NSDecimalNumber)!
        XCTAssertEqual(f.string(usd: value), expected)
    }

    func testTrTRConsistentWithReferenceFormatter() {
        let f = CurrencyFormatter(locale: trTR)
        let reference = Self.referenceCurrency(locale: trTR)
        let value = Decimal(string: "1234.56")!
        let expected = reference.string(from: value as NSDecimalNumber)!
        XCTAssertEqual(f.string(usd: value), expected)
    }

    // MARK: - compact(usd:) en_US

    func testCompactUnderTenThousandFallsThroughToFullDigits_enUS() {
        let f = CurrencyFormatter(locale: enUS)
        XCTAssertEqual(f.compact(usd: Decimal(string: "9999")!), "$9,999.00")
    }

    func testCompactTenThousandRendersAsTenPointZeroK_enUS() {
        let f = CurrencyFormatter(locale: enUS)
        XCTAssertEqual(f.compact(usd: Decimal(string: "10000")!), "$10.00K")
    }

    func testCompactThousandsUseKSuffix_enUS() {
        let f = CurrencyFormatter(locale: enUS)
        // 12_345 / 1000 = 12.345 → NumberFormatter default rounding (halfEven)
        // takes .345 (5 with preceding 4) to .34. Result: "$12.34K".
        XCTAssertEqual(f.compact(usd: Decimal(string: "12345")!), "$12.34K")
    }

    func testCompactMillionsUseMSuffix_enUS() {
        let f = CurrencyFormatter(locale: enUS)
        XCTAssertEqual(f.compact(usd: Decimal(string: "1234567")!), "$1.23M")
    }

    func testCompactBillionsUseBSuffix_enUS() {
        let f = CurrencyFormatter(locale: enUS)
        XCTAssertEqual(f.compact(usd: Decimal(string: "1234567890")!), "$1.23B")
    }

    func testCompactNegativeUsesUnicodeMinusGlyph_enUS() {
        let f = CurrencyFormatter(locale: enUS)
        let result = f.compact(usd: Decimal(string: "-12345")!)
        XCTAssertTrue(result.contains("\u{2212}"), "expected U+2212 minus in \(result)")
        XCTAssertFalse(result.contains("-"), "ASCII hyphen must not appear in \(result)")
        XCTAssertTrue(result.contains("12.34K"))
    }

    func testCompactNegativeUnderThresholdUsesUnicodeMinus_enUS() {
        let f = CurrencyFormatter(locale: enUS)
        let result = f.compact(usd: Decimal(string: "-1.23")!)
        XCTAssertTrue(result.contains("\u{2212}"))
        XCTAssertFalse(result.contains("-"))
        XCTAssertTrue(result.contains("1.23"))
    }

    // MARK: - Helpers

    private static func referenceCurrency(locale: Locale) -> NumberFormatter {
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.currencyCode = "USD"
        formatter.locale = locale
        formatter.minimumFractionDigits = 2
        formatter.maximumFractionDigits = 2
        formatter.usesGroupingSeparator = true
        return formatter
    }
}
