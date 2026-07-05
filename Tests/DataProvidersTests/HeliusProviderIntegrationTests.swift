import SolanaKit
import SolanaRPC
import XCTest
@testable import DataProviders

final class HeliusProviderIntegrationTests: XCTestCase {
    private func makeProvider(transport: MockRPCTransport) -> HeliusSolanaProvider {
        HeliusSolanaProvider(
            network: .mainnet,
            apiKey: "unused",
            transport: transport,
            priceTransport: transport)
    }

    private let testAddress = try! WalletAddress(base58: "11111111111111111111111111111111")

    // MARK: - solBalance

    func test_solBalance_success() async throws {
        let transport = MockRPCTransport()
        let data = try FixtureLoader.load("get-balance-success.json")
        await transport.enqueue(data: data)

        let provider = self.makeProvider(transport: transport)
        let balance = try await provider.solBalance(for: self.testAddress, network: .mainnet)
        XCTAssertEqual(balance.rawValue, 5_000_000_000)
    }

    // MARK: - tokenAccounts

    func test_tokenAccounts_success() async throws {
        let transport = MockRPCTransport()
        let data = try FixtureLoader.load("get-token-accounts-success.json")
        await transport.enqueue(data: data)

        let provider = self.makeProvider(transport: transport)
        let accounts = try await provider.tokenAccounts(for: self.testAddress, network: .mainnet)
        XCTAssertEqual(accounts.count, 1)
        XCTAssertEqual(accounts[0].mint.base58, "EPjFWdd5AufqSSqeM2qN1xzybapC8G4wEGGkZwyTDt1v")
        XCTAssertEqual(accounts[0].amount.amount, 1_000_000)
        XCTAssertEqual(accounts[0].amount.decimals, 6)
    }

    // MARK: - assets

    func test_assets_success_mapsAssetPage() async throws {
        let transport = MockRPCTransport()
        let data = try FixtureLoader.load("assets-by-owner-success.json")
        await transport.enqueue(data: data)

        let provider = self.makeProvider(transport: transport)
        let page = try await provider.assets(for: self.testAddress, network: .mainnet, options: .default)

        XCTAssertNotNil(page.nativeSol)
        XCTAssertEqual(page.nativeSol?.lamports.rawValue, 5_000_000_000)
        XCTAssertEqual(page.nativeSol?.pricePerSol, 150.50)
        XCTAssertEqual(page.page, 1)
        XCTAssertEqual(page.limit, 1000)

        let fungibles = page.items.filter { $0.kind == .fungible }
        XCTAssertEqual(fungibles.count, 2)

        let usdc = try XCTUnwrap(fungibles.first(where: { $0.symbol == "USDC" }))
        XCTAssertEqual(usdc.amount.amount, 1_000_000)
        XCTAssertEqual(usdc.amount.decimals, 6)
        XCTAssertEqual(usdc.pricePerToken, 1.0)

        let nfts = page.items.filter { $0.kind == .nft }
        XCTAssertEqual(nfts.count, 3)

        let others = page.items.filter { $0.kind == .other }
        XCTAssertEqual(others.count, 1)
    }

    func test_assets_nativeSol_absent_when_option_disabled() async throws {
        let transport = MockRPCTransport()
        let data = try FixtureLoader.load("assets-by-owner-success.json")
        await transport.enqueue(data: data)

        let provider = self.makeProvider(transport: transport)
        var options = AssetQueryOptions.default
        options.showNativeBalance = false
        let page = try await provider.assets(for: self.testAddress, network: .mainnet, options: options)
        XCTAssertNil(page.nativeSol)
    }

    // MARK: - Error mapping

    func test_http429_throws_rateLimited() async throws {
        let transport = MockRPCTransport()
        await transport.enqueueError(.http(status: 429, retryAfter: .seconds(2)))

        let provider = self.makeProvider(transport: transport)
        do {
            _ = try await provider.solBalance(for: self.testAddress, network: .mainnet)
            XCTFail("Should have thrown")
        } catch let error as SolanaProviderError {
            XCTAssertEqual(error, .rateLimited(retryAfter: .seconds(2)))
        }
    }

    func test_http500_throws_providerUnavailable() async throws {
        let transport = MockRPCTransport()
        await transport.enqueueError(.http(status: 500, retryAfter: nil))

        let provider = self.makeProvider(transport: transport)
        do {
            _ = try await provider.solBalance(for: self.testAddress, network: .mainnet)
            XCTFail("Should have thrown")
        } catch let error as SolanaProviderError {
            XCTAssertEqual(error, .providerUnavailable(message: "Helius 500"))
        }
    }

    func test_http401_throws_unauthorized() async throws {
        let transport = MockRPCTransport()
        await transport.enqueueError(.http(status: 401, retryAfter: nil))

        let provider = self.makeProvider(transport: transport)
        do {
            _ = try await provider.solBalance(for: self.testAddress, network: .mainnet)
            XCTFail("Should have thrown")
        } catch let error as SolanaProviderError {
            XCTAssertEqual(error, .unauthorized)
        }
    }

    func test_rpc_error_32005_throws_rateLimited() async throws {
        let transport = MockRPCTransport()
        let data = try FixtureLoader.load("assets-by-owner-rate-limit.json")
        await transport.enqueue(data: data)

        let provider = self.makeProvider(transport: transport)
        do {
            _ = try await provider.assets(for: self.testAddress, network: .mainnet, options: .default)
            XCTFail("Should have thrown")
        } catch let error as SolanaProviderError {
            XCTAssertEqual(error, .rateLimited(retryAfter: nil))
        }
    }

    func test_rpc_error_32602_throws_invalidInput() async throws {
        let transport = MockRPCTransport()
        let errorJSON = """
        {"jsonrpc":"2.0","id":"x","error":{"code":-32602,"message":"Invalid params"}}
        """.data(using: .utf8)!
        await transport.enqueue(data: errorJSON)

        let provider = self.makeProvider(transport: transport)
        do {
            _ = try await provider.assets(for: self.testAddress, network: .mainnet, options: .default)
            XCTFail("Should have thrown")
        } catch let error as SolanaProviderError {
            XCTAssertEqual(error, .invalidInput("Invalid params"))
        }
    }

    func test_canceled_throws_canceled() async throws {
        let transport = MockRPCTransport()
        await transport.enqueueError(.canceled)

        let provider = self.makeProvider(transport: transport)
        do {
            _ = try await provider.solBalance(for: self.testAddress, network: .mainnet)
            XCTFail("Should have thrown")
        } catch let error as SolanaProviderError {
            XCTAssertEqual(error, .canceled)
        }
    }

    func test_decoding_failure_throws_malformedResponse() async throws {
        let transport = MockRPCTransport()
        await transport.enqueueError(.decoding("unexpected structure"))

        let provider = self.makeProvider(transport: transport)
        do {
            _ = try await provider.solBalance(for: self.testAddress, network: .mainnet)
            XCTFail("Should have thrown")
        } catch let error as SolanaProviderError {
            XCTAssertEqual(error, .malformedResponse("unexpected structure"))
        }
    }

    func test_notConnectedToInternet_throws_networkUnavailable() async throws {
        let transport = MockRPCTransport()
        await transport.enqueueError(.transport(.notConnectedToInternet))

        let provider = self.makeProvider(transport: transport)
        do {
            _ = try await provider.solBalance(for: self.testAddress, network: .mainnet)
            XCTFail("Should have thrown")
        } catch let error as SolanaProviderError {
            XCTAssertEqual(error, .networkUnavailable)
        }
    }
}
