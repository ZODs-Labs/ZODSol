import Foundation

/// DefiLlama `/prices/current` coin entry. `price` is decoded as `Decimal` so the
/// JSON number is not routed through binary `Double`. `confidence` (0...1) gates
/// low-quality prices.
struct DefiLlamaCoin: Decodable {
    let price: Decimal?
    let confidence: Double?
}

struct DefiLlamaCurrentResponse: Decodable {
    let coins: [String: DefiLlamaCoin]
}

/// `/percentage` returns the 24h change as a signed fraction (`-0.0035` == -0.35%).
struct DefiLlamaPercentageResponse: Decodable {
    let coins: [String: Double]
}
