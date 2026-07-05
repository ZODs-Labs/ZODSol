import SolanaKit
import XCTest
@testable import WalletOverviewDomain

private struct StubEVM: EVMTokenResolving {
    let result: EVMResolution
    func resolve(address: String) async -> EVMResolution {
        self.result
    }
}

private struct StubSolana: TickerTokenResolving {
    let result: ResolvedTickerToken?
    func resolve(mint: String) async -> ResolvedTickerToken? {
        self.result
    }
}

final class TokenPasteResolverTests: XCTestCase {
    private let baseUSDC = "0x833589fcd6edb6e08f4c7c32d4f71b54bda02913"
    private let solUSDC = "EPjFWdd5AufqSSqeM2qN1xzybapC8G4wEGGkZwyTDt1v"

    private func evmToken(_ chain: EVMChain, liquidity: Decimal) -> EVMResolvedToken {
        EVMResolvedToken(
            chain: chain, address: self.baseUSDC, symbol: "USDC", name: "USD Coin",
            iconURL: nil, liquidityUSD: liquidity)
    }

    // MARK: - EVM path

    func testEVMSingleChainResolvesToEntry() async {
        let resolver = TokenPasteResolver(evm: StubEVM(result: .resolved(self.evmToken(.base, liquidity: 5_000_000))))
        guard case let .resolved(entry) = await resolver.resolve(self.baseUSDC) else {
            return XCTFail("expected resolved")
        }
        XCTAssertEqual(entry.source, .evmDex)
        XCTAssertEqual(entry.sourceIdentifier, "evm:base:\(self.baseUSDC)")
        XCTAssertEqual(entry.symbol, "USDC")
    }

    func testEVMMultipleChainsNeedsChoice() async {
        let tokens = [self.evmToken(.ethereum, liquidity: 9_000_000), self.evmToken(.base, liquidity: 4_000_000)]
        let resolver = TokenPasteResolver(evm: StubEVM(result: .multipleChains(tokens)))
        guard case let .needsChainChoice(candidates) = await resolver.resolve(self.baseUSDC) else {
            return XCTFail("expected needsChainChoice")
        }
        XCTAssertEqual(candidates.count, 2)
        XCTAssertEqual(candidates.first?.chainName, "Ethereum")
        XCTAssertEqual(candidates.first?.entry.source, .evmDex)
    }

    func testEVMNotFoundRejects() async {
        let resolver = TokenPasteResolver(evm: StubEVM(result: .notFound))
        guard case let .rejected(message) = await resolver.resolve(self.baseUSDC) else {
            return XCTFail("expected rejected")
        }
        XCTAssertFalse(message.isEmpty)
    }

    func testEVMUnsupportedChainNamesTheChain() async {
        let resolver = TokenPasteResolver(evm: StubEVM(result: .unsupportedChain("Linea")))
        guard case let .rejected(message) = await resolver.resolve(self.baseUSDC) else {
            return XCTFail("expected rejected")
        }
        XCTAssertTrue(message.contains("Linea"))
    }

    func testEVMLowLiquidityRejects() async {
        let resolver = TokenPasteResolver(evm: StubEVM(result: .lowLiquidity(250)))
        guard case let .rejected(message) = await resolver.resolve(self.baseUSDC) else {
            return XCTFail("expected rejected")
        }
        XCTAssertTrue(message.lowercased().contains("liquidity"))
    }

    func testEVMServiceUnavailableRejects() async {
        let resolver = TokenPasteResolver(evm: StubEVM(result: .serviceUnavailable))
        guard case .rejected = await resolver.resolve(self.baseUSDC) else {
            return XCTFail("expected rejected")
        }
    }

    func testEVMPasteWithoutEVMResolverRejects() async {
        let resolver = TokenPasteResolver(solana: StubSolana(result: nil))
        guard case .rejected = await resolver.resolve(self.baseUSDC) else {
            return XCTFail("expected rejected")
        }
    }

    // MARK: - Solana path

    func testSolanaMintResolvesToJupiterEntry() async {
        let token = ResolvedTickerToken(mint: self.solUSDC, symbol: "USDC", name: "USD Coin", decimals: 6, iconURL: nil)
        let resolver = TokenPasteResolver(solana: StubSolana(result: token))
        guard case let .resolved(entry) = await resolver.resolve("  \(self.solUSDC)  ") else {
            return XCTFail("expected resolved")
        }
        XCTAssertEqual(entry.source, .jupiter)
        XCTAssertEqual(entry.sourceIdentifier, self.solUSDC)
    }

    func testSolanaWrappedSolIsSteeredAway() async {
        let resolver = TokenPasteResolver(solana: StubSolana(result: nil))
        guard case let .rejected(message) = await resolver.resolve(TickerCatalog.wrappedSolMint) else {
            return XCTFail("expected rejected")
        }
        XCTAssertTrue(message.contains("SOL"))
    }

    func testSolanaUnresolvedRejects() async {
        let resolver = TokenPasteResolver(solana: StubSolana(result: nil))
        guard case .rejected = await resolver.resolve(self.solUSDC) else {
            return XCTFail("expected rejected")
        }
    }

    // MARK: - Input families

    func testEnsNameRejected() async {
        let resolver = TokenPasteResolver(evm: StubEVM(result: .notFound))
        guard case let .rejected(message) = await resolver.resolve("usdc.eth") else {
            return XCTFail("expected rejected")
        }
        XCTAssertTrue(message.contains("ENS"))
    }

    func testEmptyIsSilentRejection() async {
        let resolver = TokenPasteResolver()
        let result = await resolver.resolve("   ")
        XCTAssertEqual(result, .rejected(""))
    }
}
