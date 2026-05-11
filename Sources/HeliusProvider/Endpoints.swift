import Foundation
import SolanaKit

public struct HeliusEndpoint: Sendable {
    public let rpcURL: URL

    public init(network: SolanaNetwork, apiKey: String) {
        let host: String
        switch network {
        case .mainnet: host = "mainnet.helius-rpc.com"
        case .devnet:  host = "devnet.helius-rpc.com"
        case .testnet: host = "api.testnet.solana.com"
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
}
