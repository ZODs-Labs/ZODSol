import Formatters
import Foundation
import WalletOverviewDomain
import XCTest
@testable import WalletOverviewUI

final class TickerRenderModelTests: XCTestCase {
    private let price = TickerPriceFormatter(locale: Locale(identifier: "en_US"))
    private let delta = PercentageDeltaFormatter(locale: Locale(identifier: "en_US"))

    private func segment(
        symbol: String = "SOL",
        price: String? = "152.40",
        change: Double? = 1.2,
        staleness: TickerStaleness = .fresh) -> TickerSegment
    {
        TickerSegment(
            id: UUID(),
            symbol: symbol,
            displayName: symbol,
            iconURL: nil,
            price: price.flatMap { Decimal(string: $0) },
            change24h: change,
            staleness: staleness)
    }

    private func build(_ segment: TickerSegment, mode: TickerDisplayMode, enabled: Bool = true) -> TickerRenderModel {
        TickerRenderModel.build(
            snapshot: TickerSnapshot(segments: [segment]),
            displayMode: mode,
            isEnabled: enabled,
            priceFormatter: self.price,
            deltaFormatter: self.delta)
    }

    func testDisabledIsHidden() {
        XCTAssertEqual(self.build(self.segment(), mode: .symbolAndPrice, enabled: false), .hidden)
    }

    func testSymbolAndPriceOmitsChange() {
        guard case let .ticker(segments) = self.build(self.segment(), mode: .symbolAndPrice) else {
            return XCTFail("expected ticker")
        }
        XCTAssertEqual(segments.first?.symbol, "SOL")
        XCTAssertEqual(segments.first?.priceText, "$152.40")
        XCTAssertNil(segments.first?.changeText)
    }

    func testSymbolPriceAndChangeShowsTintedChange() {
        guard case let .ticker(segments) = self.build(self.segment(change: 1.2), mode: .symbolPriceAndChange) else {
            return XCTFail("expected ticker")
        }
        XCTAssertEqual(segments.first?.changeText, "+1.20%")
        XCTAssertEqual(segments.first?.tint, .up)
    }

    func testNegativeChangeIsDownTinted() {
        guard case let .ticker(segments) = self.build(self.segment(change: -3.0), mode: .symbolPriceAndChange) else {
            return XCTFail("expected ticker")
        }
        XCTAssertEqual(segments.first?.tint, .down)
        XCTAssertEqual(segments.first?.changeText, "\u{2212}3.00%")
    }

    func testPriceOnlyDropsSymbol() {
        guard case let .ticker(segments) = self.build(self.segment(), mode: .priceOnly) else {
            return XCTFail("expected ticker")
        }
        XCTAssertNil(segments.first?.symbol)
        XCTAssertEqual(segments.first?.priceText, "$152.40")
    }

    func testStaleSegmentIsDimmedButKeepsPrice() {
        guard case let .ticker(segments) = self.build(self.segment(staleness: .stale), mode: .symbolAndPrice) else {
            return XCTFail("expected ticker")
        }
        XCTAssertTrue(segments.first?.isDimmed == true)
        XCTAssertEqual(segments.first?.priceText, "$152.40")
    }

    func testUnavailableSegmentShowsPlaceholderAndNoChange() {
        let unavailable = self.segment(price: nil, change: 2.0, staleness: .unavailable)
        guard case let .ticker(segments) = self.build(unavailable, mode: .symbolPriceAndChange) else {
            return XCTFail("expected ticker")
        }
        XCTAssertEqual(segments.first?.priceText, TickerPriceFormatter.noData)
        XCTAssertNil(segments.first?.changeText)
    }
}
