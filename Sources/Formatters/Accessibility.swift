import Foundation
import SolanaKit

// MARK: - CurrencyFormatter

extension CurrencyFormatter {
    /// VoiceOver-friendly description such as
    /// `"one thousand two hundred thirty-four dollars and fifty-six cents"`.
    /// Uses `en_US` spell-out regardless of `self.locale` because VoiceOver labels
    /// in this app are English-only.
    public func accessibilityDescription(usd: Decimal) -> String {
        let isNegative = usd < 0
        let absUSD = isNegative ? -usd : usd
        let dollarsDecimal = absUSD.wholePart
        let centsDecimal = ((absUSD - dollarsDecimal) * 100).rounded(scale: 0)

        let dollars = (dollarsDecimal as NSDecimalNumber).intValue
        let cents = (centsDecimal as NSDecimalNumber).intValue

        let speller = NumberFormatter()
        speller.numberStyle = .spellOut
        speller.locale = Locale(identifier: "en_US")

        let dollarsStr = speller.string(from: NSNumber(value: dollars)) ?? "\(dollars)"
        let centsStr = speller.string(from: NSNumber(value: cents)) ?? "\(cents)"
        let neg = isNegative ? "negative " : ""
        let dollarWord = dollars == 1 ? "dollar" : "dollars"

        if cents == 0 {
            return "\(neg)\(dollarsStr) \(dollarWord)"
        }
        let centWord = cents == 1 ? "cent" : "cents"
        return "\(neg)\(dollarsStr) \(dollarWord) and \(centsStr) \(centWord)"
    }
}

// MARK: - TokenAmountFormatter

extension TokenAmountFormatter {
    /// VoiceOver-friendly token-amount description: full precision, no abbreviation,
    /// no subscript-zero notation. Uses `en_US_POSIX` to produce a raw decimal string
    /// that VoiceOver can read digit-by-digit.
    public func accessibilityDescription(_ amount: TokenAmount, symbol: String?) -> String {
        let ui = amount.uiAmount
        let raw = (ui as NSDecimalNumber).description(withLocale: Locale(identifier: "en_US_POSIX"))
        let suffix = if let symbol, !symbol.isEmpty {
            " \(symbol)"
        } else {
            ""
        }
        return "\(raw)\(suffix)"
    }
}

// MARK: - PercentageDeltaFormatter

extension PercentageDeltaFormatter {
    /// VoiceOver-friendly description such as `"Up 1.23 percent"`, `"Down 4.56 percent"`,
    /// or `"Unchanged"`.
    public func accessibilityDescription(_ delta: Double) -> String {
        if delta == 0.0 { return "Unchanged" }
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.locale = locale
        formatter.minimumFractionDigits = 2
        formatter.maximumFractionDigits = 2
        let absStr = formatter.string(from: NSNumber(value: Swift.abs(delta)))
            ?? String(format: "%.2f", Swift.abs(delta))
        if delta > 0 { return "Up \(absStr) percent" }
        return "Down \(absStr) percent"
    }
}

// MARK: - CompactNumberFormatter

extension CompactNumberFormatter {
    /// Full-precision description with locale-aware grouping. No K/M/B abbreviation.
    public func accessibilityDescription(_ integer: Int) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.locale = locale
        formatter.usesGroupingSeparator = true
        return formatter.string(from: NSNumber(value: integer)) ?? "\(integer)"
    }
}

// MARK: - Decimal helpers (internal to this file)

extension Decimal {
    /// Returns the integer part of the receiver as a `Decimal`, truncating toward zero.
    fileprivate var wholePart: Decimal {
        var source = self
        var rounded = Decimal()
        NSDecimalRound(&rounded, &source, 0, .down)
        return rounded
    }

    /// Rounds to the given scale using "schoolbook" half-up rounding.
    fileprivate func rounded(scale: Int) -> Decimal {
        var source = self
        var rounded = Decimal()
        NSDecimalRound(&rounded, &source, scale, .plain)
        return rounded
    }
}
