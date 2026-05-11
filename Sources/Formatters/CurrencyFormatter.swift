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
        f.locale = locale
        f.minimumFractionDigits = 2
        f.maximumFractionDigits = 2
        f.usesGroupingSeparator = true
        let result = f.string(from: usd as NSDecimalNumber) ?? "\(usd)"
        if usd < 0 {
            let cleaned = result.replacingOccurrences(of: "-", with: "\u{2212}")
            return cleaned
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
            f.locale = locale
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
        if absValue >= 10_000 {
            return format(absValue / 1_000, fraction: 2, suffix: "K")
        }
        if isNegative {
            return "\u{2212}\(string(usd: absValue))"
        }
        return string(usd: usd)
    }
}
