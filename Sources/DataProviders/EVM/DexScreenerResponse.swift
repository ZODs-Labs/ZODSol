import Foundation
import SolanaKit

/// One DexScreener trading pair. Every price/liquidity field is nullable per the
/// documented schema, so a pair may be present with no usable price.
struct DexScreenerPair: Decodable {
    let chainId: String
    let baseToken: DexScreenerToken
    let priceUsd: String?
    let liquidity: DexScreenerLiquidity?
    let priceChange: DexScreenerPriceChange?
    let info: DexScreenerInfo?
}

struct DexScreenerToken: Decodable {
    let address: String
    let name: String?
    let symbol: String?
}

struct DexScreenerLiquidity: Decodable {
    let usd: Double?
}

struct DexScreenerPriceChange: Decodable {
    let h24: Double?
}

struct DexScreenerInfo: Decodable {
    let imageUrl: String?
}

/// `/latest/dex/search` wraps its results; `/tokens/v1/...` returns a bare array.
struct DexScreenerSearchResponse: Decodable {
    let pairs: [DexScreenerPair]?
}

/// Pure pair arithmetic shared by the resolver (add-time) and the price client
/// (refresh), so canonical-price rules live in exactly one place.
enum DexScreenerPairMath {
    /// Pairs where the queried address is the BASE token, case-insensitive. A
    /// token can appear as a quote token in unrelated pairs, so this filter is
    /// mandatory before trusting anything.
    static func matching(_ pairs: [DexScreenerPair], address: String) -> [DexScreenerPair] {
        let target = address.lowercased()
        return pairs.filter { $0.baseToken.address.lowercased() == target }
    }

    static func liquidityUSD(_ pair: DexScreenerPair) -> Double {
        pair.liquidity?.usd ?? 0
    }

    static func totalLiquidity(_ pairs: [DexScreenerPair]) -> Decimal {
        pairs.reduce(Decimal(0)) { $0 + Decimal(Self.liquidityUSD($1)) }
    }

    /// The deepest pool by USD liquidity: the canonical reference for price.
    static func deepestPool(_ pairs: [DexScreenerPair]) -> DexScreenerPair? {
        pairs.max { Self.liquidityUSD($0) < Self.liquidityUSD($1) }
    }

    /// A quote from a pair, or nil when the price is missing or non-positive.
    /// `priceUsd` is a decimal string parsed locale-independently on ".", so the
    /// value never round-trips through `Double` and its precision is preserved.
    static func quote(_ pair: DexScreenerPair) -> PriceQuote? {
        guard let priceString = pair.priceUsd,
              let price = Decimal(string: priceString), price > 0
        else {
            return nil
        }
        let change = pair.priceChange?.h24.flatMap { $0.isFinite ? $0 : nil }
        return PriceQuote(usdPrice: price, change24h: change)
    }
}
