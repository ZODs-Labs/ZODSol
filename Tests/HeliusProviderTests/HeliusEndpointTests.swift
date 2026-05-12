import SolanaKit
import XCTest
@testable import HeliusProvider

final class HeliusEndpointTests: XCTestCase {
    func test_mainnet_url() {
        let ep = HeliusEndpoint(network: .mainnet, apiKey: "test-key")
        XCTAssertEqual(ep.rpcURL.scheme, "https")
        XCTAssertEqual(ep.rpcURL.host, "mainnet.helius-rpc.com")
        XCTAssertEqual(ep.rpcURL.path, "/")
        let items = URLComponents(url: ep.rpcURL, resolvingAgainstBaseURL: false)?.queryItems
        XCTAssertEqual(items?.first(where: { $0.name == "api-key" })?.value, "test-key")
    }

    func test_devnet_url() {
        let ep = HeliusEndpoint(network: .devnet, apiKey: "dev-key")
        XCTAssertEqual(ep.rpcURL.host, "devnet.helius-rpc.com")
        let items = URLComponents(url: ep.rpcURL, resolvingAgainstBaseURL: false)?.queryItems
        XCTAssertEqual(items?.first(where: { $0.name == "api-key" })?.value, "dev-key")
    }

    func test_testnet_url() {
        let ep = HeliusEndpoint(network: .testnet, apiKey: "test-key")
        XCTAssertEqual(ep.rpcURL.host, "api.testnet.solana.com")
    }

    func test_scheme_is_https() {
        for network: SolanaNetwork in [.mainnet, .devnet, .testnet] {
            let ep = HeliusEndpoint(network: network, apiKey: "k")
            XCTAssertEqual(ep.rpcURL.scheme, "https", "\(network) should use https")
        }
    }

    func test_jupiterEndpoint_priceV3() {
        XCTAssertEqual(JupiterEndpoint.priceV3.absoluteString, "https://lite-api.jup.ag/price/v3")
    }
}
