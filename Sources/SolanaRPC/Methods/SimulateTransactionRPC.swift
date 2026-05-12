import Foundation

/// `simulateTransaction`: dry-runs a transaction. Used twice in the send
/// pipeline:
///
///   1. To estimate the compute-unit limit: `sigVerify = false` (we sim with
///      placeholder all-zero signatures) and `replaceRecentBlockhash = true`
///      so a stale blockhash doesn't cause an immediate failure.
///   2. As a pre-broadcast safety check after the user sees the confirm
///      screen but before we ask them to sign for real.
public enum SimulateTransactionRPC {
    public struct Params: Encodable, Sendable {
        public let base64Transaction: String
        public let sigVerify: Bool
        public let replaceRecentBlockhash: Bool
        public let commitment: String

        public init(
            base64Transaction: String,
            sigVerify: Bool = false,
            replaceRecentBlockhash: Bool = true,
            commitment: String = "processed")
        {
            self.base64Transaction = base64Transaction
            self.sigVerify = sigVerify
            self.replaceRecentBlockhash = replaceRecentBlockhash
            self.commitment = commitment
        }

        public func encode(to encoder: any Encoder) throws {
            var container = encoder.unkeyedContainer()
            try container.encode(self.base64Transaction)
            struct Config: Encodable {
                let encoding: String
                let sigVerify: Bool
                let replaceRecentBlockhash: Bool
                let commitment: String
            }
            try container.encode(Config(
                encoding: "base64",
                sigVerify: self.sigVerify,
                replaceRecentBlockhash: self.replaceRecentBlockhash,
                commitment: self.commitment))
        }
    }

    /// We don't try to decode the raw `err` payload — it's an arbitrarily
    /// shaped variant; surface as a JSON-ish blob via `AnyJSON` and let the
    /// caller render it.
    public struct Value: Decodable, Sendable {
        public let err: AnyJSON?
        public let logs: [String]?
        public let unitsConsumed: UInt64?
    }

    public struct Result: Decodable, Sendable {
        public let value: Value
    }

    public static func request(
        base64Transaction: String,
        sigVerify: Bool = false,
        replaceRecentBlockhash: Bool = true,
        commitment: String = "processed") -> JSONRPCRequest<Params>
    {
        JSONRPCRequest(
            method: "simulateTransaction",
            params: Params(
                base64Transaction: base64Transaction,
                sigVerify: sigVerify,
                replaceRecentBlockhash: replaceRecentBlockhash,
                commitment: commitment))
    }
}
