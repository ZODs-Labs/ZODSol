import Foundation
import SolanaKit

/// Flat row model used by the compact portfolio list. Decouples the view
/// from `AssetSummary` so native SOL can sit in the same sorted list as the
/// SPL tokens.
struct PortfolioRow: Identifiable, Equatable {
    let id: String
    let symbol: String
    let name: String?
    let imageURL: URL?
    let imageURLAlternates: [URL]
    let amount: TokenAmount
    let pricePerToken: Decimal?
    let usdValue: Decimal?
    let priceChange24h: Double?
    let isNative: Bool
    /// Discriminator for the token's owning program (used to derive the
    /// recipient ATA). `nil` for native SOL.
    let tokenProgram: String?

    init(
        id: String,
        symbol: String,
        name: String?,
        imageURL: URL?,
        imageURLAlternates: [URL] = [],
        amount: TokenAmount,
        pricePerToken: Decimal?,
        usdValue: Decimal?,
        priceChange24h: Double?,
        isNative: Bool,
        tokenProgram: String?)
    {
        self.id = id
        self.symbol = symbol
        self.name = name
        self.imageURL = imageURL
        self.imageURLAlternates = imageURLAlternates
        self.amount = amount
        self.pricePerToken = pricePerToken
        self.usdValue = usdValue
        self.priceChange24h = priceChange24h
        self.isNative = isNative
        self.tokenProgram = tokenProgram
    }
}

extension PortfolioRow {
    static func from(_ asset: AssetSummary) -> PortfolioRow {
        PortfolioRow(
            id: asset.id.base58,
            symbol: asset.symbol ?? "—",
            name: asset.name,
            imageURL: asset.imageURL,
            imageURLAlternates: asset.imageURLAlternates,
            amount: asset.amount,
            pricePerToken: asset.pricePerToken,
            usdValue: asset.usdValue,
            priceChange24h: asset.priceChange24h,
            isNative: false,
            tokenProgram: asset.tokenProgram)
    }

    static func sol(balance: Lamports, price: Decimal?, change: Double?) -> PortfolioRow {
        let amount = TokenAmount(amount: balance.rawValue, decimals: 9)
        let usd: Decimal? = price.map { amount.uiAmount * $0 }
        return PortfolioRow(
            id: "native",
            symbol: "SOL",
            name: "Solana",
            imageURL: nil,
            amount: amount,
            pricePerToken: price,
            usdValue: usd,
            priceChange24h: change,
            isNative: true,
            tokenProgram: nil)
    }
}

extension [PortfolioRow] {
    /// USD-descending order, rows without a price slide to the bottom.
    func sortedByValue() -> [PortfolioRow] {
        sorted { a, b in
            switch (a.usdValue, b.usdValue) {
            case let (l?, r?): l > r
            case (nil, _): false
            case (_, nil): true
            default: false
            }
        }
    }
}
