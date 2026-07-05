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
