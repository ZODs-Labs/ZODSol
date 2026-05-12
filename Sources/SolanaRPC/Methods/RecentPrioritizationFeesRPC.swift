import Foundation

/// `getRecentPrioritizationFees`: returns the prioritization fee paid by
/// transactions that wrote to any of `accountAddresses` over the recent
/// slot window.
///
/// The orchestrator scopes its query to the transaction's writable accounts
/// (sender, recipient ATA, etc.) so the percentile reflects competition for
/// the same write locks — that's the actual fee market the tx will join.
public enum RecentPrioritizationFeesRPC {
    public struct Params: Encodable, Sendable {
        public let accountAddresses: [String]

        public init(accountAddresses: [String]) {
            self.accountAddresses = accountAddresses
        }

        public func encode(to encoder: any Encoder) throws {
            var container = encoder.unkeyedContainer()
            try container.encode(self.accountAddresses)
        }
    }

    public struct Fee: Decodable, Sendable, Equatable {
        public let slot: UInt64
        public let prioritizationFee: UInt64
    }

    public typealias Result = [Fee]

    public static func request(accountAddresses: [String]) -> JSONRPCRequest<Params> {
        JSONRPCRequest(method: "getRecentPrioritizationFees", params: Params(accountAddresses: accountAddresses))
    }
}
