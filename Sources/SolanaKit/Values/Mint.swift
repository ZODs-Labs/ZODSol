import Foundation
import Kit

public struct Mint: Hashable, Sendable, Codable {
    public let address: Kit.Address

    public var base58: String {
        self.address.rawValue
    }

    public init(base58: String) throws {
        do {
            self.address = try Kit.address(base58)
        } catch {
            throw SolanaProviderError.invalidInput("base58 address must decode to exactly 32 bytes")
        }
    }

    public init(address: Kit.Address) {
        self.address = address
    }

    public init(from decoder: any Swift.Decoder) throws {
        let container = try decoder.singleValueContainer()
        let raw = try container.decode(String.self)
        try self.init(base58: raw)
    }

    public func encode(to encoder: any Swift.Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(self.base58)
    }
}
