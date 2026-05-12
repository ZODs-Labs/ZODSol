import Foundation

/// Serializes a Solana Pay payment request into a `URL`.
///
/// Query items are emitted in a stable order: `amount`, `spl-token`, every
/// `reference` in input order, then `label`, `message`, `memo`. `URLComponents`
/// applies UTF-8 percent-encoding to the human-readable fields.
public enum SolanaPayURIBuilder {
    public static func build(
        recipient: WalletAddress,
        amount: Decimal? = nil,
        splToken: Mint? = nil,
        label: String? = nil,
        message: String? = nil,
        memo: String? = nil,
        references: [WalletAddress] = []
    ) throws -> URL {
        var components = URLComponents()
        components.scheme = "solana"
        components.host = nil
        components.path = recipient.base58

        var items: [URLQueryItem] = []

        if let amount {
            let serialized = try serialize(amount: amount)
            items.append(URLQueryItem(name: "amount", value: serialized))
        }
        if let splToken {
            items.append(URLQueryItem(name: "spl-token", value: splToken.base58))
        }
        for reference in references {
            items.append(URLQueryItem(name: "reference", value: reference.base58))
        }
        if let label {
            items.append(URLQueryItem(name: "label", value: label))
        }
        if let message {
            items.append(URLQueryItem(name: "message", value: message))
        }
        if let memo {
            items.append(URLQueryItem(name: "memo", value: memo))
        }

        if !items.isEmpty {
            components.queryItems = items
        }

        guard let url = components.url else {
            throw SolanaPayParseError.malformedURL
        }
        return url
    }

    private static func serialize(amount: Decimal) throws -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.usesGroupingSeparator = false
        formatter.minimumFractionDigits = 0
        formatter.maximumFractionDigits = 20
        formatter.locale = Locale(identifier: "en_US_POSIX")

        let value = NSDecimalNumber(decimal: amount)
        guard let raw = formatter.string(from: value) else {
            throw SolanaPayParseError.invalidAmount("\(amount)")
        }
        guard isFiniteNonNegativeDecimal(raw) else {
            throw SolanaPayParseError.invalidAmount(raw)
        }
        return raw
    }

    private static func isFiniteNonNegativeDecimal(_ value: String) -> Bool {
        // Matches ^(0|[1-9][0-9]*)(\.[0-9]+)?$ without pulling in NSRegularExpression.
        guard !value.isEmpty else { return false }
        let parts = value.split(separator: ".", omittingEmptySubsequences: false)
        if parts.count > 2 { return false }
        let integer = parts[0]
        guard !integer.isEmpty else { return false }
        if integer.count > 1 && integer.first == "0" { return false }
        for character in integer where !character.isASCII || !character.isNumber {
            return false
        }
        if parts.count == 2 {
            let fraction = parts[1]
            if fraction.isEmpty { return false }
            for character in fraction where !character.isASCII || !character.isNumber {
                return false
            }
        }
        return true
    }
}
