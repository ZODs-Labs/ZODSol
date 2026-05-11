import Foundation

/// Composed entry point used by the domain layer: a single dependency that
/// exposes balance, token-account, asset-metadata and price capabilities.
///
/// Concrete implementations (for example the Helius-backed provider in the
/// `HeliusProvider` library) conform to `SolanaProvider` directly. The domain
/// layer depends only on this composed protocol so backends can be swapped
/// without ripple changes upstream.
public protocol SolanaProvider: BalanceProvider, TokenAccountsProvider, AssetMetadataProvider, PriceProvider, Sendable {}
