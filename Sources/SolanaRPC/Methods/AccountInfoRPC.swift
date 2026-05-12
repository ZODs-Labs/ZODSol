import Foundation

/// `getAccountInfo`: returns one account's data. We always request
/// `encoding: "base64"` so the bytes survive without truncation; callers
/// base64-decode and route to the appropriate domain parser.
///
/// Used for: (1) reading mint accounts to determine owner program (legacy
/// vs Token-2022) and parse extensions, (2) checking recipient ATA existence,
/// (3) reading recipient lamports for SOL "send max" math.
public enum AccountInfoRPC {
    public struct Params: Encodable, Sendable {
        public let address: String
        public let commitment: String

        public init(address: String, commitment: String = "confirmed") {
            self.address = address
            self.commitment = commitment
        }

        public func encode(to encoder: any Encoder) throws {
            var container = encoder.unkeyedContainer()
            try container.encode(self.address)
            struct Config: Encodable { let encoding: String; let commitment: String }
            try container.encode(Config(encoding: "base64", commitment: self.commitment))
        }
    }

    /// `data` is a `[base64String, "base64"]` tuple in the RPC response.
    public struct AccountValue: Decodable, Sendable {
        public let lamports: UInt64
        public let owner: String
        public let executable: Bool
        public let rentEpoch: UInt64?
        public let data: [String]

        public var base64Data: String? {
            self.data.first
        }
    }

    public struct Result: Decodable, Sendable {
        public let value: AccountValue?
    }

    public static func request(address: String, commitment: String = "confirmed") -> JSONRPCRequest<Params> {
        JSONRPCRequest(method: "getAccountInfo", params: Params(address: address, commitment: commitment))
    }
}
