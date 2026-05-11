import XCTest
@testable import Formatters

final class PercentageDeltaFormatterTests: XCTestCase {
    private let enUS = Locale(identifier: "en_US")
    private let deDE = Locale(identifier: "de_DE")
    private let trTR = Locale(identifier: "tr_TR")

    // MARK: - string(_:)

    func testZeroRendersAsPlainZeroPercent_enUS() {
        let f = PercentageDeltaFormatter(locale: enUS)
        XCTAssertEqual(f.string(0.0), "0.00%")
    }

    func testZeroRendersAsPlainZeroPercent_deDE() {
        // The zero branch is hardcoded by spec; locale must not change it.
        let f = PercentageDeltaFormatter(locale: deDE)
        XCTAssertEqual(f.string(0.0), "0.00%")
    }

    func testPositiveDeltaHasPlusSignAndAsciiPercent_enUS() {
        let f = PercentageDeltaFormatter(locale: enUS)
        XCTAssertEqual(f.string(1.23), "+1.23%")
    }

    func testNegativeDeltaUsesUnicodeMinusGlyph_enUS() {
        let f = PercentageDeltaFormatter(locale: enUS)
        let result = f.string(-4.56)
        XCTAssertEqual(result, "\u{2212}4.56%")
        XCTAssertTrue(result.contains("\u{2212}"))
        XCTAssertFalse(result.contains("-"), "ASCII hyphen must not be used for negative delta")
    }

    func testTwoFractionDigitsAreEnforced_enUS() {
        let f = PercentageDeltaFormatter(locale: enUS)
        XCTAssertEqual(f.string(5.0), "+5.00%")
        XCTAssertEqual(f.string(-0.1), "\u{2212}0.10%")
    }

    func testDecimalSeparatorIsLocalized_deDE() {
        // de_DE uses "," as decimal separator.
        let f = PercentageDeltaFormatter(locale: deDE)
        XCTAssertEqual(f.string(1.23), "+1,23%")
        XCTAssertEqual(f.string(-4.56), "\u{2212}4,56%")
    }

    func testDecimalSeparatorIsLocalized_trTR() {
        // tr_TR also uses ",".
        let f = PercentageDeltaFormatter(locale: trTR)
        XCTAssertEqual(f.string(1.23), "+1,23%")
    }

    // MARK: - share(_:)

    func testShareIsUnsignedTwoDigitsByDefault_enUS() {
        let f = PercentageDeltaFormatter(locale: enUS)
        XCTAssertEqual(f.share(12.34), "12.34%")
        XCTAssertEqual(f.share(0), "0.00%")
        XCTAssertEqual(f.share(99.5), "99.50%")
    }

    func testShareDropsFractionDigitsAboveOneHundred_enUS() {
        let f = PercentageDeltaFormatter(locale: enUS)
        XCTAssertEqual(f.share(150), "150%")
    }

    func testShareHonorsLocaleDecimalSeparator_deDE() {
        let f = PercentageDeltaFormatter(locale: deDE)
        XCTAssertEqual(f.share(12.34), "12,34%")
    }

    // MARK: - color(for:)

    func testColorNeutralForZero() {
        let f = PercentageDeltaFormatter(locale: enUS)
        XCTAssertEqual(f.color(for: 0.0), .neutral)
    }

    func testColorUpForPositive() {
        let f = PercentageDeltaFormatter(locale: enUS)
        XCTAssertEqual(f.color(for: 0.01), .up)
        XCTAssertEqual(f.color(for: 100), .up)
    }

    func testColorDownForNegative() {
        let f = PercentageDeltaFormatter(locale: enUS)
        XCTAssertEqual(f.color(for: -0.01), .down)
        XCTAssertEqual(f.color(for: -42.0), .down)
    }
}
