import SolanaKit
import XCTest
@testable import WalletOverviewDomain

final class TickerCatalogTests: XCTestCase {
    func testCuratedDefaultsAreSolBtcEthFromKraken() {
        let defaults = TickerCatalog.curatedDefaults
        XCTAssertEqual(defaults.map(\.symbol), ["SOL", "BTC", "ETH"])
        XCTAssertTrue(defaults.allSatisfy { $0.source == .kraken })
        XCTAssertTrue(defaults.allSatisfy { $0.displayDecimals == 2 })
    }

    func testBlueChipEntryIsCaseInsensitive() {
        let entry = TickerCatalog.blueChipEntry(symbol: "btc")
        XCTAssertEqual(entry?.symbol, "BTC")
        XCTAssertEqual(entry?.source, .kraken)
        XCTAssertEqual(entry?.sourceIdentifier, "XXBTZUSD")
    }

    func testBlueChipEntryUsesKrakenLegacyCodes() {
        XCTAssertEqual(TickerCatalog.blueChipEntry(symbol: "BTC")?.sourceIdentifier, "XXBTZUSD")
        XCTAssertEqual(TickerCatalog.blueChipEntry(symbol: "DOGE")?.sourceIdentifier, "XDGUSD")
        XCTAssertEqual(TickerCatalog.blueChipEntry(symbol: "SOL")?.sourceIdentifier, "SOLUSD")
    }

    func testBlueChipEntryUnknownSymbolReturnsNil() {
        XCTAssertNil(TickerCatalog.blueChipEntry(symbol: "WIF"))
    }

    func testJupiterEntryFreezesMintAsIdentifier() {
        let mint = "EPjFWdd5AufqSSqeM2qN1xzybapC8G4wEGGkZwyTDt1v"
        let entry = TickerCatalog.jupiterEntry(
            mint: mint, symbol: "USDC", displayName: "USD Coin", displayDecimals: 6)
        XCTAssertEqual(entry.source, .jupiter)
        XCTAssertEqual(entry.sourceIdentifier, mint)
        XCTAssertEqual(entry.symbol, "USDC")
    }

    func testCoinbaseFallbackMapping() {
        XCTAssertEqual(TickerCatalog.coinbaseProduct(forKrakenPair: "XXBTZUSD"), "BTC-USD")
        XCTAssertEqual(TickerCatalog.coinbaseProduct(forKrakenPair: "XDGUSD"), "DOGE-USD")
        XCTAssertNil(TickerCatalog.coinbaseProduct(forKrakenPair: "NOPEUSD"))
        XCTAssertEqual(TickerCatalog.krakenToCoinbaseProducts.count, TickerCatalog.blueChips.count)
    }
}
