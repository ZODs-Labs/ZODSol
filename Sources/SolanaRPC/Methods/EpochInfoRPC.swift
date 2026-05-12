import Foundation

/// `getEpochInfo`: fetches `blockHeight` (raced against
/// `lastValidBlockHeight` during confirmation) and the current `epoch`
/// (used by the Token-2022 transfer-fee math to pick older vs newer fee).
public enum EpochInfoRPC {
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

    public struct Result: Decodable, Sendable, Equatable {
        public let epoch: UInt64
        public let slotIndex: UInt64
        public let slotsInEpoch: UInt64
        public let absoluteSlot: UInt64
        public let blockHeight: UInt64
        public let transactionCount: UInt64?
    }

    public static func request(commitment: String = "confirmed") -> JSONRPCRequest<Params> {
        JSONRPCRequest(method: "getEpochInfo", params: Params(commitment: commitment))
    }
}
