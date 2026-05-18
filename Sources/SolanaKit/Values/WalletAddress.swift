import Foundation
import Kit

public struct WalletAddress: Hashable, Sendable, Codable, CustomStringConvertible {
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

    public static func derivedFromPrivateKeySeed(_ seed: Data) throws -> WalletAddress {
        do {
            let publicKey = try ZODSolCryptoBackend().publicKey(privateKeyBytes: seed)
            return try WalletAddress(base58: Base58.encode(publicKey))
        } catch {
            throw SolanaProviderError.invalidInput("invalid private-key seed")
        }
    }

    public var description: String {
        self.base58
    }

    public func shortened(prefix: Int = 4, suffix: Int = 4) -> String {
        "\(self.base58.prefix(prefix))…\(self.base58.suffix(suffix))"
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
