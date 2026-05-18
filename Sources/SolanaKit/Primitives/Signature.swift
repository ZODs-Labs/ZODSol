import Foundation
import Kit

public struct Signature: Hashable, Sendable, Codable, CustomStringConvertible {
    public let bytes: Data

    public init(bytes: Data) throws {
        guard (try? Kit.signatureBytes(bytes)) != nil else {
            throw SolanaProviderError.invalidInput("signature must be exactly 64 bytes, got \(bytes.count)")
        }
        self.bytes = bytes
    }

    public init(base58: String) throws {
        _ = try Kit.signature(base58)
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

    public static func sign(message: Data, seed: Data) throws -> Signature {
        do {
            let privateKey = try Kit.createPrivateKeyFromBytes(seed)
            let signature = try Kit.signBytes(message, with: privateKey, using: ZODSolCryptoBackend())
            return try Signature(bytes: signature.rawValue)
        } catch {
            throw SolanaProviderError.invalidInput("stored private key is corrupt")
        }
    }
}
