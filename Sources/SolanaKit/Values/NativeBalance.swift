import Foundation

public struct NativeBalance: Hashable, Sendable, Codable {
    public let lamports: Lamports
    public let pricePerSol: Decimal?
    public let totalUSD: Decimal?

    public init(lamports: Lamports, pricePerSol: Decimal?, totalUSD: Decimal?) {
        self.lamports = lamports
        self.pricePerSol = pricePerSol
        self.totalUSD = totalUSD
    }
}
