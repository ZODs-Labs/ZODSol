import Formatters
import Foundation
import WalletOverviewDomain

/// One token as the menu bar should paint it: pre-formatted strings plus a tint
/// and dim flag. AppKit-free so the mapping is testable; the status item turns
/// this into an `NSAttributedString`.
public struct TickerRenderSegment: Sendable, Equatable, Identifiable {
    public let id: UUID
    public let symbol: String?
    public let priceText: String
    public let changeText: String?
    public let tint: PercentageDeltaFormatter.DeltaColor
    public let isDimmed: Bool

    public init(
        id: UUID,
        symbol: String?,
        priceText: String,
        changeText: String?,
        tint: PercentageDeltaFormatter.DeltaColor,
        isDimmed: Bool)
    {
        self.id = id
        self.symbol = symbol
        self.priceText = priceText
        self.changeText = changeText
        self.tint = tint
        self.isDimmed = isDimmed
    }
}

/// What the status item should show: the brand icon (`hidden`) or the ticker.
public enum TickerRenderModel: Sendable, Equatable {
    case hidden
    case ticker([TickerRenderSegment])

    /// Maps a snapshot to render segments under the given display mode. Returns
    /// `.hidden` (show the ZODs icon) when the widget is disabled.
    public static func build(
        snapshot: TickerSnapshot,
        displayMode: TickerDisplayMode,
        isEnabled: Bool,
        priceFormatter: TickerPriceFormatter = TickerPriceFormatter(locale: Locale(identifier: "en_US")),
        deltaFormatter: PercentageDeltaFormatter = PercentageDeltaFormatter(locale: Locale(identifier: "en_US")))
        -> TickerRenderModel
    {
        guard isEnabled else { return .hidden }
        let segments = snapshot.segments.map { segment -> TickerRenderSegment in
            let symbol = displayMode == .priceOnly ? nil : segment.symbol
            let priceText = priceFormatter.string(segment.price)
            var changeText: String?
            var tint: PercentageDeltaFormatter.DeltaColor = .neutral
            if displayMode == .symbolPriceAndChange,
               segment.staleness != .unavailable,
               let change = segment.change24h
            {
                changeText = deltaFormatter.string(change)
                tint = deltaFormatter.color(for: change)
            }
            return TickerRenderSegment(
                id: segment.id,
                symbol: symbol,
                priceText: priceText,
                changeText: changeText,
                tint: tint,
                isDimmed: segment.staleness == .stale)
        }
        return .ticker(segments)
    }
}
