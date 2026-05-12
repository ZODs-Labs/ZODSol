import Foundation
import SolanaKit

public struct TokenAmountFormatter: Sendable {
    public let locale: Locale

    public init(locale: Locale = .current) {
        self.locale = locale
    }

    /// Compact balance rendering that matches the web tool's `formatLargeNumber`:
    /// `Intl.NumberFormat("en-US", { notation: "compact", min: 0, max: 2 })`.
    /// Used by the portfolio row's balance column where space is tight and the
    /// precise count never matters more than the value/share next to it.
    public func largeNumber(_ ui: Decimal) -> String {
        ui.formatted(
            .number
                .notation(.compactName)
                .precision(.fractionLength(0 ... 2))
                .locale(Locale(identifier: "en_US"))
        )
    }

    public func string(_ amount: TokenAmount, symbol: String?) -> String {
        let ui = amount.uiAmount
        let suffix = (symbol.map { $0.isEmpty ? nil : $0 } ?? nil).map { " \($0)" } ?? ""
        if ui == 0 { return "0\(suffix)" }

        let isNegative = ui < 0
        let absUI = abs(ui)
        let signGlyph = isNegative ? "\u{2212}" : ""

        if absUI >= 1 {
            return "\(signGlyph)\(decimalFormatted(absUI, minFractionDigits: 0, maxFractionDigits: 2))\(suffix)"
        }
        if absUI >= Decimal(string: "0.001")! {
            return "\(signGlyph)\(decimalSignificant(absUI, significantDigits: 4))\(suffix)"
        }

        return "\(signGlyph)\(subscriptZeroFormatted(absUI))\(suffix)"
    }

    private func decimalFormatted(_ v: Decimal, minFractionDigits: Int, maxFractionDigits: Int) -> String {
        let f = NumberFormatter()
        f.numberStyle = .decimal
        f.locale = locale
        f.minimumFractionDigits = minFractionDigits
        f.maximumFractionDigits = maxFractionDigits
        f.usesGroupingSeparator = true
        return f.string(from: v as NSDecimalNumber) ?? "\(v)"
    }

    private func decimalSignificant(_ v: Decimal, significantDigits: Int) -> String {
        let f = NumberFormatter()
        f.numberStyle = .decimal
        f.locale = locale
        f.usesSignificantDigits = true
        f.minimumSignificantDigits = 1
        f.maximumSignificantDigits = significantDigits
        f.usesGroupingSeparator = false
        return f.string(from: v as NSDecimalNumber) ?? "\(v)"
    }

    private func subscriptZeroFormatted(_ v: Decimal) -> String {
        let posix = (v as NSDecimalNumber).description(withLocale: Locale(identifier: "en_US_POSIX"))
        let afterDot: String
        if let dotIdx = posix.firstIndex(of: ".") {
            afterDot = String(posix[posix.index(after: dotIdx)...])
        } else {
            afterDot = "0"
        }
        let leadingZeros = afterDot.prefix(while: { $0 == "0" }).count
        let significant = String(afterDot.dropFirst(leadingZeros).prefix(4))
        let decimalSep = locale.decimalSeparator ?? "."
        let subscriptChars = Self.subscriptDigits(leadingZeros)
        return "0\(decimalSep)0\(subscriptChars)\(significant)"
    }

    private static func subscriptDigits(_ n: Int) -> String {
        let table: [Character] = [
            "\u{2080}", "\u{2081}", "\u{2082}", "\u{2083}", "\u{2084}",
            "\u{2085}", "\u{2086}", "\u{2087}", "\u{2088}", "\u{2089}"
        ]
        return String(String(n).compactMap { ch in
            guard let d = ch.wholeNumberValue, d >= 0, d <= 9 else { return nil }
            return table[d]
        })
    }
}
