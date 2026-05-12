import Foundation

/// A 32-byte Solana blockhash.
///
/// Used to bind a transaction to a recent block; the cluster will reject a
/// transaction whose blockhash is older than ~150 slots. Construct from the
/// base58 string the RPC returns or from raw bytes for tests.
public struct Blockhash: Hashable, Sendable, Codable, CustomStringConvertible {
    public let bytes: Data

    public init(bytes: Data) throws {
        guard bytes.count == 32 else {
            throw SolanaProviderError.invalidInput(
                "blockhash must be exactly 32 bytes, got \(bytes.count)")
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
