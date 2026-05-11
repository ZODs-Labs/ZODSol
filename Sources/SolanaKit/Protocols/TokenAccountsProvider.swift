import Foundation

/// Returns the parsed SPL token accounts owned by a wallet.
///
/// Implementations MUST throw `SolanaProviderError` cases at this boundary.
public protocol TokenAccountsProvider: Sendable {
    /// Fetch the parsed token accounts for `address` on `network`.
    /// - Parameters:
    ///   - address: The wallet whose token accounts are being queried.
    ///   - network: The Solana network to query.
    /// - Returns: Each entry pairs a mint with its raw atomic balance and the
    ///   owning token-account address.
    /// - Throws: `SolanaProviderError`.
    func tokenAccounts(for address: WalletAddress, network: SolanaNetwork) async throws -> [ParsedTokenAccount]
}
