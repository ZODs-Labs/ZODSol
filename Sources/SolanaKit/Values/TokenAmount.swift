import Foundation

public struct TokenAmount: Hashable, Sendable, Codable {
    public let amount: UInt64
    public let decimals: UInt8

    public var uiAmount: Decimal {
        Decimal(self.amount) / pow(Decimal(10), Int(self.decimals))
    }

    public init(amount: UInt64, decimals: UInt8) {
        self.amount = amount
        self.decimals = decimals
    }
}
