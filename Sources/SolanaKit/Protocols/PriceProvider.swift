import Foundation

/// A spot USD price for a mint together with its 24-hour change percentage.
///
/// Either field may be `nil` if the upstream price oracle has no datapoint
/// in the current window for that field.
public struct PriceQuote: Hashable, Sendable, Codable {
    public let usdPrice: Decimal?
    public let change24h: Double?

    public init(usdPrice: Decimal?, change24h: Double?) {
        self.usdPrice = usdPrice
        self.change24h = change24h
    }
}

/// Returns USD spot prices and 24-hour change percentages for a set of mints
/// and for native SOL.
///
/// Implementations MUST throw `SolanaProviderError` cases at this boundary.
public protocol PriceProvider: Sendable {
    /// Fetch USD price and 24-hour change for each requested mint.
    /// - Parameter mints: The mints to look up. Order is not significant.
    /// - Returns: A dictionary keyed by mint. Mints the provider could not
    ///   price are absent from the result.
    /// - Throws: `SolanaProviderError`.
    func prices(for mints: [Mint]) async throws -> [Mint: PriceQuote]

    /// Fetch the 24-hour USD price-change percentage for native SOL.
    /// - Returns: The percentage change, or `nil` when the provider has no
    ///   data point for the current window.
    /// - Throws: `SolanaProviderError`.
    func solChange24h() async throws -> Double?
}
