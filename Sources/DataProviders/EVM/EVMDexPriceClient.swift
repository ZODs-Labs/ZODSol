import Foundation
import SolanaKit

/// The EVM refresh adapter. Prices every tracked EVM token via DexScreener
/// chain-scoped batches (one call per chain, deepest pool per token), then falls
/// back to DefiLlama for any token DexScreener returned empty for. Quotes are
/// keyed by the full `sourceIdentifier` so the engine matches them to entries.
actor EVMDexPriceClient {
    private let dexScreener: DexScreenerClient
    private let defiLlama: DefiLlamaClient

    init(session: URLSession) {
        self.dexScreener = DexScreenerClient(session: session)
        self.defiLlama = DefiLlamaClient(session: session)
    }

    func quotes(for refs: [EVMTokenRef]) async -> TickerFetchOutcome {
        guard !refs.isEmpty else { return .empty }
        var quotes: [String: PriceQuote] = [:]
        var shouldBackOff = false
        var retryAfter: Duration?

        for (chain, chainRefs) in Dictionary(grouping: refs, by: { $0.chain }) {
            let batch = await self.dexScreener.tokenPairs(
                chainId: chain.dexScreenerId,
                addresses: chainRefs.map(\.address))
            if batch.shouldBackOff {
                shouldBackOff = true
                retryAfter = retryAfter ?? batch.retryAfter
            }
            for ref in chainRefs {
                let matching = DexScreenerPairMath.matching(batch.pairs, address: ref.address)
                if let deepest = DexScreenerPairMath.deepestPool(matching),
                   let quote = DexScreenerPairMath.quote(deepest)
                {
                    quotes[ref.sourceIdentifier] = quote
                }
            }
        }

        let missing = refs.filter { quotes[$0.sourceIdentifier] == nil }
        if !missing.isEmpty {
            for (identifier, quote) in await self.defiLlama.prices(refs: missing) {
                quotes[identifier] = quote
            }
        }

        return TickerFetchOutcome(quotes: quotes, retryAfter: retryAfter, shouldBackOff: shouldBackOff)
    }
}
