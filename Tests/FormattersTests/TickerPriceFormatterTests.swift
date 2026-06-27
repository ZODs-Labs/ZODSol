import XCTest
@testable import Formatters

final class TickerPriceFormatterTests: XCTestCase {
    private let enUS = Locale(identifier: "en_US")

    private func make() -> TickerPriceFormatter {
        TickerPriceFormatter(locale: self.enUS)
    }

    // MARK: - No data

    func testNilRendersAsNoDataGlyph() {
        XCTAssertEqual(self.make().string(nil), "\u{2014}")
    }

    func testZeroRendersAsNoDataGlyph() {
        XCTAssertEqual(self.make().string(Decimal(0)), "\u{2014}")
    }

    func testNegativeRendersAsNoDataGlyph() throws {
        XCTAssertEqual(try self.make().string(XCTUnwrap(Decimal(string: "-5"))), "\u{2014}")
    }

    // MARK: - At or above $500: no decimals

    func testLargeCapDropsDecimalsWithGrouping() throws {
        XCTAssertEqual(try self.make().string(XCTUnwrap(Decimal(string: "68000"))), "$68,000")
    }

    func testAboveFiveHundredRoundsToWholeDollars() throws {
        XCTAssertEqual(try self.make().string(XCTUnwrap(Decimal(string: "60325.00"))), "$60,325")
        XCTAssertEqual(try self.make().string(XCTUnwrap(Decimal(string: "1583.98"))), "$1,584")
    }

    func testExactlyFiveHundredDropsDecimals() throws {
        XCTAssertEqual(try self.make().string(XCTUnwrap(Decimal(string: "500"))), "$500")
    }

    // MARK: - One dollar to $500: two decimals

    func testJustBelowFiveHundredKeepsTwoDecimals() throws {
        XCTAssertEqual(try self.make().string(XCTUnwrap(Decimal(string: "499.99"))), "$499.99")
    }

    func testMidPriceUsesTwoDecimals() throws {
        XCTAssertEqual(try self.make().string(XCTUnwrap(Decimal(string: "152.40"))), "$152.40")
    }

    func testExactlyOneUsesTwoDecimals() throws {
        XCTAssertEqual(try self.make().string(XCTUnwrap(Decimal(string: "1"))), "$1.00")
    }

    // MARK: - One cent to one dollar

    func testSubDollarUsesFourFractionDigits() throws {
        XCTAssertEqual(try self.make().string(XCTUnwrap(Decimal(string: "0.4213"))), "$0.4213")
    }

    func testSubDollarPadsToFourFractionDigits() throws {
        XCTAssertEqual(try self.make().string(XCTUnwrap(Decimal(string: "0.5"))), "$0.5000")
    }

    func testJustAboveOneCentUsesFourFractionDigits() throws {
        XCTAssertEqual(try self.make().string(XCTUnwrap(Decimal(string: "0.0123"))), "$0.0123")
    }

    // MARK: - Sub-cent, the case CurrencyFormatter collapses to <$0.01

    func testSubCentDoesNotCollapse() throws {
        // CurrencyFormatter.priceUSD would render both of these as "<$0.01".
        let formatter = self.make()
        XCTAssertEqual(try formatter.string(XCTUnwrap(Decimal(string: "0.001234"))), "$0.0\u{2082}1234")
        XCTAssertEqual(try formatter.string(XCTUnwrap(Decimal(string: "0.005"))), "$0.0\u{2082}5000")
    }

    func testDeepSubCentUsesSubscriptZero() throws {
        XCTAssertEqual(
            try self.make().string(XCTUnwrap(Decimal(string: "0.000001234"))),
            "$0.0\u{2085}1234")
    }

    func testTwoDistinctMemecoinPricesRenderDistinctly() throws {
        let formatter = self.make()
        let first = try formatter.string(XCTUnwrap(Decimal(string: "0.00000123")))
        let second = try formatter.string(XCTUnwrap(Decimal(string: "0.00000456")))
        XCTAssertNotEqual(first, second)
        XCTAssertEqual(first, "$0.0\u{2085}1230")
        XCTAssertEqual(second, "$0.0\u{2085}4560")
    }

    func testSubCentRoundingCarryFallsBackToFixed() throws {
        // 0.00999996 rounds up to 0.0100; the subscript path would emit a wrong
        // zero count, so the fixed renderer takes over.
        XCTAssertEqual(try self.make().string(XCTUnwrap(Decimal(string: "0.00999996"))), "$0.0100")
    }

    // MARK: - Precision (no Double round-trip)

    func testManyDigitPriceKeepsExactSignificand() throws {
        // 0.000000010101 has a significand that binary Double cannot represent
        // exactly; the Decimal path must still surface 1010 as the first four
        // significant digits (five leading zeros).
        XCTAssertEqual(
            try self.make().string(XCTUnwrap(Decimal(string: "0.0000000101010101"))),
            "$0.0\u{2087}1010")
    }
}
