import Foundation

/// Returns 24-hour USD price-change percentages for a set of mints and for SOL.
///
/// Implementations MUST throw `SolanaProviderError` cases at this boundary.
public protocol PriceProvider: Sendable {
    /// Fetch the 24-hour USD price-change percentage for each requested mint.
    /// - Parameter mints: The mints to look up. Order is not significant.
    /// - Returns: A dictionary keyed by mint. Mints the provider could not
    ///   price are simply absent from the result.
    /// - Throws: `SolanaProviderError`.
    func priceChange24h(for mints: [Mint]) async throws -> [Mint: Double]

    /// Fetch the 24-hour USD price-change percentage for native SOL.
    /// - Returns: The percentage change, or `nil` when the provider has no
    ///   data point for the current window.
    /// - Throws: `SolanaProviderError`.
    func solChange24h() async throws -> Double?
}
