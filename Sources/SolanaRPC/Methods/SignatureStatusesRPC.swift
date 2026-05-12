import Foundation

/// `getSignatureStatuses`: polls for the confirmation status of one or more
/// transaction signatures.
///
/// Pass `searchTransactionHistory = true` only when resyncing a signature
/// that may have rolled past the recent-status window (e.g. on app reopen
/// after the panel was closed mid-send).
public enum SignatureStatusesRPC {
    public struct Params: Encodable, Sendable {
        public let signatures: [String]
        public let searchTransactionHistory: Bool

        public init(signatures: [String], searchTransactionHistory: Bool = false) {
            self.signatures = signatures
            self.searchTransactionHistory = searchTransactionHistory
        }

        public func encode(to encoder: any Encoder) throws {
            var container = encoder.unkeyedContainer()
            try container.encode(self.signatures)
            struct Config: Encodable { let searchTransactionHistory: Bool }
            try container.encode(Config(searchTransactionHistory: self.searchTransactionHistory))
        }
    }

    public struct Status: Decodable, Sendable {
        public let slot: UInt64
        public let confirmations: UInt64?
        public let err: AnyJSON?
        public let confirmationStatus: String?
    }

    public struct Result: Decodable, Sendable {
        public let value: [Status?]
    }

    public static func request(
        signatures: [String],
        searchTransactionHistory: Bool = false) -> JSONRPCRequest<Params>
    {
        JSONRPCRequest(
            method: "getSignatureStatuses",
            params: Params(signatures: signatures, searchTransactionHistory: searchTransactionHistory))
    }
}
