import SolanaKit
import XCTest
@testable import DataProviders

final class JupiterTokenResolverTests: XCTestCase {
    private let usdcMint = "EPjFWdd5AufqSSqeM2qN1xzybapC8G4wEGGkZwyTDt1v"
    private let wsolMint = "So11111111111111111111111111111111111111112"

    override func setUp() {
        super.setUp()
        MockURLProtocol.reset()
    }

    override func tearDown() {
        MockURLProtocol.reset()
        super.tearDown()
    }

    private func makeResolver() -> JupiterTokenResolver {
        JupiterTokenResolver(session: MockURLProtocol.makeSession())
    }

    func test_resolve_exactMatch_returnsMetadata() async throws {
        let fixture = try FixtureLoader.load("jupiter-token-search.json")
        MockURLProtocol.requestHandler = { request in
            let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
            return (response, fixture)
        }

        let resolved = await self.makeResolver().resolve(mint: self.usdcMint)
        XCTAssertEqual(resolved?.mint, self.usdcMint)
        XCTAssertEqual(resolved?.symbol, "USDC")
        XCTAssertEqual(resolved?.name, "USD Coin")
        XCTAssertEqual(resolved?.decimals, 6)
        XCTAssertEqual(resolved?.iconURL?.absoluteString, "https://example.com/usdc.png")
    }

    func test_resolve_noExactIdMatch_returnsNil() async throws {
        let fixture = try FixtureLoader.load("jupiter-token-search.json")
        MockURLProtocol.requestHandler = { request in
            let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
            return (response, fixture)
        }

        // The fixture only contains USDC, so a different mint must not match.
        let resolved = await self.makeResolver().resolve(mint: self.wsolMint)
        XCTAssertNil(resolved)
    }

    func test_resolve_non2xx_returnsNil() async {
        MockURLProtocol.requestHandler = { request in
            (HTTPURLResponse(url: request.url!, statusCode: 500, httpVersion: nil, headerFields: nil)!, Data())
        }
        let resolved = await self.makeResolver().resolve(mint: self.usdcMint)
        XCTAssertNil(resolved)
    }

    func test_resolve_networkError_returnsNil() async {
        MockURLProtocol.requestHandler = { _ in throw URLError(.notConnectedToInternet) }
        let resolved = await self.makeResolver().resolve(mint: self.usdcMint)
        XCTAssertNil(resolved)
    }
}
