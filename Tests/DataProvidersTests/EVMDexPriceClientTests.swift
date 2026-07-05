import SolanaKit
import XCTest
@testable import DataProviders

final class EVMDexPriceClientTests: XCTestCase {
    private let baseUSDC = "0x833589fcd6edb6e08f4c7c32d4f71b54bda02913"

    override func setUp() {
        super.setUp()
        MockURLProtocol.reset()
    }

    override func tearDown() {
        MockURLProtocol.reset()
        super.tearDown()
    }

    private func ref() -> EVMTokenRef {
        EVMTokenRef(chain: .base, address: self.baseUSDC)
    }

    private func makeClient() -> EVMDexPriceClient {
        EVMDexPriceClient(session: MockURLProtocol.makeSession())
    }

    func test_refresh_usesDeepestPool_keyedBySourceIdentifier() async throws {
        let data = try FixtureLoader.load("dexscreener-tokens-base.json")
        MockURLProtocol.requestHandler = { request in (Self.ok(request.url!), data) }

        let outcome = await self.makeClient().quotes(for: [self.ref()])

        let identifier = self.ref().sourceIdentifier
        XCTAssertEqual(outcome.quotes[identifier]?.usdPrice, Decimal(string: "1.0001"))
        XCTAssertEqual(try XCTUnwrap(outcome.quotes[identifier]?.change24h), 0.05, accuracy: 0.0001)
        XCTAssertFalse(outcome.shouldBackOff)
    }

    func test_429_backsOff_honorsRetryAfter() async {
        MockURLProtocol.requestHandler = { request in
            (Self.status(429, request.url!, headers: ["Retry-After": "3"]), Data())
        }
        let outcome = await self.makeClient().quotes(for: [self.ref()])
        XCTAssertTrue(outcome.shouldBackOff)
        XCTAssertEqual(outcome.retryAfter, .seconds(3))
        XCTAssertTrue(outcome.quotes.isEmpty)
    }

    func test_dexScreenerEmpty_fallsBackToDefiLlama() async throws {
        let current = try FixtureLoader.load("defillama-current.json")
        let percentage = try FixtureLoader.load("defillama-percentage.json")
        MockURLProtocol.requestHandler = { request in
            let url = request.url!
            if url.host == "api.dexscreener.com" {
                return (Self.ok(url), Data("[]".utf8))
            }
            if url.path.contains("/percentage/") {
                return (Self.ok(url), percentage)
            }
            return (Self.ok(url), current)
        }

        let outcome = await self.makeClient().quotes(for: [self.ref()])

        let identifier = self.ref().sourceIdentifier
        XCTAssertEqual(outcome.quotes[identifier]?.usdPrice, Decimal(string: "1.0002"))
        XCTAssertEqual(try XCTUnwrap(outcome.quotes[identifier]?.change24h), -0.12, accuracy: 0.0001)
    }

    private static func ok(_ url: URL) -> HTTPURLResponse {
        self.status(200, url)
    }

    private static func status(_ code: Int, _ url: URL, headers: [String: String]? = nil) -> HTTPURLResponse {
        HTTPURLResponse(url: url, statusCode: code, httpVersion: nil, headerFields: headers)!
    }
}
