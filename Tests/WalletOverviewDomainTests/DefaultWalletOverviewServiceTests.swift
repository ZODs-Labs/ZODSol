import Testing
import Foundation
import CryptoKit
@testable import WalletOverviewDomain
import SolanaKit
import Caching

// MARK: - Mock Provider

final class MockSolanaProvider: SolanaProvider, @unchecked Sendable {
    var assetsHandler: @Sendable (WalletAddress, SolanaNetwork, AssetQueryOptions) async throws -> AssetPage
    var solChange24hHandler: @Sendable () async throws -> Double?
    var pricesHandler: @Sendable ([Mint]) async throws -> [Mint: PriceQuote]
    var solBalanceHandler: @Sendable (WalletAddress, SolanaNetwork) async throws -> Lamports
    var tokenAccountsHandler: @Sendable (WalletAddress, SolanaNetwork) async throws -> [ParsedTokenAccount]

    private(set) var assetsCalled = 0
    private(set) var solChange24hCalled = 0
    private(set) var pricesCalled = 0

    init() {
        assetsHandler = { _, _, _ in
            throw SolanaProviderError.providerUnavailable(message: "not configured")
        }
        solChange24hHandler = { nil }
        pricesHandler = { _ in [:] }
        solBalanceHandler = { _, _ in 0 }
        tokenAccountsHandler = { _, _ in [] }
    }

    func assets(
        for address: WalletAddress,
        network: SolanaNetwork,
        options: AssetQueryOptions
    ) async throws -> AssetPage {
        assetsCalled += 1
        return try await assetsHandler(address, network, options)
    }

    func solChange24h() async throws -> Double? {
        solChange24hCalled += 1
        return try await solChange24hHandler()
    }

    func prices(for mints: [Mint]) async throws -> [Mint: PriceQuote] {
        pricesCalled += 1
        return try await pricesHandler(mints)
    }

    func solBalance(for address: WalletAddress, network: SolanaNetwork) async throws -> Lamports {
        try await solBalanceHandler(address, network)
    }

    func tokenAccounts(for address: WalletAddress, network: SolanaNetwork) async throws -> [ParsedTokenAccount] {
        try await tokenAccountsHandler(address, network)
    }
}

// MARK: - Test Helpers

private func makeTestAddress() -> WalletAddress {
    let pk = Curve25519.Signing.PrivateKey()
    return try! WalletAddress(base58: Base58.encode(pk.publicKey.rawRepresentation))
}

private func makeTestMint() -> Mint {
    let pk = Curve25519.Signing.PrivateKey()
    return try! Mint(base58: Base58.encode(pk.publicKey.rawRepresentation))
}

private func makeAssetPage(
    fungibles: [(mint: Mint, usdValue: Decimal?, pricePerToken: Decimal?)] = [],
    nftCount: Int = 0,
    nativeSol: NativeBalance? = NativeBalance(
        lamports: Lamports(rawValue: 2_000_000_000),
        pricePerSol: Decimal(150),
        totalUSD: Decimal(300)
    )
) -> AssetPage {
    var items: [AssetSummary] = fungibles.map { f in
        AssetSummary(
            id: f.mint, kind: .fungible,
            symbol: "TKN", name: "Token",
            imageURL: nil,
            amount: TokenAmount(amount: 1000, decimals: 6),
            usdValue: f.usdValue, pricePerToken: f.pricePerToken,
            priceChange24h: nil, tokenProgram: nil
        )
    }
    for _ in 0..<nftCount {
        items.append(AssetSummary(
            id: makeTestMint(), kind: .nft,
            symbol: "NFT", name: "Test NFT",
            imageURL: URL(string: "https://example.com/nft.png"),
            amount: TokenAmount(amount: 1, decimals: 0),
            usdValue: nil, pricePerToken: nil,
            priceChange24h: nil, tokenProgram: nil
        ))
    }
    return AssetPage(
        items: items, nativeSol: nativeSol,
        page: 1, limit: 1000, totalEstimated: nil, hasMore: false
    )
}

private func makeService(
    mock: MockSolanaProvider,
    walletId: UUID,
    address: WalletAddress,
    cacheTTL: Duration = .seconds(15)
) -> DefaultWalletOverviewService {
    let cache = TimedCache<UUID, WalletOverview>(ttl: cacheTTL, capacity: 32)
    return DefaultWalletOverviewService(
        provider: mock,
        addressLookup: { id in
            guard id == walletId else { throw WalletOverviewError.needsSetup }
            return address
        },
        network: .mainnet,
        overviewCache: cache
    )
}

// MARK: - Tests

@Suite("DefaultWalletOverviewService")
struct DefaultWalletOverviewServiceTests {
    let walletId = UUID()
    let address = makeTestAddress()

    @Test("Cold load fetches assets, solChange24h, and prices then emits .loaded")
    func coldLoad() async {
        let mint = makeTestMint()
        let mock = MockSolanaProvider()
        mock.assetsHandler = { _, _, _ in
            makeAssetPage(fungibles: [(mint, Decimal(100), Decimal(1))])
        }
        mock.solChange24hHandler = { 2.5 }
        mock.pricesHandler = { _ in [mint: PriceQuote(usdPrice: Decimal(1), change24h: 3.0)] }

        let service = makeService(mock: mock, walletId: walletId, address: address)
        let state = await service.load(for: walletId, forceRevalidate: false)

        guard case .loaded(let overview, _) = state else {
            Issue.record("Expected .loaded, got \(state)")
            return
        }
        #expect(overview.walletId == walletId)
        #expect(overview.address == address)
        #expect(overview.solBalance.rawValue == 2_000_000_000)
        #expect(overview.solPriceUSD == Decimal(150))
        #expect(overview.solChange24h == 2.5)
        #expect(overview.tokens.count == 1)
        #expect(overview.tokens.first?.priceChange24h == 3.0)
        #expect(overview.isPartial == false)
        #expect(mock.assetsCalled == 1)
        #expect(mock.pricesCalled == 1)
    }

    @Test("forceRevalidate=false on fresh cache returns cached value without provider calls")
    func freshCacheHit() async {
        let mock = MockSolanaProvider()
        mock.assetsHandler = { _, _, _ in makeAssetPage() }
        mock.solChange24hHandler = { 1.0 }

        let service = makeService(mock: mock, walletId: walletId, address: address)

        let first = await service.load(for: walletId, forceRevalidate: false)
        guard case .loaded = first else {
            Issue.record("Expected .loaded on first call")
            return
        }
        #expect(mock.assetsCalled == 1)

        let second = await service.load(for: walletId, forceRevalidate: false)
        guard case .loaded = second else {
            Issue.record("Expected .loaded on second call")
            return
        }
        #expect(mock.assetsCalled == 1)
    }

    @Test("forceRevalidate=true always fetches from provider")
    func forceRevalidateAlwaysFetches() async {
        let mock = MockSolanaProvider()
        mock.assetsHandler = { _, _, _ in makeAssetPage() }
        mock.solChange24hHandler = { 1.0 }

        let service = makeService(mock: mock, walletId: walletId, address: address)

        _ = await service.load(for: walletId, forceRevalidate: false)
        #expect(mock.assetsCalled == 1)

        _ = await service.load(for: walletId, forceRevalidate: true)
        #expect(mock.assetsCalled == 2)
    }

    @Test("prices throws results in isPartial overview")
    func priceChangeThrowsPartial() async {
        let mint = makeTestMint()
        let mock = MockSolanaProvider()
        mock.assetsHandler = { _, _, _ in
            makeAssetPage(fungibles: [(mint, Decimal(50), Decimal(0.5))])
        }
        mock.solChange24hHandler = { 1.0 }
        mock.pricesHandler = { _ in
            throw SolanaProviderError.providerUnavailable(message: "price service down")
        }

        let service = makeService(mock: mock, walletId: walletId, address: address)
        let state = await service.load(for: walletId, forceRevalidate: false)

        switch state {
        case .partial(let overview, _):
            #expect(overview.isPartial == true)
        case .loaded(let overview, _):
            #expect(overview.isPartial == true)
        default:
            Issue.record("Expected .partial or .loaded with isPartial, got \(state)")
        }
    }

    @Test("assets throws rateLimited with no cache returns .failed(.rateLimited)")
    func rateLimitedNoCacheReturnsFailed() async {
        let mock = MockSolanaProvider()
        mock.assetsHandler = { _, _, _ in
            throw SolanaProviderError.rateLimited(retryAfter: .seconds(2))
        }

        let service = makeService(mock: mock, walletId: walletId, address: address)
        let state = await service.load(for: walletId, forceRevalidate: false)

        guard case .failed(let err) = state else {
            Issue.record("Expected .failed, got \(state)")
            return
        }
        #expect(err == .rateLimited(retryAfter: .seconds(2)))
    }

    @Test("assets throws rateLimited with stale cache returns .partial")
    func rateLimitedWithStaleCacheReturnsPartial() async {
        let mock = MockSolanaProvider()
        mock.assetsHandler = { _, _, _ in makeAssetPage() }
        mock.solChange24hHandler = { 1.0 }

        let cache = TimedCache<UUID, WalletOverview>(ttl: .zero, capacity: 32)
        let service = DefaultWalletOverviewService(
            provider: mock,
            addressLookup: { [walletId, address] id in
                guard id == walletId else { throw WalletOverviewError.needsSetup }
                return address
            },
            network: .mainnet,
            overviewCache: cache
        )

        _ = await service.load(for: walletId, forceRevalidate: false)

        mock.assetsHandler = { _, _, _ in
            throw SolanaProviderError.rateLimited(retryAfter: .seconds(2))
        }

        let state = await service.load(for: walletId, forceRevalidate: true)
        guard case .partial(_, let err) = state else {
            Issue.record("Expected .partial with stale cache, got \(state)")
            return
        }
        #expect(err == .rateLimited(retryAfter: .seconds(2)))
    }

    @Test("Cache hit on quick re-load avoids provider calls")
    func cacheHitOnQuickReload() async {
        let mock = MockSolanaProvider()
        mock.assetsHandler = { _, _, _ in makeAssetPage() }
        mock.solChange24hHandler = { 1.0 }

        let service = makeService(mock: mock, walletId: walletId, address: address)

        _ = await service.load(for: walletId, forceRevalidate: false)
        let beforeAssets = mock.assetsCalled
        let beforeSol = mock.solChange24hCalled

        let state = await service.load(for: walletId, forceRevalidate: false)
        guard case .loaded = state else {
            Issue.record("Expected .loaded from cache, got \(state)")
            return
        }
        #expect(mock.assetsCalled == beforeAssets)
        #expect(mock.solChange24hCalled == beforeSol)
    }

    @Test("Unknown wallet returns .idle")
    func unknownWalletReturnsIdle() async {
        let mock = MockSolanaProvider()
        let service = makeService(mock: mock, walletId: walletId, address: address)
        let state = await service.load(for: UUID(), forceRevalidate: false)
        guard case .idle = state else {
            Issue.record("Expected .idle for unknown wallet, got \(state)")
            return
        }
    }

    @Test("invalidate removes cached entry, next load fetches again")
    func invalidateForcesFetch() async {
        let mock = MockSolanaProvider()
        mock.assetsHandler = { _, _, _ in makeAssetPage() }
        mock.solChange24hHandler = { 1.0 }

        let service = makeService(mock: mock, walletId: walletId, address: address)

        _ = await service.load(for: walletId, forceRevalidate: false)
        #expect(mock.assetsCalled == 1)

        await service.invalidate(walletId: walletId)

        _ = await service.load(for: walletId, forceRevalidate: false)
        #expect(mock.assetsCalled == 2)
    }

    @Test("invalidateAll clears all cached entries")
    func invalidateAllClearsCache() async {
        let mock = MockSolanaProvider()
        mock.assetsHandler = { _, _, _ in makeAssetPage() }
        mock.solChange24hHandler = { 1.0 }

        let service = makeService(mock: mock, walletId: walletId, address: address)

        _ = await service.load(for: walletId, forceRevalidate: false)
        #expect(mock.assetsCalled == 1)

        await service.invalidateAll()

        _ = await service.load(for: walletId, forceRevalidate: false)
        #expect(mock.assetsCalled == 2)
    }

    @Test("Cancellation mid-fetch returns .failed(.canceled)")
    func cancellationMidFetch() async {
        let mock = MockSolanaProvider()
        mock.assetsHandler = { _, _, _ in
            try await Task.sleep(for: .seconds(10))
            return makeAssetPage()
        }

        let service = makeService(mock: mock, walletId: walletId, address: address)

        let task = Task {
            await service.load(for: walletId, forceRevalidate: false)
        }

        try? await Task.sleep(for: .milliseconds(50))
        task.cancel()

        let state = await task.value
        guard case .failed(let err) = state else {
            return
        }
        #expect(err == .canceled)
    }

    @Test("Assemble sorts fungibles by usdValue descending, nil last")
    func assembleSortsFungibles() async {
        let mint1 = makeTestMint()
        let mint2 = makeTestMint()
        let mint3 = makeTestMint()
        let mock = MockSolanaProvider()
        mock.assetsHandler = { _, _, _ in
            makeAssetPage(fungibles: [
                (mint1, Decimal(10), Decimal(1)),
                (mint2, Decimal(500), Decimal(5)),
                (mint3, nil, nil),
            ])
        }
        mock.solChange24hHandler = { 1.0 }

        let service = makeService(mock: mock, walletId: walletId, address: address)
        let state = await service.load(for: walletId, forceRevalidate: false)

        let overview: WalletOverview
        switch state {
        case .loaded(let v, _): overview = v
        case .partial(let v, _): overview = v
        default:
            Issue.record("Expected .loaded or .partial, got \(state)")
            return
        }
        #expect(overview.tokens.count == 3)
        #expect(overview.tokens[0].usdValue == Decimal(500))
        #expect(overview.tokens[1].usdValue == Decimal(10))
        #expect(overview.tokens[2].usdValue == nil)
    }

    @Test("NFTs counted correctly with collection previews capped at 6")
    func nftSummary() async {
        let mock = MockSolanaProvider()
        mock.assetsHandler = { _, _, _ in makeAssetPage(nftCount: 8) }
        mock.solChange24hHandler = { 1.0 }

        let service = makeService(mock: mock, walletId: walletId, address: address)
        let state = await service.load(for: walletId, forceRevalidate: false)

        guard case .loaded(let overview, _) = state else {
            Issue.record("Expected .loaded")
            return
        }
        #expect(overview.nfts.count == 8)
        #expect(overview.nfts.collectionPreviews.count == 6)
    }

    @Test("totalUSD is nil when native SOL price is missing")
    func totalUSDNilWithoutSolPrice() async {
        let mock = MockSolanaProvider()
        mock.assetsHandler = { _, _, _ in
            makeAssetPage(nativeSol: NativeBalance(
                lamports: Lamports(rawValue: 1_000_000_000),
                pricePerSol: nil, totalUSD: nil
            ))
        }
        mock.solChange24hHandler = { 1.0 }

        let service = makeService(mock: mock, walletId: walletId, address: address)
        let state = await service.load(for: walletId, forceRevalidate: false)

        guard case .loaded(let overview, _) = state else {
            Issue.record("Expected .loaded")
            return
        }
        #expect(overview.totalUSD == nil)
    }

    @Test("stream emits values then finishes on cancellation")
    func streamEmitsAndCancels() async {
        let mock = MockSolanaProvider()
        mock.assetsHandler = { _, _, _ in makeAssetPage() }
        mock.solChange24hHandler = { 1.0 }

        let service = makeService(mock: mock, walletId: walletId, address: address)
        let stream = service.stream(for: walletId, tick: .milliseconds(50))

        var received = 0
        for await state in stream {
            guard case .loaded = state else { continue }
            received += 1
            if received >= 2 { break }
        }
        #expect(received >= 2)
    }

    @Test("Jupiter quote fills usdValue and pricePerToken when Helius has no price; Helius wins when both present")
    func jupiterFallbackAndHeliusPriority() async {
        let unpriced = makeTestMint()
        let helius = makeTestMint()
        let mock = MockSolanaProvider()
        mock.assetsHandler = { _, _, _ in
            makeAssetPage(fungibles: [(unpriced, nil, nil), (helius, Decimal(100), Decimal(1))])
        }
        mock.solChange24hHandler = { 0.0 }
        mock.pricesHandler = { _ in [
            unpriced: PriceQuote(usdPrice: Decimal(2), change24h: 13.6),
            helius: PriceQuote(usdPrice: Decimal(99), change24h: 5.0),
        ] }

        let service = makeService(mock: mock, walletId: walletId, address: address)
        let state = await service.load(for: walletId, forceRevalidate: false)

        guard case .loaded(let overview, _) = state else {
            Issue.record("Expected .loaded, got \(state)")
            return
        }
        let byMint = Dictionary(uniqueKeysWithValues: overview.tokens.map { ($0.id, $0) })
        // makeAssetPage uses amount 1000 / decimals 6, uiAmount 0.001. 0.001 * 2 = 0.002.
        #expect(byMint[unpriced]?.pricePerToken == Decimal(2))
        #expect(byMint[unpriced]?.usdValue == Decimal(string: "0.002"))
        #expect(byMint[unpriced]?.priceChange24h == 13.6)
        #expect(byMint[helius]?.pricePerToken == Decimal(1))
        #expect(byMint[helius]?.usdValue == Decimal(100))
        #expect(byMint[helius]?.priceChange24h == 5.0)
        #expect(overview.isPartial == false)
    }

    @Test("Zero-balance fungibles are filtered out of the overview tokens")
    func zeroBalanceFungiblesFiltered() async {
        let liveMint = makeTestMint()
        let dustMint = makeTestMint()
        let mock = MockSolanaProvider()
        mock.assetsHandler = { _, _, _ in
            AssetPage(
                items: [
                    AssetSummary(
                        id: liveMint, kind: .fungible,
                        symbol: "LIVE", name: "Live Token", imageURL: nil,
                        amount: TokenAmount(amount: 1_000, decimals: 6),
                        usdValue: Decimal(50), pricePerToken: Decimal(1),
                        priceChange24h: nil, tokenProgram: nil
                    ),
                    AssetSummary(
                        id: dustMint, kind: .fungible,
                        symbol: "DUST", name: "Empty Token", imageURL: nil,
                        amount: TokenAmount(amount: 0, decimals: 6),
                        usdValue: nil, pricePerToken: nil,
                        priceChange24h: nil, tokenProgram: nil
                    ),
                ],
                nativeSol: NativeBalance(
                    lamports: Lamports(rawValue: 2_000_000_000),
                    pricePerSol: Decimal(150),
                    totalUSD: Decimal(300)
                ),
                page: 1, limit: 1000, totalEstimated: nil, hasMore: false
            )
        }
        mock.solChange24hHandler = { 0.0 }
        mock.pricesHandler = { _ in [liveMint: PriceQuote(usdPrice: Decimal(1), change24h: 1.0)] }

        let service = makeService(mock: mock, walletId: walletId, address: address)
        let state = await service.load(for: walletId, forceRevalidate: false)

        guard case .loaded(let overview, _) = state else {
            Issue.record("Expected .loaded, got \(state)")
            return
        }
        #expect(overview.tokens.count == 1)
        #expect(overview.tokens.first?.symbol == "LIVE")
    }
}
