import Foundation

/// A 64-byte Ed25519 signature over a Solana transaction message.
///
/// Encoded as base58 in JSON-RPC responses. This is the public identifier of
/// a submitted transaction (a transaction "signature" in Solana parlance).
public struct Signature: Hashable, Sendable, Codable, CustomStringConvertible {
    public let bytes: Data

    public init(bytes: Data) throws {
        guard bytes.count == 64 else {
            throw SolanaProviderError.invalidInput(
                "signature must be exactly 64 bytes, got \(bytes.count)")
        }
        self.bytes = bytes
    }

    public init(base58: String) throws {
        let decoded = try Base58.decode(base58)
        try self.init(bytes: decoded)
    }

    public var base58: String {
        Base58.encode(self.bytes)
    }

    public var description: String {
        self.base58
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.singleValueContainer()
        let raw = try container.decode(String.self)
        try self.init(base58: raw)
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(self.base58)
    }
}
