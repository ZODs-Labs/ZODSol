import XCTest
@testable import DataProviders

final class HeliusDTOTests: XCTestCase {
    func test_decodeAssetsByOwnerResult() throws {
        let data = try FixtureLoader.load("assets-by-owner-success.json")
        let envelope = try JSONDecoder().decode(RPCEnvelope<HeliusAssetsByOwnerResult>.self, from: data)
        let result = try XCTUnwrap(envelope.result)

        XCTAssertEqual(result.total, 6)
        XCTAssertEqual(result.limit, 1000)
        XCTAssertEqual(result.page, 1)
        XCTAssertEqual(result.last_indexed_slot, 300_000_000)
        XCTAssertEqual(result.items.count, 6)

        let nb = try XCTUnwrap(result.nativeBalance)
        XCTAssertEqual(nb.lamports, 5_000_000_000)
        XCTAssertEqual(nb.price_per_sol, 150.50)
        XCTAssertEqual(nb.total_price, 752.50)

        let fungible = result.items[0]
        XCTAssertEqual(fungible.interface, "FungibleToken")
        XCTAssertEqual(fungible.token_info?.balance, 1_000_000)
        XCTAssertEqual(fungible.token_info?.decimals, 6)
        XCTAssertEqual(fungible.token_info?.symbol, "USDC")
        XCTAssertEqual(fungible.content?.metadata?.name, "USD Coin")

        let nft = result.items[2]
        XCTAssertEqual(nft.interface, "V1_NFT")
        XCTAssertEqual(nft.content?.metadata?.name, "Test NFT #1")
    }

    func test_decodeBalanceResult() throws {
        let data = try FixtureLoader.load("get-balance-success.json")
        let envelope = try JSONDecoder().decode(RPCEnvelope<HeliusBalanceResult>.self, from: data)
        let result = try XCTUnwrap(envelope.result)

        XCTAssertEqual(result.context.slot, 300_000_000)
        XCTAssertEqual(result.value, 5_000_000_000)
    }

    func test_decodeTokenAccountsResult() throws {
        let data = try FixtureLoader.load("get-token-accounts-success.json")
        let envelope = try JSONDecoder().decode(RPCEnvelope<HeliusTokenAccountsResult>.self, from: data)
        let result = try XCTUnwrap(envelope.result)

        XCTAssertEqual(result.context.slot, 300_000_000)
        XCTAssertEqual(result.context.apiVersion, "2.0.15")
        XCTAssertEqual(result.value.count, 1)

        let holding = result.value[0]
        XCTAssertEqual(holding.pubkey, "ATokenGPvbdGVxr1b2hvZbsiqW5xWH25efTNsLJA8knL")
        XCTAssertEqual(holding.account.data.parsed.info.mint, "EPjFWdd5AufqSSqeM2qN1xzybapC8G4wEGGkZwyTDt1v")
        XCTAssertEqual(holding.account.data.parsed.info.tokenAmount.amount, "1000000")
        XCTAssertEqual(holding.account.data.parsed.info.tokenAmount.decimals, 6)
    }

    func test_decodeJupiterPriceResponse() throws {
        let data = try FixtureLoader.load("jupiter-price-success.json")
        let response = try JSONDecoder().decode(JupiterPriceResponse.self, from: data)

        XCTAssertEqual(response.entries.count, 3)

        let usdc = try XCTUnwrap(response.entries["EPjFWdd5AufqSSqeM2qN1xzybapC8G4wEGGkZwyTDt1v"])
        XCTAssertEqual(usdc.priceChange24h, 0.02)
        XCTAssertEqual(usdc.decimals, 6)

        let sol = try XCTUnwrap(response.entries["So11111111111111111111111111111111111111112"])
        XCTAssertEqual(sol.priceChange24h, 3.45)
    }

    func test_decodeRateLimitError() throws {
        let data = try FixtureLoader.load("assets-by-owner-rate-limit.json")
        let envelope = try JSONDecoder().decode(RPCEnvelope<HeliusAssetsByOwnerResult>.self, from: data)

        XCTAssertNil(envelope.result)
        let rpcError = try XCTUnwrap(envelope.error)
        XCTAssertEqual(rpcError.code, -32005)
        XCTAssertEqual(rpcError.message, "Node is behind by 42 slots")
    }
}

private struct RPCEnvelope<T: Decodable>: Decodable {
    let jsonrpc: String
    let id: String
    let result: T?
    let error: RPCErrorPayload?
}

private struct RPCErrorPayload: Decodable {
    let code: Int
    let message: String
}
