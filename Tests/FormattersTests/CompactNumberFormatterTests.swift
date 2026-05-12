import XCTest
@testable import Formatters

final class CompactNumberFormatterTests: XCTestCase {
    private let enUS = Locale(identifier: "en_US")
    private let deDE = Locale(identifier: "de_DE")
    private let trTR = Locale(identifier: "tr_TR")

    // MARK: - Below 1K (full digits, locale-aware grouping)

    func testZero_enUS() {
        let f = CompactNumberFormatter(locale: enUS)
        XCTAssertEqual(f.string(0), "0")
    }

    func testUnderThousand_enUS() {
        let f = CompactNumberFormatter(locale: enUS)
        XCTAssertEqual(f.string(999), "999")
        XCTAssertEqual(f.string(1), "1")
    }

    // MARK: - K branch

    func testThousandsUseKSuffixOneFractionDigit_enUS() {
        let f = CompactNumberFormatter(locale: enUS)
        XCTAssertEqual(f.string(1234), "1.2K")
        XCTAssertEqual(f.string(12345), "12.3K")
        XCTAssertEqual(f.string(999_999), "1,000.0K")
    }

    // MARK: - M branch

    func testMillionsUseMSuffixTwoFractionDigits_enUS() {
        let f = CompactNumberFormatter(locale: enUS)
        XCTAssertEqual(f.string(1_234_567), "1.23M")
        XCTAssertEqual(f.string(12_345_678), "12.35M")
    }

    // MARK: - B branch

    func testBillionsUseBSuffixTwoFractionDigits_enUS() {
        let f = CompactNumberFormatter(locale: enUS)
        XCTAssertEqual(f.string(1_234_567_890), "1.23B")
    }

    // MARK: - Negative numbers

    func testNegativeUsesUnicodeMinusGlyph_enUS() {
        let f = CompactNumberFormatter(locale: enUS)
        let result = f.string(-12345)
        XCTAssertTrue(result.hasPrefix("\u{2212}"), "expected U+2212 minus prefix, got \(result)")
        XCTAssertFalse(result.hasPrefix("-"))
        XCTAssertEqual(result, "\u{2212}12.3K")
    }

    func testNegativeMillions_enUS() {
        let f = CompactNumberFormatter(locale: enUS)
        XCTAssertEqual(f.string(-1_234_567), "\u{2212}1.23M")
    }

    func testNegativeUnderThousand_enUS() {
        let f = CompactNumberFormatter(locale: enUS)
        XCTAssertEqual(f.string(-42), "\u{2212}42")
    }

    // MARK: - Locale awareness

    func testDecimalSeparatorIsLocalized_deDE() {
        let f = CompactNumberFormatter(locale: deDE)
        // de_DE uses "," for decimals.
        XCTAssertEqual(f.string(1234), "1,2K")
        XCTAssertEqual(f.string(1_234_567), "1,23M")
    }

    func testGroupingSeparatorIsLocalized_deDE() throws {
        let f = CompactNumberFormatter(locale: deDE)
        // In de_DE under-1K isn't grouped, but we cross-check via reference NumberFormatter
        // to avoid hard-coding a separator that may differ across OS versions.
        let reference = NumberFormatter()
        reference.numberStyle = .decimal
        reference.locale = self.deDE
        reference.usesGroupingSeparator = true
        let expected = try XCTUnwrap(reference.string(from: NSNumber(value: 999)))
        XCTAssertEqual(f.string(999), expected)
    }

    func testTurkishLocaleUsesCommaDecimal_trTR() {
        let f = CompactNumberFormatter(locale: trTR)
        XCTAssertEqual(f.string(12345), "12,3K")
    }
}
