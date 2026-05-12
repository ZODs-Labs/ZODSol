import Foundation

/// `sendTransaction`: submits a base64-encoded signed transaction.
///
/// We always set `skipPreflight = false` and pin `maxSupportedTransactionVersion = 0`
/// (V0 is the only format we emit). `maxRetries = 0` because callers handle
/// rebroadcast themselves so they can re-sign on blockhash expiry.
public enum SendTransactionRPC {
    public struct Params: Encodable, Sendable {
        public let base64Transaction: String
        public let skipPreflight: Bool
        public let preflightCommitment: String
        public let maxRetries: UInt32
        public let maxSupportedTransactionVersion: UInt8

        public init(
            base64Transaction: String,
            skipPreflight: Bool = false,
            preflightCommitment: String = "confirmed",
            maxRetries: UInt32 = 0,
            maxSupportedTransactionVersion: UInt8 = 0)
        {
            self.base64Transaction = base64Transaction
            self.skipPreflight = skipPreflight
            self.preflightCommitment = preflightCommitment
            self.maxRetries = maxRetries
            self.maxSupportedTransactionVersion = maxSupportedTransactionVersion
        }

        public func encode(to encoder: any Encoder) throws {
            var container = encoder.unkeyedContainer()
            try container.encode(self.base64Transaction)
            struct Config: Encodable {
                let encoding: String
                let skipPreflight: Bool
                let preflightCommitment: String
                let maxRetries: UInt32
                let maxSupportedTransactionVersion: UInt8
            }
            try container.encode(Config(
                encoding: "base64",
                skipPreflight: self.skipPreflight,
                preflightCommitment: self.preflightCommitment,
                maxRetries: self.maxRetries,
                maxSupportedTransactionVersion: self.maxSupportedTransactionVersion))
        }
    }

    /// `result` is the base58-encoded transaction signature.
    public static func request(
        base64Transaction: String,
        skipPreflight: Bool = false,
        preflightCommitment: String = "confirmed",
        maxRetries: UInt32 = 0) -> JSONRPCRequest<Params>
    {
        JSONRPCRequest(
            method: "sendTransaction",
            params: Params(
                base64Transaction: base64Transaction,
                skipPreflight: skipPreflight,
                preflightCommitment: preflightCommitment,
                maxRetries: maxRetries))
    }
}
