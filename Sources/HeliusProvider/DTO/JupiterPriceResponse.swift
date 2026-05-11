import Foundation

struct JupiterPriceResponse: Decodable, Sendable {
    let entries: [String: JupiterPrice]

    init(from decoder: any Decoder) throws {
        let container = try decoder.singleValueContainer()
        self.entries = try container.decode([String: JupiterPrice].self)
    }

    init(entries: [String: JupiterPrice]) {
        self.entries = entries
    }
}

struct JupiterPrice: Decodable, Sendable {
    let usdPrice: Decimal?
    let blockId: UInt64?
    let decimals: UInt8?
    let priceChange24h: Double?
}
