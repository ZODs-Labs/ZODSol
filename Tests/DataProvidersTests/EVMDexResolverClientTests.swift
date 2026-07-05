import SolanaKit
import XCTest
@testable import DataProviders

final class EVMDexResolverClientTests: XCTestCase {
    private let baseUSDC = "0x833589fcd6edb6e08f4c7c32d4f71b54bda02913"

    override func setUp() {
        super.setUp()
        MockURLProtocol.reset()
    }

    override func tearDown() {
        MockURLProtocol.reset()
        super.tearDown()
    }

    private func makeResolver(floor: Decimal = 1000) -> EVMDexResolverClient {
        EVMDexResolverClient(session: MockURLProtocol.makeSession(), liquidityFloor: floor)
    }

    private func respond(_ fixture: String) throws {
        let data = try FixtureLoader.load(fixture)
        MockURLProtocol.requestHandler = { request in (Self.ok(request.url!), data) }
    }

    func test_singleSupportedChain_resolvesDeepestPoolMetadata() async throws {
        try self.respond("dexscreener-search-base-usdc.json")
        guard case let .resolved(token) = await self.makeResolver().resolve(address: self.baseUSDC) else {
            return XCTFail("expected resolved")
        }
        XCTAssertEqual(token.chain, .base)
        XCTAssertEqual(token.symbol, "USDC")
        XCTAssertEqual(token.name, "USD Coin")
        XCTAssertEqual(token.address, self.baseUSDC)
        XCTAssertNotNil(token.iconURL)
    }

    func test_multipleChains_needChoice_sortedByLiquidity() async throws {
        try self.respond("dexscreener-search-multichain.json")
        guard case let .multipleChains(tokens) = await self.makeResolver().resolve(address: self.baseUSDC) else {
            return XCTFail("expected multipleChains")
        }
        XCTAssertEqual(tokens.map(\.chain), [.ethereum, .base])
    }

    func test_addressCollision_picksSupportedChainByBaseTokenAndLiquidity_notResultZero() async throws {
        // result[0] is an unsupported PulseChain pair; a base pair belongs to a
        // different token. Only the Ethereum group survives the base-token filter
        // and the supported-chain filter.
        try self.respond("dexscreener-search-collision.json")
        guard case let .resolved(token) = await self.makeResolver().resolve(address: self.baseUSDC) else {
            return XCTFail("expected resolved")
        }
        XCTAssertEqual(token.chain, .ethereum)
    }

    func test_onlyUnsupportedChain_namesTheChain() async throws {
        try self.respond("dexscreener-search-unsupported-only.json")
        let result = await self.makeResolver().resolve(address: self.baseUSDC)
        XCTAssertEqual(result, .unsupportedChain("Pulsechain"))
    }

    func test_belowLiquidityFloor_lowLiquidity() async throws {
        try self.respond("dexscreener-search-lowliq.json")
        guard case .lowLiquidity = await self.makeResolver(floor: 1000).resolve(address: self.baseUSDC) else {
            return XCTFail("expected lowLiquidity")
        }
    }

    func test_noPairs_notFound() async throws {
        try self.respond("dexscreener-search-empty.json")
        let result = await self.makeResolver().resolve(address: self.baseUSDC)
        XCTAssertEqual(result, .notFound)
    }

    func test_httpError_serviceUnavailable() async {
        MockURLProtocol.requestHandler = { request in (Self.status(500, request.url!), Data()) }
        let result = await self.makeResolver().resolve(address: self.baseUSDC)
        XCTAssertEqual(result, .serviceUnavailable)
    }

    func test_invalidAddress_notFound_noNetworkCall() async {
        MockURLProtocol.requestHandler = { _ in
            XCTFail("no network call for an invalid address")
            throw URLError(.unknown)
        }
        let result = await self.makeResolver().resolve(address: "not-an-address")
        XCTAssertEqual(result, .notFound)
    }

    private static func ok(_ url: URL) -> HTTPURLResponse {
        self.status(200, url)
    }

    private static func status(_ code: Int, _ url: URL) -> HTTPURLResponse {
        HTTPURLResponse(url: url, statusCode: code, httpVersion: nil, headerFields: nil)!
    }
}
