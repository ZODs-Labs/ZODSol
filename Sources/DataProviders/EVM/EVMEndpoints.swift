import Foundation

public struct DexScreenerEndpoint: Sendable {
    public static let search = URL(string: "https://api.dexscreener.com/latest/dex/search")!

    /// Chain-scoped batch, up to 30 comma-separated addresses. The chain id and
    /// addresses are lowercase alphanumerics so they are path-safe as-is.
    public static func tokens(chainId: String, addresses: [String]) -> URL {
        URL(string: "https://api.dexscreener.com/tokens/v1/\(chainId)/\(addresses.joined(separator: ","))")!
    }
}

public struct DefiLlamaEndpoint: Sendable {
    /// `coins` are `{chain}:{address}` keys; colons and commas are path-legal.
    public static func currentPrices(_ coins: [String]) -> URL {
        URL(string: "https://coins.llama.fi/prices/current/\(coins.joined(separator: ","))")!
    }

    public static func percentage(_ coins: [String]) -> URL {
        URL(string: "https://coins.llama.fi/percentage/\(coins.joined(separator: ","))?period=24h")!
    }
}
