import Foundation

/// Formats percentage deltas (e.g. price change) with explicit sign glyph and locale-aware
/// decimal separator. The plus sign and the minus glyph (U+2212) are baked in so that
/// negative values render as `−4.56%` rather than `-4.56%`.
public struct PercentageDeltaFormatter: Sendable {
    public let locale: Locale

    public init(locale: Locale = .current) {
        self.locale = locale
    }

    /// Returns a string like `"+1.23%"`, `"−4.56%"` (U+2212 minus glyph), or `"0.00%"`.
    /// Always uses two fraction digits and the locale's decimal separator.
    public func string(_ delta: Double) -> String {
        if delta == 0.0 { return "0.00%" }
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.locale = locale
        formatter.minimumFractionDigits = 2
        formatter.maximumFractionDigits = 2
        let absFormatted = formatter.string(from: NSNumber(value: abs(delta)))
            ?? String(format: "%.2f", abs(delta))
        if delta > 0 { return "+\(absFormatted)%" }
        return "\u{2212}\(absFormatted)%"
    }

    /// Maps a delta to a semantic color hint for UI consumers.
    public func color(for delta: Double) -> DeltaColor {
        if delta > 0 { return .up }
        if delta < 0 { return .down }
        return .neutral
    }

    public enum DeltaColor: Sendable {
        case up
        case down
        case neutral
    }
}
