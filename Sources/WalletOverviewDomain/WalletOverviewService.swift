import Foundation
import SolanaKit
import Caching

public protocol WalletOverviewService: Sendable {
    func load(for walletId: UUID, forceRevalidate: Bool) async -> LoadState<WalletOverview>
    func stream(for walletId: UUID, tick: Duration) -> AsyncStream<LoadState<WalletOverview>>
    func invalidate(walletId: UUID) async
    func invalidateAll() async
}

public actor DefaultWalletOverviewService: WalletOverviewService {
    private let provider: any SolanaProvider
    private let addressLookup: @Sendable (UUID) async throws -> WalletAddress
    private let network: SolanaNetwork
    private let overviewCache: TimedCache<UUID, WalletOverview>

    public init(
        provider: any SolanaProvider,
        walletStore: WalletStore,
        network: SolanaNetwork = .mainnet,
        overviewCache: TimedCache<UUID, WalletOverview>
    ) {
        self.provider = provider
        self.addressLookup = { id in try await walletStore.address(for: id) }
        self.network = network
        self.overviewCache = overviewCache
    }

    internal init(
        provider: any SolanaProvider,
        addressLookup: @Sendable @escaping (UUID) async throws -> WalletAddress,
        network: SolanaNetwork = .mainnet,
        overviewCache: TimedCache<UUID, WalletOverview>
    ) {
        self.provider = provider
        self.addressLookup = addressLookup
        self.network = network
        self.overviewCache = overviewCache
    }

    public func load(for walletId: UUID, forceRevalidate: Bool) async -> LoadState<WalletOverview> {
        let address: WalletAddress
        do { address = try await addressLookup(walletId) } catch { return .idle }

        if !forceRevalidate {
            switch await overviewCache.read(walletId) {
            case .fresh(let v): return .loaded(v, lastRefreshed: Date())
            case .stale, .miss: break
            }
        }

        do {
            let overview = try await fetchOverview(walletId: walletId, address: address)
            await overviewCache.write(overview, for: walletId)
            if overview.isPartial {
                return .partial(overview, error: .providerUnavailable("partial"))
            }
            return .loaded(overview, lastRefreshed: Date())
        } catch let e as WalletOverviewError {
            if case .stale(let cached) = await overviewCache.read(walletId) {
                return .partial(cached, error: e)
            }
            return .failed(e)
        } catch let e as SolanaProviderError {
            let mapped = mapProviderError(e)
            if case .stale(let cached) = await overviewCache.read(walletId) {
                return .partial(cached, error: mapped)
            }
            return .failed(mapped)
        } catch is CancellationError {
            return .failed(.canceled)
        } catch {
            return .failed(.unknown(String(describing: error)))
        }
    }

    public nonisolated func stream(for walletId: UUID, tick: Duration) -> AsyncStream<LoadState<WalletOverview>> {
        AsyncStream { continuation in
            let task = Task { [weak self] in
                while !Task.isCancelled {
                    guard let self else { return }
                    let state = await self.load(for: walletId, forceRevalidate: true)
                    continuation.yield(state)
                    try? await Task.sleep(for: tick)
                }
                continuation.finish()
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    public func invalidate(walletId: UUID) async {
        await overviewCache.invalidate(walletId)
    }

    public func invalidateAll() async {
        await overviewCache.invalidateAll()
    }

    // MARK: - Private

    private func fetchOverview(walletId: UUID, address: WalletAddress) async throws -> WalletOverview {
        async let assetsTask = provider.assets(for: address, network: network, options: .default)
        async let solChangeTask = safeSolChange()

        let page: AssetPage
        do {
            page = try await assetsTask
        } catch is CancellationError {
            throw WalletOverviewError.canceled
        } catch let e as SolanaProviderError {
            throw mapProviderError(e)
        }

        let solChange = await solChangeTask

        let fungibleMints = page.items.compactMap { $0.kind == .fungible ? $0.id : nil }
        let quotes: [Mint: PriceQuote] = (try? await provider.prices(for: fungibleMints)) ?? [:]

        return assemble(walletId: walletId, address: address, page: page, solChange: solChange, quotes: quotes)
    }

    private func safeSolChange() async -> Double? {
        try? await provider.solChange24h()
    }

    private func assemble(
        walletId: UUID,
        address: WalletAddress,
        page: AssetPage,
        solChange: Double?,
        quotes: [Mint: PriceQuote]
    ) -> WalletOverview {
        let merged: [AssetSummary] = page.items.map { item in
            guard item.kind == .fungible, let quote = quotes[item.id] else { return item }
            // Trust Helius DAS pricing when present (its index covers the major
            // listings consistently). Fall back to Jupiter for the long tail
            // (pump.fun mints and other tokens Helius does not index).
            let pricePerToken = item.pricePerToken ?? quote.usdPrice
            let usdValue: Decimal? = {
                if let existing = item.usdValue { return existing }
                guard let price = quote.usdPrice else { return nil }
                return price * item.amount.uiAmount
            }()
            return AssetSummary(
                id: item.id, kind: item.kind, symbol: item.symbol, name: item.name,
                imageURL: item.imageURL, amount: item.amount,
                usdValue: usdValue, pricePerToken: pricePerToken,
                priceChange24h: quote.change24h, tokenProgram: item.tokenProgram
            )
        }

        let fungibles = merged
            .filter { $0.kind == .fungible && $0.amount.amount > 0 }
            .sorted { a, b in
                switch (a.usdValue, b.usdValue) {
                case let (l?, r?): return l > r
                case (nil, _): return false
                case (_, nil): return true
                default: return false
                }
            }

        let nfts = merged.filter { $0.kind == .nft || $0.kind == .compressedNft }
        let nftSummary = NFTSummary(
            count: nfts.count,
            collectionPreviews: Array(nfts.compactMap(\.imageURL).prefix(6))
        )

        let solBalance: Lamports = page.nativeSol?.lamports ?? Lamports(rawValue: 0)
        let solPriceUSD: Decimal? = page.nativeSol?.pricePerSol
        let solTotalUSD: Decimal? = page.nativeSol?.totalUSD

        let fungibleTotal: Decimal = fungibles.compactMap(\.usdValue).reduce(Decimal(0), +)
        let totalUSD: Decimal? = solTotalUSD.map { $0 + fungibleTotal }

        let allPricesPresent = fungibles.allSatisfy { $0.usdValue != nil }
        let isPartial = (!fungibles.isEmpty && (quotes.isEmpty || !allPricesPresent))
            || (solChange == nil && page.nativeSol != nil)

        let totalChange24h: Double? = {
            var weightedSum: Double = 0
            var weightTotal: Double = 0
            for f in fungibles {
                guard let usd = f.usdValue, let change = f.priceChange24h else { continue }
                let w = NSDecimalNumber(decimal: usd).doubleValue
                weightedSum += w * change
                weightTotal += w
            }
            if let solUSD = solTotalUSD, let solCh = solChange {
                let w = NSDecimalNumber(decimal: solUSD).doubleValue
                weightedSum += w * solCh
                weightTotal += w
            }
            return weightTotal > 0 ? weightedSum / weightTotal : nil
        }()

        return WalletOverview(
            walletId: walletId, address: address,
            solBalance: solBalance, solPriceUSD: solPriceUSD, solChange24h: solChange,
            tokens: fungibles,
            nfts: nftSummary,
            totalUSD: totalUSD, totalChange24h: totalChange24h,
            asOf: Date(), isPartial: isPartial
        )
    }

    private nonisolated func mapProviderError(_ e: SolanaProviderError) -> WalletOverviewError {
        switch e {
        case .networkUnavailable: return .networkUnavailable
        case .rateLimited(let r): return .rateLimited(retryAfter: r)
        case .unauthorized: return .unauthorized
        case .providerUnavailable(message: let m): return .providerUnavailable(m)
        case .malformedResponse(let m): return .malformedResponse(m)
        case .invalidInput(let m): return .malformedResponse(m)
        case .canceled: return .canceled
        }
    }
}
