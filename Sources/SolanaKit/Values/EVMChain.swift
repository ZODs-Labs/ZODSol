import Foundation

/// A supported EVM chain and the per-vendor identifiers needed to price a token
/// on it. An EVM contract address does not encode its chain, so identity is
/// always the tuple `(chain, address)`; this type is the `chain` half.
///
/// The vendor id fields exist because each keyless price host names the same
/// chain differently (DexScreener `avalanche`, DefiLlama `avax`); passing one
/// vendor's slug to another silently returns empty results. `slug` is our own
/// stable internal key that the persisted `sourceIdentifier` is built from, so
/// the on-disk format never depends on a vendor's naming.
public struct EVMChain: Sendable, Hashable {
    public let slug: String
    public let displayName: String
    public let dexScreenerId: String
    public let defiLlamaId: String
    public let nativeSymbol: String

    public init(
        slug: String,
        displayName: String,
        dexScreenerId: String,
        defiLlamaId: String,
        nativeSymbol: String)
    {
        self.slug = slug
        self.displayName = displayName
        self.dexScreenerId = dexScreenerId
        self.defiLlamaId = defiLlamaId
        self.nativeSymbol = nativeSymbol
    }

    public static let ethereum = EVMChain(
        slug: "ethereum", displayName: "Ethereum",
        dexScreenerId: "ethereum", defiLlamaId: "ethereum", nativeSymbol: "ETH")
    public static let base = EVMChain(
        slug: "base", displayName: "Base",
        dexScreenerId: "base", defiLlamaId: "base", nativeSymbol: "ETH")
    public static let arbitrum = EVMChain(
        slug: "arbitrum", displayName: "Arbitrum",
        dexScreenerId: "arbitrum", defiLlamaId: "arbitrum", nativeSymbol: "ETH")
    public static let optimism = EVMChain(
        slug: "optimism", displayName: "Optimism",
        dexScreenerId: "optimism", defiLlamaId: "optimism", nativeSymbol: "ETH")
    public static let polygon = EVMChain(
        slug: "polygon", displayName: "Polygon",
        dexScreenerId: "polygon", defiLlamaId: "polygon", nativeSymbol: "POL")
    public static let bsc = EVMChain(
        slug: "bsc", displayName: "BNB Chain",
        dexScreenerId: "bsc", defiLlamaId: "bsc", nativeSymbol: "BNB")
    public static let avalanche = EVMChain(
        slug: "avalanche", displayName: "Avalanche",
        dexScreenerId: "avalanche", defiLlamaId: "avax", nativeSymbol: "AVAX")
    // Robinhood Chain: an Ethereum L2 (ETH gas, WETH-quoted DEX pairs). DefiLlama
    // does not index it yet, so the DefiLlama fallback returns nothing for it and
    // DexScreener carries the price; the placeholder id keeps it forward-safe.
    public static let robinhood = EVMChain(
        slug: "robinhood", displayName: "Robinhood",
        dexScreenerId: "robinhood", defiLlamaId: "robinhood", nativeSymbol: "ETH")

    /// The supported allow-list. Expanding it is pure data plus a completeness
    /// test row; the DexScreener id must be a chain DexScreener actually indexes.
    public static let supported: [EVMChain] = [
        .ethereum, .base, .arbitrum, .optimism, .polygon, .bsc, .avalanche, .robinhood,
    ]

    public static func supported(slug: String) -> EVMChain? {
        self.supported.first { $0.slug == slug }
    }

    public static func supported(dexScreenerId: String) -> EVMChain? {
        self.supported.first { $0.dexScreenerId == dexScreenerId }
    }
}
