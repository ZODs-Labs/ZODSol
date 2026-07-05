import Foundation
import SolanaKit

/// Routes each ticker request to its frozen source: blue-chips (SOL, BTC, ETH)
/// to the keyless CEX client (Kraken, Coinbase fallback) for real spot, arbitrary
/// Solana mints to Jupiter, and arbitrary EVM tokens to the DexScreener/DefiLlama
/// client. The source fetches run concurrently and merge into one
/// keyed-by-identifier outcome, so the engine stays source-agnostic. Any source
/// that rate-limits or errors sets the shared backoff signal.
public struct LayeredTickerPriceProvider: TickerQuoteProviding {
    private let blueChip: BlueChipPriceClient
    private let jupiter: JupiterClient
    private let evmDex: EVMDexPriceClient
    private let krakenToCoinbaseProducts: [String: String]

    public init(session: URLSession, krakenToCoinbaseProducts: [String: String]) {
        self.blueChip = BlueChipPriceClient(session: session)
        self.jupiter = JupiterClient(session: session)
        self.evmDex = EVMDexPriceClient(session: session)
        self.krakenToCoinbaseProducts = krakenToCoinbaseProducts
    }

    public func quotes(for requests: [TickerQuoteRequest]) async -> TickerFetchOutcome {
        let krakenPairs = requests.filter { $0.source == .kraken }.map(\.identifier)
        let jupiterMints = requests.filter { $0.source == .jupiter }.map(\.identifier)
        let evmRefs = requests
            .filter { $0.source == .evmDex }
            .compactMap { EVMTokenRef(sourceIdentifier: $0.identifier) }

        async let krakenOutcome = self.blueChipOutcome(pairs: krakenPairs)
        async let jupiterOutcome = self.jupiterOutcome(mints: jupiterMints)
        async let evmOutcome = self.evmDex.quotes(for: evmRefs)
        let (kraken, jupiterResult, evm) = await (krakenOutcome, jupiterOutcome, evmOutcome)

        var quotes = kraken.quotes
        quotes.merge(jupiterResult.quotes) { _, new in new }
        quotes.merge(evm.quotes) { _, new in new }
        let retryAfter = [kraken.retryAfter, jupiterResult.retryAfter, evm.retryAfter].compactMap(\.self).max()
        return TickerFetchOutcome(
            quotes: quotes,
            retryAfter: retryAfter,
            shouldBackOff: kraken.shouldBackOff || jupiterResult.shouldBackOff || evm.shouldBackOff)
    }

    private func blueChipOutcome(pairs: [String]) async -> TickerFetchOutcome {
        guard !pairs.isEmpty else { return .empty }
        let primary = await self.blueChip.fetchKraken(pairs: pairs)
        let missing = pairs.filter { primary.quotes[$0] == nil }
        guard !missing.isEmpty else { return primary }
        let products = missing.reduce(into: [String: String]()) { accumulator, pair in
            if let product = self.krakenToCoinbaseProducts[pair] { accumulator[pair] = product }
        }
        guard !products.isEmpty else { return primary }
        let fallback = await self.blueChip.fetchCoinbase(products: products)
        var quotes = primary.quotes
        quotes.merge(fallback.quotes) { _, new in new }
        return TickerFetchOutcome(quotes: quotes, retryAfter: primary.retryAfter, shouldBackOff: primary.shouldBackOff)
    }

    private func jupiterOutcome(mints: [String]) async -> TickerFetchOutcome {
        guard !mints.isEmpty else { return .empty }
        guard let response = await self.jupiter.fetchPrices(mints: mints) else {
            return TickerFetchOutcome(quotes: [:], retryAfter: nil, shouldBackOff: true)
        }
        var quotes: [String: PriceQuote] = [:]
        for (mint, entry) in response.entries {
            guard entry.usdPrice != nil || entry.priceChange24h != nil else { continue }
            quotes[mint] = PriceQuote(usdPrice: entry.usdPrice, change24h: entry.priceChange24h)
        }
        return TickerFetchOutcome(quotes: quotes, retryAfter: nil, shouldBackOff: false)
    }
}
