import Foundation

/// Menu-bar spot-price formatting for the price ticker.
///
/// `CurrencyFormatter.priceUSD` collapses everything below one cent to `<$0.01`,
/// so every sub-cent token renders identically. This formatter keeps significant
/// figures instead, so distinct memecoin prices stay distinguishable, and bounds
/// width for deep-sub-cent values with DexScreener-style subscript-zero notation
/// (`$0.0₅1234` == `0.000001234`, the subscript being the count of leading zeros).
///
/// All rounding is done off `Decimal` via `NumberFormatter` fraction-digit
/// rounding or exact decimal scaling; the significant-digit path never
/// round-trips through `Double`, which would reintroduce binary float error
/// precisely in the many-decimal range this type exists to render.
public struct TickerPriceFormatter: Sendable {
    public let locale: Locale

    /// Rendered when a price is absent or non-positive (thin or missing
    /// liquidity is never shown as `$0.00`). Matches `PercentageDeltaFormatter`.
    public static let noData = "\u{2014}"

    private static let significantDigits = 4

    public init(locale: Locale = .current) {
        self.locale = locale
    }

    /// Returns the menu-bar price string, or `noData` for nil / non-positive prices.
    /// At or above $500 the fraction is dropped (`$60,325`) to keep the bar
    /// compact; below that two decimals are kept (`$72.08`).
    public func string(_ price: Decimal?) -> String {
        guard let price, price > 0 else { return Self.noData }
        if price >= 500 {
            return self.fixed(price, fractionDigits: 0)
        }
        if price >= 1 {
            return self.fixed(price, fractionDigits: 2)
        }
        let oneCent = Decimal(string: "0.01")!
        if price >= oneCent {
            return self.fixed(price, fractionDigits: 4)
        }
        return self.subscriptForm(price)
    }

    private func fixed(_ price: Decimal, fractionDigits: Int) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.currencyCode = "USD"
        formatter.locale = self.locale
        formatter.usesGroupingSeparator = true
        formatter.minimumFractionDigits = fractionDigits
        formatter.maximumFractionDigits = fractionDigits
        return formatter.string(from: price as NSDecimalNumber) ?? "\(price)"
    }

    /// price is in (0, 0.01). Renders currencySymbol + "0" + separator + "0" +
    /// subscript(leadingZeros) + significantDigits, e.g. "$0.0₅1234".
    private func subscriptForm(_ price: Decimal) -> String {
        let zeros = Self.leadingZeros(price)
        let digits = Self.significand(price, leadingZeros: zeros, count: Self.significantDigits)
        // Rounding the significant digits can carry past the bucket
        // (0.00999996 rounds to 0.0100); fall back to the fixed renderer, which
        // shows the rounded value honestly rather than a wrong subscript count.
        if digits.count > Self.significantDigits {
            return self.fixed(price, fractionDigits: 4)
        }
        let symbols = self.currencySymbols()
        return "\(symbols.symbol)0\(symbols.separator)0\(Self.subscriptDigits(zeros))\(digits)"
    }

    private func currencySymbols() -> (symbol: String, separator: String) {
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.currencyCode = "USD"
        formatter.locale = self.locale
        return (formatter.currencySymbol ?? "$", formatter.currencyDecimalSeparator ?? ".")
    }

    // Zeros immediately after the decimal point before the first significant
    // digit: 0.4 -> 0, 0.04 -> 1, 0.001234 -> 2. Caller guarantees 0 < value < 1.
    private static func leadingZeros(_ value: Decimal) -> Int {
        var count = 0
        var remaining = value
        let tenth = Decimal(string: "0.1")!
        while remaining < tenth {
            remaining *= 10
            count += 1
        }
        return count
    }

    /// The first `count` significant digits, computed exactly off `Decimal`:
    /// scale up by a power of ten past the leading zeros, then round to integer.
    private static func significand(_ value: Decimal, leadingZeros: Int, count: Int) -> String {
        let scaled = value * self.power10(leadingZeros + count)
        let handler = NSDecimalNumberHandler(
            roundingMode: .plain,
            scale: 0,
            raiseOnExactness: false,
            raiseOnOverflow: false,
            raiseOnUnderflow: false,
            raiseOnDivideByZero: false)
        return NSDecimalNumber(decimal: scaled).rounding(accordingToBehavior: handler).stringValue
    }

    private static func power10(_ exponent: Int) -> Decimal {
        var result = Decimal(1)
        for _ in 0..<Swift.max(0, exponent) {
            result *= 10
        }
        return result
    }

    private static func subscriptDigits(_ number: Int) -> String {
        let glyphs: [Character] = [
            "\u{2080}", "\u{2081}", "\u{2082}", "\u{2083}", "\u{2084}",
            "\u{2085}", "\u{2086}", "\u{2087}", "\u{2088}", "\u{2089}",
        ]
        return String(String(number).compactMap { character in
            character.wholeNumberValue.map { glyphs[$0] }
        })
    }
}
