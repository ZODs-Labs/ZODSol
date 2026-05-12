import Foundation

public struct CurrencyFormatter: Sendable {
    public let locale: Locale

    public init(locale: Locale = .current) {
        self.locale = locale
    }

    public func string(usd: Decimal) -> String {
        let f = NumberFormatter()
        f.numberStyle = .currency
        f.currencyCode = "USD"
        f.locale = self.locale
        f.minimumFractionDigits = 2
        f.maximumFractionDigits = 2
        f.usesGroupingSeparator = true
        let result = f.string(from: usd as NSDecimalNumber) ?? "\(usd)"
        if usd < 0 {
            return result.replacingOccurrences(of: "-", with: "\u{2212}")
        }
        return result
    }

    public func compact(usd: Decimal) -> String {
        let absValue = abs(usd)
        let isNegative = usd < 0
        let sign = isNegative ? "\u{2212}" : ""

        func format(_ v: Decimal, fraction: Int, suffix: String) -> String {
            let f = NumberFormatter()
            f.numberStyle = .currency
            f.currencyCode = "USD"
            f.locale = self.locale
            f.minimumFractionDigits = fraction
            f.maximumFractionDigits = fraction
            f.usesGroupingSeparator = true
            let base = f.string(from: v as NSDecimalNumber) ?? "\(v)"
            return "\(sign)\(base)\(suffix)"
        }

        if absValue >= 1_000_000_000 {
            return format(absValue / 1_000_000_000, fraction: 2, suffix: "B")
        }
        if absValue >= 1_000_000 {
            return format(absValue / 1_000_000, fraction: 2, suffix: "M")
        }
        if absValue >= 10000 {
            return format(absValue / 1000, fraction: 2, suffix: "K")
        }
        if isNegative {
            return "\u{2212}\(self.string(usd: absValue))"
        }
        return self.string(usd: usd)
    }

    /// Portfolio-row USD value. Sub-$1K renders as canonical two-decimal currency
    /// so 99¢ and $164.50 always show the same shape; ≥$1K compacts to K/M/B.
    public func displayValue(usd: Decimal) -> String {
        let absValue = abs(usd)
        let isNegative = usd < 0
        let sign = isNegative ? "\u{2212}" : ""

        func format(_ v: Decimal, fraction: Int, suffix: String) -> String {
            let f = NumberFormatter()
            f.numberStyle = .currency
            f.currencyCode = "USD"
            f.locale = self.locale
            f.minimumFractionDigits = 0
            f.maximumFractionDigits = fraction
            f.usesGroupingSeparator = true
            let base = f.string(from: v as NSDecimalNumber) ?? "\(v)"
            return "\(sign)\(base)\(suffix)"
        }

        if absValue >= 1_000_000_000 {
            return format(absValue / 1_000_000_000, fraction: 2, suffix: "B")
        }
        if absValue >= 1_000_000 {
            return format(absValue / 1_000_000, fraction: 2, suffix: "M")
        }
        if absValue >= 1000 {
            return format(absValue / 1000, fraction: 2, suffix: "K")
        }
        return isNegative ? "\u{2212}\(self.string(usd: absValue))" : self.string(usd: usd)
    }

    /// Per-token spot price. Below 1¢ collapses to `<$0.01` (no scientific notation,
    /// no long decimal tails); 1¢–$1 keeps up to 4 fraction digits; ≥$1 uses the
    /// standard two-decimal currency shape.
    public func priceUSD(_ price: Decimal) -> String {
        if price == 0 { return "$0" }
        let absValue = abs(price)
        let isNegative = price < 0
        let threshold = Decimal(string: "0.01")!

        if absValue < threshold {
            return isNegative ? "\u{2212}<$0.01" : "<$0.01"
        }

        let f = NumberFormatter()
        f.numberStyle = .currency
        f.currencyCode = "USD"
        f.locale = self.locale
        f.usesGroupingSeparator = true
        if absValue >= 1 {
            f.minimumFractionDigits = 2
            f.maximumFractionDigits = 2
        } else {
            f.minimumFractionDigits = 2
            f.maximumFractionDigits = 4
        }
        let result = f.string(from: price as NSDecimalNumber) ?? "\(price)"
        return isNegative ? result.replacingOccurrences(of: "-", with: "\u{2212}") : result
    }
}
