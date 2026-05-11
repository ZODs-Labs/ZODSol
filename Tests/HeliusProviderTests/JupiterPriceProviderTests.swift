import XCTest
import SolanaKit
@testable import HeliusProvider

final class JupiterPriceProviderTests: XCTestCase {

    override func setUp() {
        super.setUp()
        MockURLProtocol.reset()
    }

    override func tearDown() {
        MockURLProtocol.reset()
        super.tearDown()
    }

    private func makeProvider() -> JupiterPriceProvider {
        let client = JupiterClient(session: MockURLProtocol.makeSession())
        return JupiterPriceProvider(client: client)
    }

    // MARK: - priceChange24h

    func test_emptyMints_returnsEmptyMap_noNetworkCall() async throws {
        MockURLProtocol.requestHandler = { _ in
            XCTFail("No network call should be made for empty mints")
            throw URLError(.unknown)
        }

        let provider = makeProvider()
        let result = try await provider.priceChange24h(for: [])
        XCTAssertTrue(result.isEmpty)
    }

    func test_success_withThreeMints() async throws {
        let fixtureData = try FixtureLoader.load("jupiter-price-success.json")
        MockURLProtocol.requestHandler = { _ in
            let response = HTTPURLResponse(
                url: JupiterEndpoint.priceV3,
                statusCode: 200,
                httpVersion: nil,
                headerFields: nil
            )!
            return (response, fixtureData)
        }

        let mints = [
            try Mint(base58: "EPjFWdd5AufqSSqeM2qN1xzybapC8G4wEGGkZwyTDt1v"),
            try Mint(base58: "Es9vMFrzaCERmJfrF4H2FYD4KCoNkY11McCe8BenwNYB"),
            try Mint(base58: "So11111111111111111111111111111111111111112"),
        ]
        let provider = makeProvider()
        let result = try await provider.priceChange24h(for: mints)

        XCTAssertEqual(result.count, 3)
        XCTAssertEqual(result[mints[0]], 0.02)
        XCTAssertEqual(result[mints[1]], -0.05)
        XCTAssertEqual(result[mints[2]], 3.45)
    }

    func test_http429_returnsEmptyMap_noThrow() async throws {
        MockURLProtocol.requestHandler = { _ in
            let response = HTTPURLResponse(
                url: JupiterEndpoint.priceV3,
                statusCode: 429,
                httpVersion: nil,
                headerFields: nil
            )!
            return (response, Data())
        }

        let mint = try Mint(base58: "EPjFWdd5AufqSSqeM2qN1xzybapC8G4wEGGkZwyTDt1v")
        let provider = makeProvider()
        let result = try await provider.priceChange24h(for: [mint])
        XCTAssertTrue(result.isEmpty)
    }

    func test_networkError_returnsEmptyMap() async throws {
        MockURLProtocol.requestHandler = { _ in
            throw URLError(.notConnectedToInternet)
        }

        let mint = try Mint(base58: "EPjFWdd5AufqSSqeM2qN1xzybapC8G4wEGGkZwyTDt1v")
        let provider = makeProvider()
        let result = try await provider.priceChange24h(for: [mint])
        XCTAssertTrue(result.isEmpty)
    }

    func test_51_mints_sends_2_chunks() async throws {
        let fixtureData = try FixtureLoader.load("jupiter-price-success.json")
        MockURLProtocol.requestHandler = { _ in
            let response = HTTPURLResponse(
                url: JupiterEndpoint.priceV3,
                statusCode: 200,
                httpVersion: nil,
                headerFields: nil
            )!
            return (response, fixtureData)
        }

        let baseMint = try Mint(base58: "EPjFWdd5AufqSSqeM2qN1xzybapC8G4wEGGkZwyTDt1v")
        let mints = Array(repeating: baseMint, count: 51)
        let provider = makeProvider()
        _ = try await provider.priceChange24h(for: mints)

        XCTAssertEqual(MockURLProtocol.requestLog.count, 2)
    }

    // MARK: - solChange24h

    func test_solChange24h_success() async throws {
        let fixtureData = try FixtureLoader.load("jupiter-price-success.json")
        MockURLProtocol.requestHandler = { _ in
            let response = HTTPURLResponse(
                url: JupiterEndpoint.priceV3,
                statusCode: 200,
                httpVersion: nil,
                headerFields: nil
            )!
            return (response, fixtureData)
        }

        let provider = makeProvider()
        let change = try await provider.solChange24h()
        XCTAssertEqual(change, 3.45)
    }

    func test_solChange24h_networkError_returnsNil() async throws {
        MockURLProtocol.requestHandler = { _ in
            throw URLError(.notConnectedToInternet)
        }

        let provider = makeProvider()
        let change = try await provider.solChange24h()
        XCTAssertNil(change)
    }
}
