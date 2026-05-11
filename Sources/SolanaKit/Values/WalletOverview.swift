import Foundation

public struct WalletOverview: Hashable, Sendable, Codable {
    public let walletId: UUID
    public let address: WalletAddress
    public let solBalance: Lamports
    public let solPriceUSD: Decimal?
    public let solChange24h: Double?
    public let tokens: [AssetSummary]
    public let nfts: NFTSummary
    public let totalUSD: Decimal?
    public let totalChange24h: Double?
    public let asOf: Date
    public let isPartial: Bool

    public init(
        walletId: UUID,
        address: WalletAddress,
        solBalance: Lamports,
        solPriceUSD: Decimal?,
        solChange24h: Double?,
        tokens: [AssetSummary],
        nfts: NFTSummary,
        totalUSD: Decimal?,
        totalChange24h: Double?,
        asOf: Date,
        isPartial: Bool
    ) {
        self.walletId = walletId
        self.address = address
        self.solBalance = solBalance
        self.solPriceUSD = solPriceUSD
        self.solChange24h = solChange24h
        self.tokens = tokens
        self.nfts = nfts
        self.totalUSD = totalUSD
        self.totalChange24h = totalChange24h
        self.asOf = asOf
        self.isPartial = isPartial
    }
}
