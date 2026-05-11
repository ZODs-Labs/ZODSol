import Foundation
import SolanaKit

public struct WalletIdentity: Hashable, Sendable, Codable, Identifiable {
    public let id: UUID
    public let address: WalletAddress
    public var label: String
    public let createdAt: Date

    public init(id: UUID, address: WalletAddress, label: String, createdAt: Date) {
        self.id = id
        self.address = address
        self.label = label
        self.createdAt = createdAt
    }
}
