import Foundation

/// Parses a Solana Pay URI string into a `SolanaPayURI`.
///
/// Validates the scheme (case-sensitive `solana:`), the recipient address and
/// every query parameter the spec defines. Amounts are checked against an
/// optional decimal-precision cap so callers can refuse values that would lose
/// precision when scaled to the asset's smallest unit.
public enum SolanaPayURIParser {
    public static func parse(_ text: String, expectedDecimals: Int? = nil) throws -> SolanaPayURI {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            throw SolanaPayParseError.notASolanaPayURI
        }
        guard trimmed.hasPrefix("solana:") else {
            throw SolanaPayParseError.notASolanaPayURI
        }
        guard let components = URLComponents(string: trimmed) else {
            throw SolanaPayParseError.malformedURL
        }

        let recipient = try parseRecipient(components: components)

        var amount: Decimal?
        var splToken: Mint?
        var label: String?
        var message: String?
        var memo: String?
        var references: [WalletAddress] = []

        for item in components.queryItems ?? [] {
            switch item.name {
            case "amount":
                amount = try parseAmount(item.value, expectedDecimals: expectedDecimals)
            case "spl-token":
                splToken = try parseSplToken(item.value)
            case "reference":
                if let reference = try parseReference(item.value) {
                    references.append(reference)
                }
            case "label":
                label = item.value
            case "message":
                message = item.value
            case "memo":
                memo = item.value
            default:
                continue
            }
        }

        return SolanaPayURI(
            recipient: recipient,
            amount: amount,
            splToken: splToken,
            label: label,
            message: message,
            memo: memo,
            references: references
        )
    }

    private static func parseRecipient(components: URLComponents) throws -> WalletAddress {
        var path = components.path
        if path.hasPrefix("/") {
            path.removeFirst()
        }
        guard !path.isEmpty else {
            throw SolanaPayParseError.missingRecipient
        }
        do {
            return try WalletAddress(base58: path)
        } catch {
            throw SolanaPayParseError.invalidRecipient(path)
        }
    }

    private static func parseAmount(_ raw: String?, expectedDecimals: Int?) throws -> Decimal {
        guard let value = raw, !value.isEmpty else {
            throw SolanaPayParseError.invalidAmount(raw ?? "")
        }
        if value.contains("e") || value.contains("E") {
            throw SolanaPayParseError.invalidAmount(value)
        }
        if value.hasPrefix(".") {
            throw SolanaPayParseError.invalidAmount(value)
        }
        guard let decimal = Decimal(string: value, locale: Locale(identifier: "en_US_POSIX")) else {
            throw SolanaPayParseError.invalidAmount(value)
        }
        let cap = expectedDecimals ?? 9
        if let dotIndex = value.firstIndex(of: ".") {
            let fractional = value[value.index(after: dotIndex)...]
            if fractional.count > cap {
                throw SolanaPayParseError.excessDecimals(expected: cap, got: fractional.count)
            }
        }
        return decimal
    }

    private static func parseSplToken(_ raw: String?) throws -> Mint {
        guard let value = raw, !value.isEmpty else {
            throw SolanaPayParseError.invalidSplToken(raw ?? "")
        }
        do {
            return try Mint(base58: value)
        } catch {
            throw SolanaPayParseError.invalidSplToken(value)
        }
    }

    private static func parseReference(_ raw: String?) throws -> WalletAddress? {
        guard let value = raw, !value.isEmpty else {
            throw SolanaPayParseError.invalidReference(raw ?? "")
        }
        do {
            return try WalletAddress(base58: value)
        } catch {
            throw SolanaPayParseError.invalidReference(value)
        }
    }
}
