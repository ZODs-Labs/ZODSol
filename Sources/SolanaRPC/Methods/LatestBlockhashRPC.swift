import Foundation

/// `getLatestBlockhash`: fetches the cluster's latest blockhash and the block
/// height up to which a transaction signed under it can still be confirmed.
public enum LatestBlockhashRPC {
    public struct Params: Encodable, Sendable {
        public let commitment: String

        public init(commitment: String = "confirmed") {
            self.commitment = commitment
        }

        public func encode(to encoder: any Encoder) throws {
            var container = encoder.unkeyedContainer()
            struct Config: Encodable { let commitment: String }
            try container.encode(Config(commitment: self.commitment))
        }
    }

    public struct Value: Decodable, Sendable, Equatable {
        public let blockhash: String
        public let lastValidBlockHeight: UInt64
    }

    public struct Result: Decodable, Sendable {
        public let context: RPCContext
        public let value: Value
    }

    public static func request(commitment: String = "confirmed") -> JSONRPCRequest<Params> {
        JSONRPCRequest(method: "getLatestBlockhash", params: Params(commitment: commitment))
    }
}
