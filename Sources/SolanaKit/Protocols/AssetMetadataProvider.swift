import Foundation

/// Returns a page of enriched asset summaries (fungibles, NFTs, native balance)
/// for a wallet.
///
/// Implementations MUST throw `SolanaProviderError` cases at this boundary.
public protocol AssetMetadataProvider: Sendable {
    /// Fetch a paginated set of assets owned by `address` on `network`.
    /// - Parameters:
    ///   - address: The wallet to inspect.
    ///   - network: The Solana network to query.
    ///   - options: Pagination and filter knobs (page, limit, what to include).
    /// - Returns: A page of asset summaries plus the optional native-SOL balance.
    /// - Throws: `SolanaProviderError`.
    func assets(for address: WalletAddress,
                network: SolanaNetwork,
                options: AssetQueryOptions) async throws -> AssetPage
}
