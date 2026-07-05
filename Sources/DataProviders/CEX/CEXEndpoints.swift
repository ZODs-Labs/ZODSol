import Foundation

public struct KrakenEndpoint: Sendable {
    public static let ticker = URL(string: "https://api.kraken.com/0/public/Ticker")!
}

public struct CoinbaseEndpoint: Sendable {
    public static func stats(product: String) -> URL {
        URL(string: "https://api.exchange.coinbase.com/products/\(product)/stats")!
    }
}
