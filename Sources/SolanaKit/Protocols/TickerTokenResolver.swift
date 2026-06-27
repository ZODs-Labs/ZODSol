import Foundation

/// Display metadata for a Solana mint the user pasted into the ticker, resolved
/// from a token index (Jupiter) so the menu bar can show a symbol and icon
/// instead of a raw address.
public struct ResolvedTickerToken: Sendable, Equatable {
    public let mint: String
    public let symbol: String
    public let name: String
    public let decimals: Int
    public let iconURL: URL?

    public init(mint: String, symbol: String, name: String, decimals: Int, iconURL: URL?) {
        self.mint = mint
        self.symbol = symbol
        self.name = name
        self.decimals = decimals
        self.iconURL = iconURL
    }
}

/// Resolves a Solana mint address to ticker display metadata. Implementations
/// MUST NOT throw: an unresolvable or unreachable mint returns nil.
public protocol TickerTokenResolving: Sendable {
    func resolve(mint: String) async -> ResolvedTickerToken?
}
