import SolanaKit
import XCTest
@testable import DataProviders

/// Enforces the carve-out invariant: the price ticker only ever contacts the
/// keyless public market-data hosts and never carries the Helius API key.
final class TickerKeyIsolationTests: XCTestCase {
    private static let allowedHosts = ["api.kraken.com", "api.exchange.coinbase.com", "lite-api.jup.ag"]

    override func setUp() {
        super.setUp()
        MockURLProtocol.reset()
    }

    override func tearDown() {
        MockURLProtocol.reset()
        super.tearDown()
    }

    func test_tickerProvider_neverContactsKeyBearingHost() async throws {
        let kraken = try FixtureLoader.load("kraken-ticker-success.json")
        let jupiter = try FixtureLoader.load("jupiter-price-success.json")
        MockURLProtocol.requestHandler = { request in
            let host = request.url?.host ?? ""
            let body = host.contains("kraken") ? kraken : jupiter
            let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
            return (response, body)
        }

        let provider = LayeredTickerPriceProvider(
            session: MockURLProtocol.makeSession(),
            krakenToCoinbaseProducts: ["XXBTZUSD": "BTC-USD"])
        _ = await provider.quotes(for: [
            TickerQuoteRequest(source: .kraken, identifier: "XXBTZUSD"),
            TickerQuoteRequest(source: .jupiter, identifier: "EPjFWdd5AufqSSqeM2qN1xzybapC8G4wEGGkZwyTDt1v"),
        ])

        XCTAssertFalse(MockURLProtocol.requestLog.isEmpty, "expected the ticker to make requests")
        for request in MockURLProtocol.requestLog {
            let url = request.url?.absoluteString ?? ""
            XCTAssertFalse(url.contains("api-key"), "ticker request carried an api-key: \(url)")
            XCTAssertFalse(url.lowercased().contains("helius"), "ticker request reached a Helius host: \(url)")
            let host = request.url?.host ?? ""
            XCTAssertTrue(
                Self.allowedHosts.contains(host),
                "ticker request reached an unexpected host: \(host)")
        }
    }
}
