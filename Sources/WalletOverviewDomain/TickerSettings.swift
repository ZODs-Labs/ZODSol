import Foundation
import SolanaKit

/// How much of each token the menu-bar ticker renders per entry.
public enum TickerDisplayMode: String, Sendable, Codable, Equatable, CaseIterable {
    case priceOnly
    case symbolAndPrice
    case symbolPriceAndChange
}

/// One token the user has chosen for the menu-bar ticker. `source` and
/// `sourceIdentifier` are resolved once when the token is added and frozen, so
/// the refresh loop only ever overwrites price, never re-resolves identity.
/// `sourceIdentifier` is a Kraken pair code (e.g. `XXBTZUSD`) for blue-chips or
/// a Solana mint base58 for `jupiter` entries.
public struct TickerEntry: Sendable, Codable, Equatable, Identifiable {
    public let id: UUID
    public var source: TickerPriceSource
    public var sourceIdentifier: String
    public var symbol: String
    public var displayName: String
    public var displayDecimals: Int
    public var iconURL: URL?
    public var isEnabled: Bool

    public init(
        id: UUID = UUID(),
        source: TickerPriceSource,
        sourceIdentifier: String,
        symbol: String,
        displayName: String,
        displayDecimals: Int,
        iconURL: URL? = nil,
        isEnabled: Bool = true)
    {
        self.id = id
        self.source = source
        self.sourceIdentifier = sourceIdentifier
        self.symbol = symbol
        self.displayName = displayName
        self.displayDecimals = displayDecimals
        self.iconURL = iconURL
        self.isEnabled = isEnabled
    }
}

/// The persisted menu-bar ticker configuration. Defaults to disabled (opt-in)
/// with the curated blue-chip set pre-loaded, so flipping the master toggle on
/// shows SOL, BTC and ETH immediately.
public struct TickerSettings: Sendable, Codable, Equatable {
    public var isWidgetEnabled: Bool
    public var displayMode: TickerDisplayMode
    public var entries: [TickerEntry]

    public init(
        isWidgetEnabled: Bool,
        displayMode: TickerDisplayMode,
        entries: [TickerEntry])
    {
        self.isWidgetEnabled = isWidgetEnabled
        self.displayMode = displayMode
        self.entries = entries
    }

    public static var seeded: TickerSettings {
        TickerSettings(
            isWidgetEnabled: false,
            displayMode: .symbolAndPrice,
            entries: TickerCatalog.curatedDefaults)
    }
}
