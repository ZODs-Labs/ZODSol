import Foundation

public struct AssetSummary: Hashable, Sendable, Codable, Identifiable {
    public let id: Mint
    public let kind: AssetKind
    public let symbol: String?
    public let name: String?
    public let imageURL: URL?
    /// Permitted alternate image URLs to try if `imageURL` fails. Ordered
    /// preferred-first. Empty for assets that exposed only a single
    /// candidate. The image loader walks this list before giving up.
    public let imageURLAlternates: [URL]
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
        imageURLAlternates: [URL] = [],
        amount: TokenAmount,
        usdValue: Decimal?,
        pricePerToken: Decimal?,
        priceChange24h: Double?,
        tokenProgram: String?)
    {
        self.id = id
        self.kind = kind
        self.symbol = symbol
        self.name = name
        self.imageURL = imageURL
        self.imageURLAlternates = imageURLAlternates
        self.amount = amount
        self.usdValue = usdValue
        self.pricePerToken = pricePerToken
        self.priceChange24h = priceChange24h
        self.tokenProgram = tokenProgram
    }

    public init(from decoder: any Swift.Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.id = try c.decode(Mint.self, forKey: .id)
        self.kind = try c.decode(AssetKind.self, forKey: .kind)
        self.symbol = try c.decodeIfPresent(String.self, forKey: .symbol)
        self.name = try c.decodeIfPresent(String.self, forKey: .name)
        self.imageURL = try c.decodeIfPresent(URL.self, forKey: .imageURL)
        self.imageURLAlternates = try c.decodeIfPresent([URL].self, forKey: .imageURLAlternates) ?? []
        self.amount = try c.decode(TokenAmount.self, forKey: .amount)
        self.usdValue = try c.decodeIfPresent(Decimal.self, forKey: .usdValue)
        self.pricePerToken = try c.decodeIfPresent(Decimal.self, forKey: .pricePerToken)
        self.priceChange24h = try c.decodeIfPresent(Double.self, forKey: .priceChange24h)
        self.tokenProgram = try c.decodeIfPresent(String.self, forKey: .tokenProgram)
    }
}
