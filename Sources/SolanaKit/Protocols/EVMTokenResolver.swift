import Foundation

/// A token resolved on one EVM chain, with the display metadata and the
/// liquidity the resolver used to rank it. `liquidityUSD` is the summed USD
/// liquidity across the token's pools on that chain.
public struct EVMResolvedToken: Sendable, Equatable {
    public let chain: EVMChain
    public let address: String
    public let symbol: String
    public let name: String
    public let iconURL: URL?
    public let liquidityUSD: Decimal

    public init(
        chain: EVMChain,
        address: String,
        symbol: String,
        name: String,
        iconURL: URL?,
        liquidityUSD: Decimal)
    {
        self.chain = chain
        self.address = address.lowercased()
        self.symbol = symbol
        self.name = name
        self.iconURL = iconURL
        self.liquidityUSD = liquidityUSD
    }

    public var ref: EVMTokenRef {
        EVMTokenRef(chain: self.chain, address: self.address)
    }
}

/// The outcome of detecting which chain(s) host a pasted EVM address and
/// resolving the token. Because the address alone is ambiguous, resolution
/// fails closed: zero qualifying chains yields a reason, many yields a choice.
public enum EVMResolution: Sendable, Equatable {
    /// Exactly one supported chain hosts a liquid market: add it silently.
    case resolved(EVMResolvedToken)
    /// Several supported chains qualify: the user must disambiguate. Ranked by
    /// liquidity, deepest first.
    case multipleChains([EVMResolvedToken])
    /// No supported chain hosts a tradeable market for this address.
    case notFound
    /// The token trades only on a chain outside the supported allow-list. The
    /// associated value is a display-ready chain name.
    case unsupportedChain(String)
    /// Found, but no chain clears the liquidity floor. The associated value is
    /// the deepest liquidity seen, so the message can name it.
    case lowLiquidity(Decimal)
    /// The price service could not be reached; distinct from `notFound` so the
    /// UI says "try again" rather than "no such token".
    case serviceUnavailable
}

/// Detects the chain for a pasted EVM contract address and resolves its display
/// metadata. Implementations MUST NOT throw: every failure maps to a case above.
public protocol EVMTokenResolving: Sendable {
    func resolve(address: String) async -> EVMResolution
}
