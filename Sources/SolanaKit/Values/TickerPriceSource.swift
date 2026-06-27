import Foundation

/// Which keyless price backend a menu-bar ticker entry is quoted from.
///
/// Blue-chip assets (SOL, BTC, ETH and other major CEX-listed coins) are quoted
/// from a real cross-chain CEX (`kraken`, with `coinbase` as fallback) because
/// Jupiter can only price them as bridged-Solana proxies. Arbitrary Solana
/// mints are quoted from `jupiter`. The source is resolved once when a token is
/// added and frozen onto the entry; the refresh loop never re-derives it.
public enum TickerPriceSource: String, Sendable, Codable, Hashable, CaseIterable {
    case kraken
    case coinbase
    case jupiter
}
