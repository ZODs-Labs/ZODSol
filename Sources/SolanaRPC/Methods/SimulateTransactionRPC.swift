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
        public let minContextSlot: UInt64?

        public init(
            base64Transaction: String,
            sigVerify: Bool = false,
            replaceRecentBlockhash: Bool = true,
            commitment: String = "processed",
            minContextSlot: UInt64? = nil)
        {
            self.base64Transaction = base64Transaction
            self.sigVerify = sigVerify
            self.replaceRecentBlockhash = replaceRecentBlockhash
            self.commitment = commitment
            self.minContextSlot = minContextSlot
        }

        public func encode(to encoder: any Encoder) throws {
            var container = encoder.unkeyedContainer()
            try container.encode(self.base64Transaction)
            struct Config: Encodable {
                let encoding: String
                let sigVerify: Bool
                let replaceRecentBlockhash: Bool
                let commitment: String
                let minContextSlot: UInt64?

                enum CodingKeys: String, CodingKey {
                    case encoding
                    case sigVerify
                    case replaceRecentBlockhash
                    case commitment
                    case minContextSlot
                }

                func encode(to encoder: any Encoder) throws {
                    var c = encoder.container(keyedBy: CodingKeys.self)
                    try c.encode(self.encoding, forKey: .encoding)
                    try c.encode(self.sigVerify, forKey: .sigVerify)
                    try c.encode(self.replaceRecentBlockhash, forKey: .replaceRecentBlockhash)
                    try c.encode(self.commitment, forKey: .commitment)
                    if let minContextSlot { try c.encode(minContextSlot, forKey: .minContextSlot) }
                }
            }
            try container.encode(Config(
                encoding: "base64",
                sigVerify: self.sigVerify,
                replaceRecentBlockhash: self.replaceRecentBlockhash,
                commitment: self.commitment,
                minContextSlot: self.minContextSlot))
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
        public let context: RPCContext
        public let value: Value
    }

    public static func request(
        base64Transaction: String,
        sigVerify: Bool = false,
        replaceRecentBlockhash: Bool = true,
        commitment: String = "processed",
        minContextSlot: UInt64? = nil) -> JSONRPCRequest<Params>
    {
        JSONRPCRequest(
            method: "simulateTransaction",
            params: Params(
                base64Transaction: base64Transaction,
                sigVerify: sigVerify,
                replaceRecentBlockhash: replaceRecentBlockhash,
                commitment: commitment,
                minContextSlot: minContextSlot))
    }
}
