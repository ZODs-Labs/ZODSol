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

    func testSmallValueOneFractionDigitsBecomeTwo_enUS() throws {
        let f = CurrencyFormatter(locale: enUS)
        XCTAssertEqual(try f.string(usd: XCTUnwrap(Decimal(string: "1.23"))), "$1.23")
    }

    func testThousandsGroupingInsertsComma_enUS() throws {
        let f = CurrencyFormatter(locale: enUS)
        XCTAssertEqual(try f.string(usd: XCTUnwrap(Decimal(string: "1234.56"))), "$1,234.56")
    }

    func testMillionsGroupingInsertsCommas_enUS() throws {
        let f = CurrencyFormatter(locale: enUS)
        XCTAssertEqual(try f.string(usd: XCTUnwrap(Decimal(string: "1234567.89"))), "$1,234,567.89")
    }

    func testNegativeUsesUnicodeMinusGlyph_enUS() throws {
        let f = CurrencyFormatter(locale: enUS)
        let result = try f.string(usd: XCTUnwrap(Decimal(string: "-1.23")))
        // We don't insist on the exact placement of the glyph (NumberFormatter places
        // it before the currency symbol in en_US: "−$1.23"); we just require U+2212
        // somewhere and no ASCII hyphen.
        XCTAssertTrue(result.contains("\u{2212}"), "expected U+2212 minus glyph in \(result)")
        XCTAssertFalse(result.contains("-"), "ASCII hyphen must not appear in \(result)")
        XCTAssertTrue(result.contains("1.23"))
    }

    // MARK: - string(usd:) consistency in non-en locales

    func testDeDEConsistentWithReferenceFormatter() throws {
        let f = CurrencyFormatter(locale: deDE)
        let reference = Self.referenceCurrency(locale: self.deDE)
        let value = try XCTUnwrap(Decimal(string: "1234.56"))
        let expected = reference.string(from: value as NSDecimalNumber)!
        XCTAssertEqual(f.string(usd: value), expected)
    }

    func testTrTRConsistentWithReferenceFormatter() throws {
        let f = CurrencyFormatter(locale: trTR)
        let reference = Self.referenceCurrency(locale: self.trTR)
        let value = try XCTUnwrap(Decimal(string: "1234.56"))
        let expected = reference.string(from: value as NSDecimalNumber)!
        XCTAssertEqual(f.string(usd: value), expected)
    }

    // MARK: - compact(usd:) en_US

    func testCompactUnderTenThousandFallsThroughToFullDigits_enUS() throws {
        let f = CurrencyFormatter(locale: enUS)
        XCTAssertEqual(try f.compact(usd: XCTUnwrap(Decimal(string: "9999"))), "$9,999.00")
    }

    func testCompactTenThousandRendersAsTenPointZeroK_enUS() throws {
        let f = CurrencyFormatter(locale: enUS)
        XCTAssertEqual(try f.compact(usd: XCTUnwrap(Decimal(string: "10000"))), "$10.00K")
    }

    func testCompactThousandsUseKSuffix_enUS() throws {
        let f = CurrencyFormatter(locale: enUS)
        // 12_345 / 1000 = 12.345 → NumberFormatter default rounding (halfEven)
        // takes .345 (5 with preceding 4) to .34. Result: "$12.34K".
        XCTAssertEqual(try f.compact(usd: XCTUnwrap(Decimal(string: "12345"))), "$12.34K")
    }

    func testCompactMillionsUseMSuffix_enUS() throws {
        let f = CurrencyFormatter(locale: enUS)
        XCTAssertEqual(try f.compact(usd: XCTUnwrap(Decimal(string: "1234567"))), "$1.23M")
    }

    func testCompactBillionsUseBSuffix_enUS() throws {
        let f = CurrencyFormatter(locale: enUS)
        XCTAssertEqual(try f.compact(usd: XCTUnwrap(Decimal(string: "1234567890"))), "$1.23B")
    }

    func testCompactNegativeUsesUnicodeMinusGlyph_enUS() throws {
        let f = CurrencyFormatter(locale: enUS)
        let result = try f.compact(usd: XCTUnwrap(Decimal(string: "-12345")))
        XCTAssertTrue(result.contains("\u{2212}"), "expected U+2212 minus in \(result)")
        XCTAssertFalse(result.contains("-"), "ASCII hyphen must not appear in \(result)")
        XCTAssertTrue(result.contains("12.34K"))
    }

    func testCompactNegativeUnderThresholdUsesUnicodeMinus_enUS() throws {
        let f = CurrencyFormatter(locale: enUS)
        let result = try f.compact(usd: XCTUnwrap(Decimal(string: "-1.23")))
        XCTAssertTrue(result.contains("\u{2212}"))
        XCTAssertFalse(result.contains("-"))
        XCTAssertTrue(result.contains("1.23"))
    }

    // MARK: - displayValue(usd:) en_US

    func testDisplayValueSubThousandUsesFullCurrency_enUS() throws {
        let f = CurrencyFormatter(locale: enUS)
        XCTAssertEqual(try f.displayValue(usd: XCTUnwrap(Decimal(string: "0.99"))), "$0.99")
        XCTAssertEqual(try f.displayValue(usd: XCTUnwrap(Decimal(string: "164.50"))), "$164.50")
        XCTAssertEqual(try f.displayValue(usd: XCTUnwrap(Decimal(string: "999.99"))), "$999.99")
    }

    func testDisplayValueAtOneThousandSwitchesToCompactK_enUS() throws {
        let f = CurrencyFormatter(locale: enUS)
        XCTAssertEqual(try f.displayValue(usd: XCTUnwrap(Decimal(string: "1000"))), "$1K")
        XCTAssertEqual(try f.displayValue(usd: XCTUnwrap(Decimal(string: "1234"))), "$1.23K")
    }

    func testDisplayValueMillionsUseMSuffix_enUS() throws {
        let f = CurrencyFormatter(locale: enUS)
        XCTAssertEqual(try f.displayValue(usd: XCTUnwrap(Decimal(string: "1234567"))), "$1.23M")
    }

    func testDisplayValueBillionsUseBSuffix_enUS() throws {
        let f = CurrencyFormatter(locale: enUS)
        XCTAssertEqual(try f.displayValue(usd: XCTUnwrap(Decimal(string: "1234567890"))), "$1.23B")
    }

    func testDisplayValueNegativeUsesUnicodeMinus_enUS() throws {
        let f = CurrencyFormatter(locale: enUS)
        let result = try f.displayValue(usd: XCTUnwrap(Decimal(string: "-2500")))
        XCTAssertTrue(result.contains("\u{2212}"))
        XCTAssertFalse(result.contains("-"))
        XCTAssertTrue(result.contains("K"))
    }

    // MARK: - priceUSD(_:) en_US

    func testPriceUSDZeroRendersAsBareDollarZero_enUS() {
        let f = CurrencyFormatter(locale: enUS)
        XCTAssertEqual(f.priceUSD(Decimal(0)), "$0")
    }

    func testPriceUSDSubCentCollapsesToThreshold_enUS() throws {
        let f = CurrencyFormatter(locale: enUS)
        XCTAssertEqual(try f.priceUSD(XCTUnwrap(Decimal(string: "0.005"))), "<$0.01")
        XCTAssertEqual(try f.priceUSD(XCTUnwrap(Decimal(string: "0.0001"))), "<$0.01")
    }

    func testPriceUSDSubCentNegative_enUS() throws {
        let f = CurrencyFormatter(locale: enUS)
        let result = try f.priceUSD(XCTUnwrap(Decimal(string: "-0.005")))
        XCTAssertEqual(result, "\u{2212}<$0.01")
    }

    func testPriceUSDFractionalUsesUpToFourDigits_enUS() throws {
        let f = CurrencyFormatter(locale: enUS)
        XCTAssertEqual(try f.priceUSD(XCTUnwrap(Decimal(string: "0.0123"))), "$0.0123")
        XCTAssertEqual(try f.priceUSD(XCTUnwrap(Decimal(string: "0.50"))), "$0.50")
    }

    func testPriceUSDAtOrAboveOneUsesTwoDigits_enUS() throws {
        let f = CurrencyFormatter(locale: enUS)
        XCTAssertEqual(try f.priceUSD(XCTUnwrap(Decimal(string: "1"))), "$1.00")
        XCTAssertEqual(try f.priceUSD(XCTUnwrap(Decimal(string: "1234.5"))), "$1,234.50")
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
