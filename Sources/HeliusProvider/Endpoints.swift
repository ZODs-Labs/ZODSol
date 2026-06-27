import Foundation
import SolanaKit

public struct HeliusEndpoint: Sendable {
    public let rpcURL: URL

    public init(network: SolanaNetwork, apiKey: String) {
        let host = switch network {
        case .mainnet: "mainnet.helius-rpc.com"
        case .devnet: "devnet.helius-rpc.com"
        case .testnet: "api.testnet.solana.com"
        }
        var c = URLComponents()
        c.scheme = "https"
        c.host = host
        c.path = "/"
        c.queryItems = [URLQueryItem(name: "api-key", value: apiKey)]
        self.rpcURL = c.url!
    }
}

public struct JupiterEndpoint: Sendable {
    public static let priceV3 = URL(string: "https://lite-api.jup.ag/price/v3")!
    public static let tokensSearch = URL(string: "https://lite-api.jup.ag/tokens/v2/search")!
}

public struct KrakenEndpoint: Sendable {
    public static let ticker = URL(string: "https://api.kraken.com/0/public/Ticker")!
}

public struct CoinbaseEndpoint: Sendable {
    public static func stats(product: String) -> URL {
        URL(string: "https://api.exchange.coinbase.com/products/\(product)/stats")!
    }
}
