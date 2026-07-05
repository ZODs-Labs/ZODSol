import SolanaKit
import XCTest
@testable import DataProviders

final class BlueChipPriceClientTests: XCTestCase {
    override func setUp() {
        super.setUp()
        MockURLProtocol.reset()
    }

    override func tearDown() {
        MockURLProtocol.reset()
        super.tearDown()
    }

    private func makeClient() -> BlueChipPriceClient {
        BlueChipPriceClient(session: MockURLProtocol.makeSession())
    }

    // MARK: - Kraken

    func test_kraken_emptyPairs_returnsEmpty_noNetworkCall() async {
        MockURLProtocol.requestHandler = { _ in
            XCTFail("No network call should be made for empty pairs")
            throw URLError(.unknown)
        }
        let outcome = await self.makeClient().fetchKraken(pairs: [])
        XCTAssertTrue(outcome.quotes.isEmpty)
        XCTAssertFalse(outcome.shouldBackOff)
        XCTAssertTrue(MockURLProtocol.requestLog.isEmpty)
    }

    func test_kraken_success_batchedSingleCall() async throws {
        let fixture = try FixtureLoader.load("kraken-ticker-success.json")
        MockURLProtocol.requestHandler = { _ in (Self.ok(KrakenEndpoint.ticker), fixture) }

        let outcome = await self.makeClient()
            .fetchKraken(pairs: ["XXBTZUSD", "XETHZUSD", "SOLUSD"])

        XCTAssertEqual(outcome.quotes.count, 3)
        XCTAssertFalse(outcome.shouldBackOff)
        XCTAssertEqual(MockURLProtocol.requestLog.count, 1)

        XCTAssertEqual(outcome.quotes["XXBTZUSD"]?.usdPrice, Decimal(string: "64210.5"))
        XCTAssertEqual(try XCTUnwrap(outcome.quotes["XXBTZUSD"]?.change24h), 1.7599, accuracy: 0.001)
        XCTAssertEqual(outcome.quotes["XETHZUSD"]?.usdPrice, Decimal(string: "3420.12"))
        XCTAssertEqual(try XCTUnwrap(outcome.quotes["XETHZUSD"]?.change24h), -2.2823, accuracy: 0.001)
        XCTAssertEqual(outcome.quotes["SOLUSD"]?.usdPrice, Decimal(string: "152.4"))
        XCTAssertEqual(try XCTUnwrap(outcome.quotes["SOLUSD"]?.change24h), 2.9730, accuracy: 0.001)
    }

    func test_kraken_missingPair_isOmitted() async throws {
        let fixture = try FixtureLoader.load("kraken-ticker-success.json")
        MockURLProtocol.requestHandler = { _ in (Self.ok(KrakenEndpoint.ticker), fixture) }

        let outcome = await self.makeClient().fetchKraken(pairs: ["XXBTZUSD", "XDGUSD"])

        XCTAssertEqual(outcome.quotes.count, 1)
        XCTAssertNotNil(outcome.quotes["XXBTZUSD"])
        XCTAssertNil(outcome.quotes["XDGUSD"])
        XCTAssertFalse(outcome.shouldBackOff)
    }

    func test_kraken_unknownPairError_doesNotBackOff() async throws {
        let fixture = try FixtureLoader.load("kraken-error.json")
        MockURLProtocol.requestHandler = { _ in (Self.ok(KrakenEndpoint.ticker), fixture) }

        let outcome = await self.makeClient().fetchKraken(pairs: ["XXBTZUSD"])
        XCTAssertTrue(outcome.quotes.isEmpty)
        XCTAssertFalse(outcome.shouldBackOff)
    }

    func test_kraken_rateLimitError_backsOff() async throws {
        let fixture = try FixtureLoader.load("kraken-ratelimit.json")
        MockURLProtocol.requestHandler = { _ in (Self.ok(KrakenEndpoint.ticker), fixture) }

        let outcome = await self.makeClient().fetchKraken(pairs: ["XXBTZUSD"])
        XCTAssertTrue(outcome.quotes.isEmpty)
        XCTAssertTrue(outcome.shouldBackOff)
    }

    func test_kraken_http429_backsOff_honorsRetryAfter() async {
        MockURLProtocol.requestHandler = { _ in
            (Self.status(429, KrakenEndpoint.ticker, headers: ["Retry-After": "2"]), Data())
        }
        let outcome = await self.makeClient().fetchKraken(pairs: ["XXBTZUSD"])
        XCTAssertTrue(outcome.shouldBackOff)
        XCTAssertEqual(outcome.retryAfter, .seconds(2))
    }

    func test_kraken_http500_backsOff_noRetryAfter() async {
        MockURLProtocol.requestHandler = { _ in (Self.status(500, KrakenEndpoint.ticker), Data()) }
        let outcome = await self.makeClient().fetchKraken(pairs: ["XXBTZUSD"])
        XCTAssertTrue(outcome.shouldBackOff)
        XCTAssertNil(outcome.retryAfter)
    }

    func test_kraken_networkError_backsOff() async {
        MockURLProtocol.requestHandler = { _ in throw URLError(.notConnectedToInternet) }
        let outcome = await self.makeClient().fetchKraken(pairs: ["XXBTZUSD"])
        XCTAssertTrue(outcome.shouldBackOff)
        XCTAssertTrue(outcome.quotes.isEmpty)
    }

    // MARK: - Coinbase fallback

    func test_coinbase_success() async throws {
        let fixture = try FixtureLoader.load("coinbase-stats-btc.json")
        MockURLProtocol.requestHandler = { request in
            (Self.ok(request.url ?? CoinbaseEndpoint.stats(product: "BTC-USD")), fixture)
        }

        let outcome = await self.makeClient().fetchCoinbase(products: ["XXBTZUSD": "BTC-USD"])

        XCTAssertEqual(outcome.quotes["XXBTZUSD"]?.usdPrice, Decimal(string: "64210.5"))
        XCTAssertEqual(try XCTUnwrap(outcome.quotes["XXBTZUSD"]?.change24h), 1.7599, accuracy: 0.001)
        XCTAssertFalse(outcome.shouldBackOff)
    }

    func test_coinbase_oneProductFails_othersSucceedAndBackOff() async throws {
        let fixture = try FixtureLoader.load("coinbase-stats-btc.json")
        MockURLProtocol.requestHandler = { request in
            let url = request.url ?? CoinbaseEndpoint.stats(product: "BTC-USD")
            if url.path.contains("ETH-USD") {
                return (Self.status(500, url), Data())
            }
            return (Self.ok(url), fixture)
        }

        let outcome = await self.makeClient()
            .fetchCoinbase(products: ["XXBTZUSD": "BTC-USD", "XETHZUSD": "ETH-USD"])

        XCTAssertEqual(outcome.quotes.count, 1)
        XCTAssertNotNil(outcome.quotes["XXBTZUSD"])
        XCTAssertNil(outcome.quotes["XETHZUSD"])
        XCTAssertTrue(outcome.shouldBackOff)
    }

    // MARK: - Helpers

    private static func ok(_ url: URL) -> HTTPURLResponse {
        self.status(200, url)
    }

    private static func status(_ code: Int, _ url: URL, headers: [String: String]? = nil) -> HTTPURLResponse {
        HTTPURLResponse(url: url, statusCode: code, httpVersion: nil, headerFields: headers)!
    }
}
