import Foundation

public struct Mint: Hashable, Sendable, Codable {
    public let base58: String

    public init(base58: String) throws {
        let decoded = try Base58.decode(base58)
        guard decoded.count == 32 else {
            throw SolanaProviderError.invalidInput(
                "base58 address must decode to exactly 32 bytes"
            )
        }
        self.base58 = base58
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.singleValueContainer()
        let raw = try container.decode(String.self)
        try self.init(base58: raw)
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(base58)
    }
}
