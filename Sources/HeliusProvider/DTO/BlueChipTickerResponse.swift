import Foundation

/// Kraken `/0/public/Ticker` response. Keyed by the legacy pair code Kraken
/// returns (e.g. `XXBTZUSD`), which the client passes in verbatim so request
/// keys equal response keys. Only the fields the ticker needs are decoded;
/// Kraken's other ticker fields are ignored.
struct KrakenTickerResponse: Decodable {
    let error: [String]
    let result: [String: KrakenPair]
}

struct KrakenPair: Decodable {
    /// Last trade closed: `[price, lotVolume]`.
    let c: [String]
    /// Today's opening price (UTC-midnight rolling), used for the 24h change.
    let o: String
}

/// Coinbase Exchange `/products/{id}/stats` response. All values are strings.
struct CoinbaseStats: Decodable {
    let open: String
    let last: String
}
