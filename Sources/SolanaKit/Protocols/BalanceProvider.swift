import Foundation

/// Returns the native SOL balance for a given wallet address.
///
/// Implementations MUST throw `SolanaProviderError` cases at this boundary.
public protocol BalanceProvider: Sendable {
    /// Fetch the native SOL balance, expressed in lamports, for `address` on `network`.
    /// - Parameters:
    ///   - address: The wallet whose balance is being queried.
    ///   - network: The Solana network to query (mainnet, devnet, testnet).
    /// - Returns: The balance in lamports.
    /// - Throws: `SolanaProviderError`.
    func solBalance(for address: WalletAddress, network: SolanaNetwork) async throws -> Lamports
}
