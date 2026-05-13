import Foundation

public struct RPCContext: Decodable, Sendable, Equatable {
    public let slot: UInt64
    public let apiVersion: String?

    public init(slot: UInt64, apiVersion: String? = nil) {
        self.slot = slot
        self.apiVersion = apiVersion
    }
}

