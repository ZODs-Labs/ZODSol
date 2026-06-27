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
        formatter.locale = self.locale
        formatter.minimumFractionDigits = 2
        formatter.maximumFractionDigits = 2
        let absFormatted = formatter.string(from: NSNumber(value: abs(delta)))
            ?? String(format: "%.2f", abs(delta))
        if delta > 0 { return "+\(absFormatted)%" }
        return "\u{2212}\(absFormatted)%"
    }

    /// Unsigned portfolio-share rendering. Drops the `+`/`−` glyphs because share is
    /// inherently non-negative. Uses two fraction digits at ≤100%, none above to keep
    /// the column readable when one position dominates the wallet.
    public func share(_ percent: Double) -> String {
        guard percent.isFinite else { return "—" }
        let abs = Swift.abs(percent)
        let digits = abs > 100 ? 0 : 2
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.locale = self.locale
        formatter.minimumFractionDigits = digits
        formatter.maximumFractionDigits = digits
        let body = formatter.string(from: NSNumber(value: abs))
            ?? String(format: "%.\(digits)f", abs)
        return "\(body)%"
    }

    /// Maps a delta to a semantic color hint for UI consumers.
    public func color(for delta: Double) -> DeltaColor {
        if delta > 0 { return .up }
        if delta < 0 { return .down }
        return .neutral
    }

    public enum DeltaColor: Sendable, Equatable {
        case up
        case down
        case neutral
    }
}
