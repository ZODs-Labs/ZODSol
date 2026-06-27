import Foundation
import SolanaKit

/// Freshness of a rendered ticker segment, driving how the menu bar paints it.
public enum TickerStaleness: Sendable, Equatable {
    /// Up to date (or a single dropped poll, which is treated as noise).
    case fresh
    /// Several consecutive failed refreshes: render dimmed, keep the last value.
    case stale
    /// No value, or a value too old to trust: render the no-data placeholder.
    case unavailable
}

/// One token's rendered state in the menu-bar ticker. `price` and `change24h`
/// are nil when `staleness` is `.unavailable`.
public struct TickerSegment: Sendable, Equatable, Identifiable {
    public let id: UUID
    public let symbol: String
    public let displayName: String
    public let iconURL: URL?
    public let price: Decimal?
    public let change24h: Double?
    public let staleness: TickerStaleness

    public init(
        id: UUID,
        symbol: String,
        displayName: String,
        iconURL: URL?,
        price: Decimal?,
        change24h: Double?,
        staleness: TickerStaleness)
    {
        self.id = id
        self.symbol = symbol
        self.displayName = displayName
        self.iconURL = iconURL
        self.price = price
        self.change24h = change24h
        self.staleness = staleness
    }
}

/// An immutable render model the presenter maps onto the status item. Ordered to
/// the user's selection.
public struct TickerSnapshot: Sendable, Equatable {
    public let segments: [TickerSegment]

    public init(segments: [TickerSegment]) {
        self.segments = segments
    }

    public static let empty = TickerSnapshot(segments: [])
}
