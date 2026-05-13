import Foundation

/// `sendTransaction`: submits a base64-encoded signed transaction.
///
public enum SendTransactionRPC {
    public struct Params: Encodable, Sendable {
        public let base64Transaction: String
        public let skipPreflight: Bool
        public let preflightCommitment: String
        public let maxRetries: UInt32?
        public let maxSupportedTransactionVersion: UInt8

        public init(
            base64Transaction: String,
            skipPreflight: Bool = true,
            preflightCommitment: String = "confirmed",
            maxRetries: UInt32? = nil,
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
            try container.encode(ConfigPayload(
                encoding: "base64",
                skipPreflight: self.skipPreflight,
                preflightCommitment: self.preflightCommitment,
                maxRetries: self.maxRetries,
                maxSupportedTransactionVersion: self.maxSupportedTransactionVersion))
        }

        private struct ConfigPayload: Encodable {
            let encoding: String
            let skipPreflight: Bool
            let preflightCommitment: String
            let maxRetries: UInt32?
            let maxSupportedTransactionVersion: UInt8

            enum CodingKeys: String, CodingKey {
                case encoding
                case skipPreflight
                case preflightCommitment
                case maxRetries
                case maxSupportedTransactionVersion
            }

            func encode(to encoder: any Encoder) throws {
                var c = encoder.container(keyedBy: CodingKeys.self)
                try c.encode(self.encoding, forKey: .encoding)
                try c.encode(self.skipPreflight, forKey: .skipPreflight)
                try c.encode(self.preflightCommitment, forKey: .preflightCommitment)
                if let maxRetries { try c.encode(maxRetries, forKey: .maxRetries) }
                try c.encode(
                    self.maxSupportedTransactionVersion,
                    forKey: .maxSupportedTransactionVersion)
            }
        }
    }

    /// `result` is the base58-encoded transaction signature.
    public static func request(
        base64Transaction: String,
        skipPreflight: Bool = true,
        preflightCommitment: String = "confirmed",
        maxRetries: UInt32? = nil) -> JSONRPCRequest<Params>
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
