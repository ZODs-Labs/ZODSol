import Foundation
import SolanaKit

/// The curated set of blue-chip assets the ticker offers out of the box, and
/// the symbol-to-identifier resolution that routes a chosen token to the right
/// price source. This is the single source of truth for blue-chip routing:
/// the Kraken pair code drives the refresh loop, the Coinbase product is the
/// fallback, and both are frozen onto a `TickerEntry` at add time.
public enum TickerCatalog {
    public struct BlueChip: Sendable, Equatable {
        public let symbol: String
        public let displayName: String
        public let krakenPair: String
        public let coinbaseProduct: String
    }

    /// Ordered so the picker and curated defaults have a stable order. Kraken
    /// uses legacy asset codes (XBT for Bitcoin, XDG for Dogecoin); the pair
    /// codes here are the response keys, so request key == response key.
    public static let blueChips: [BlueChip] = [
        BlueChip(symbol: "SOL", displayName: "Solana", krakenPair: "SOLUSD", coinbaseProduct: "SOL-USD"),
        BlueChip(symbol: "BTC", displayName: "Bitcoin", krakenPair: "XXBTZUSD", coinbaseProduct: "BTC-USD"),
        BlueChip(symbol: "ETH", displayName: "Ethereum", krakenPair: "XETHZUSD", coinbaseProduct: "ETH-USD"),
        BlueChip(symbol: "XRP", displayName: "XRP", krakenPair: "XXRPZUSD", coinbaseProduct: "XRP-USD"),
        BlueChip(symbol: "DOGE", displayName: "Dogecoin", krakenPair: "XDGUSD", coinbaseProduct: "DOGE-USD"),
    ]

    /// WSOL. A paste of this mint is steered to the curated SOL blue-chip, which
    /// prices off Kraken spot rather than the Jupiter WSOL proxy.
    public static let wrappedSolMint = "So11111111111111111111111111111111111111112"

    /// Pre-loaded when the widget is first enabled: SOL, BTC, ETH.
    public static var curatedDefaults: [TickerEntry] {
        ["SOL", "BTC", "ETH"].compactMap { self.blueChipEntry(symbol: $0) }
    }

    /// Resolves a curated blue-chip symbol to a Kraken-sourced entry, or `nil`
    /// when the symbol is not curated (the caller then routes a pasted mint to
    /// Jupiter instead of fabricating a CEX pair).
    public static func blueChipEntry(symbol: String) -> TickerEntry? {
        let key = symbol.uppercased()
        guard let chip = blueChips.first(where: { $0.symbol == key }) else { return nil }
        return TickerEntry(
            source: .kraken,
            sourceIdentifier: chip.krakenPair,
            symbol: chip.symbol,
            displayName: chip.displayName,
            displayDecimals: 2)
    }

    /// Builds an EVM-sourced entry for a resolved token. `sourceIdentifier`
    /// carries the `(chain, address)` identity so the refresh loop routes it
    /// back to the right chain. `displayDecimals` is unused by the significant
    /// figures ticker formatter but kept for parity with the other entry kinds.
    public static func evmEntry(_ token: EVMResolvedToken) -> TickerEntry {
        TickerEntry(
            source: .evmDex,
            sourceIdentifier: token.ref.sourceIdentifier,
            symbol: token.symbol,
            displayName: token.name,
            displayDecimals: 2,
            iconURL: token.iconURL)
    }

    /// Builds a Jupiter-sourced entry for an arbitrary Solana mint, with
    /// metadata resolved upstream (Jupiter token search or Helius DAS).
    public static func jupiterEntry(
        mint: String,
        symbol: String,
        displayName: String,
        displayDecimals: Int,
        iconURL: URL? = nil) -> TickerEntry
    {
        TickerEntry(
            source: .jupiter,
            sourceIdentifier: mint,
            symbol: symbol,
            displayName: displayName,
            displayDecimals: displayDecimals,
            iconURL: iconURL)
    }

    /// The Coinbase product for a Kraken pair code, for the fallback lookup the
    /// blue-chip client performs when a Kraken tick fails. The executable hands
    /// this map to the price provider so blue-chip routing stays defined here.
    public static func coinbaseProduct(forKrakenPair krakenPair: String) -> String? {
        self.blueChips.first { $0.krakenPair == krakenPair }?.coinbaseProduct
    }

    public static var krakenToCoinbaseProducts: [String: String] {
        Dictionary(uniqueKeysWithValues: self.blueChips.map { ($0.krakenPair, $0.coinbaseProduct) })
    }
}
