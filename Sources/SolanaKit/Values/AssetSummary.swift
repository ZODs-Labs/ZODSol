import Foundation

public struct AssetSummary: Hashable, Sendable, Codable, Identifiable {
    public let id: Mint
    public let kind: AssetKind
    public let symbol: String?
    public let name: String?
    public let imageURL: URL?
    public let amount: TokenAmount
    public let usdValue: Decimal?
    public let pricePerToken: Decimal?
    public let priceChange24h: Double?
    public let tokenProgram: String?

    public init(
        id: Mint,
        kind: AssetKind,
        symbol: String?,
        name: String?,
        imageURL: URL?,
        amount: TokenAmount,
        usdValue: Decimal?,
        pricePerToken: Decimal?,
        priceChange24h: Double?,
        tokenProgram: String?
    ) {
        self.id = id
        self.kind = kind
        self.symbol = symbol
        self.name = name
        self.imageURL = imageURL
        self.amount = amount
        self.usdValue = usdValue
        self.pricePerToken = pricePerToken
        self.priceChange24h = priceChange24h
        self.tokenProgram = tokenProgram
    }
}
