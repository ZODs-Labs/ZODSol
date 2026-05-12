import Foundation

/// Formats integer counts compactly using Phantom-style capital suffixes:
/// `K` (one fraction digit), `M` and `B` (two fraction digits). Values under 1,000
/// fall back to a full digit representation with locale-aware grouping.
public struct CompactNumberFormatter: Sendable {
    public let locale: Locale

    public init(locale: Locale = .current) {
        self.locale = locale
    }

    /// Returns a compact representation of `integer`. Negative values are prefixed with
    /// the U+2212 minus glyph.
    public func string(_ integer: Int) -> String {
        let absN = abs(integer)
        let sign = integer < 0 ? "\u{2212}" : ""

        if absN >= 1_000_000_000 {
            return self.fmt(Double(absN) / 1_000_000_000, fractionDigits: 2, sign: sign, suffix: "B")
        }
        if absN >= 1_000_000 {
            return self.fmt(Double(absN) / 1_000_000, fractionDigits: 2, sign: sign, suffix: "M")
        }
        if absN >= 1000 {
            return self.fmt(Double(absN) / 1000, fractionDigits: 1, sign: sign, suffix: "K")
        }

        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.locale = self.locale
        formatter.usesGroupingSeparator = true
        let body = formatter.string(from: NSNumber(value: absN)) ?? "\(absN)"
        return "\(sign)\(body)"
    }

    private func fmt(_ value: Double, fractionDigits: Int, sign: String, suffix: String) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.locale = self.locale
        formatter.minimumFractionDigits = fractionDigits
        formatter.maximumFractionDigits = fractionDigits
        let body = formatter.string(from: NSNumber(value: value))
            ?? String(format: "%.\(fractionDigits)f", value)
        return "\(sign)\(body)\(suffix)"
    }
}
