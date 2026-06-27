import SolanaKit
import XCTest
@testable import HeliusProvider

final class LayeredTickerPriceProviderTests: XCTestCase {
    private let usdcMint = "EPjFWdd5AufqSSqeM2qN1xzybapC8G4wEGGkZwyTDt1v"

    override func setUp() {
        super.setUp()
        MockURLProtocol.reset()
    }

    override func tearDown() {
        MockURLProtocol.reset()
        super.tearDown()
    }

    private func makeProvider() -> LayeredTickerPriceProvider {
        LayeredTickerPriceProvider(
            session: MockURLProtocol.makeSession(),
            krakenToCoinbaseProducts: ["XXBTZUSD": "BTC-USD"])
    }

    func test_routesBlueChipToKrakenAndMintToJupiter() async throws {
        let kraken = try FixtureLoader.load("kraken-ticker-success.json")
        let jupiter = try FixtureLoader.load("jupiter-price-success.json")
        MockURLProtocol.requestHandler = { request in
            let host = request.url?.host ?? ""
            let body = host.contains("kraken") ? kraken : jupiter
            return (Self.ok(request.url!), body)
        }

        let outcome = await self.makeProvider().quotes(for: [
            TickerQuoteRequest(source: .kraken, identifier: "XXBTZUSD"),
            TickerQuoteRequest(source: .jupiter, identifier: self.usdcMint),
        ])

        XCTAssertFalse(outcome.shouldBackOff)
        XCTAssertEqual(outcome.quotes["XXBTZUSD"]?.usdPrice, Decimal(string: "64210.5"))
        XCTAssertEqual(outcome.quotes[self.usdcMint]?.usdPrice, Decimal(string: "1.0001"))
    }

    func test_krakenRateLimit_fallsBackToCoinbase_keepsBackoff() async throws {
        let coinbase = try FixtureLoader.load("coinbase-stats-btc.json")
        MockURLProtocol.requestHandler = { request in
            let host = request.url?.host ?? ""
            if host.contains("kraken") {
                return (Self.status(429, request.url!), Data())
            }
            return (Self.ok(request.url!), coinbase)
        }

        let outcome = await self.makeProvider().quotes(for: [
            TickerQuoteRequest(source: .kraken, identifier: "XXBTZUSD"),
        ])

        // Coinbase supplied the price, but Kraken rate-limited so we still back off.
        XCTAssertEqual(outcome.quotes["XXBTZUSD"]?.usdPrice, Decimal(string: "64210.5"))
        XCTAssertTrue(outcome.shouldBackOff)
    }

    func test_jupiterFailure_setsBackoff() async {
        MockURLProtocol.requestHandler = { request in (Self.status(500, request.url!), Data()) }

        let outcome = await self.makeProvider().quotes(for: [
            TickerQuoteRequest(source: .jupiter, identifier: self.usdcMint),
        ])

        XCTAssertTrue(outcome.shouldBackOff)
        XCTAssertTrue(outcome.quotes.isEmpty)
    }

    private static func ok(_ url: URL) -> HTTPURLResponse {
        self.status(200, url)
    }

    private static func status(_ code: Int, _ url: URL) -> HTTPURLResponse {
        HTTPURLResponse(url: url, statusCode: code, httpVersion: nil, headerFields: nil)!
    }
}
