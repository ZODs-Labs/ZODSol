import Foundation

/// Parsed representation of a Solana Pay payment request URI.
///
/// Follows the Solana Pay spec at https://solanapay.com: scheme `solana:`,
/// recipient in the URL path, optional `amount`, `spl-token`, `reference`
/// (repeatable), `label`, `message` and `memo` query parameters.
public struct SolanaPayURI: Sendable, Equatable {
    public let recipient: WalletAddress
    public let amount: Decimal?
    public let splToken: Mint?
    public let label: String?
    public let message: String?
    public let memo: String?
    public let references: [WalletAddress]

    public init(
        recipient: WalletAddress,
        amount: Decimal?,
        splToken: Mint?,
        label: String?,
        message: String?,
        memo: String?,
        references: [WalletAddress]
    ) {
        self.recipient = recipient
        self.amount = amount
        self.splToken = splToken
        self.label = label
        self.message = message
        self.memo = memo
        self.references = references
    }
}

/// Failure modes for building or parsing a Solana Pay URI.
public enum SolanaPayParseError: Error, Sendable, Equatable {
    case notASolanaPayURI
    case missingRecipient
    case invalidRecipient(String)
    case invalidAmount(String)
    case excessDecimals(expected: Int, got: Int)
    case invalidSplToken(String)
    case invalidReference(String)
    case malformedURL
}
