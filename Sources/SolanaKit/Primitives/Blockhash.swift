import Foundation
import Kit

public struct Blockhash: Hashable, Sendable, Codable, CustomStringConvertible {
    public let bytes: Data

    public init(bytes: Data) throws {
        guard bytes.count == 32 else {
            throw SolanaProviderError.invalidInput("blockhash must be exactly 32 bytes, got \(bytes.count)")
        }
        let base58 = Base58.encode(bytes)
        _ = try Kit.blockhash(base58)
        self.bytes = bytes
    }

    public init(base58: String) throws {
        _ = try Kit.blockhash(base58)
        let decoded = try Base58.decode(base58)
        try self.init(bytes: decoded)
    }

    public var base58: String {
        Base58.encode(self.bytes)
    }

    public var description: String {
        self.base58
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
