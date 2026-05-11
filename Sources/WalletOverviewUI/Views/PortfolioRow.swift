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
    let amount: TokenAmount
    let pricePerToken: Decimal?
    let usdValue: Decimal?
    let priceChange24h: Double?
    let isNative: Bool
}

extension PortfolioRow {
    static func from(_ asset: AssetSummary) -> PortfolioRow {
        PortfolioRow(
            id: asset.id.base58,
            symbol: asset.symbol ?? "—",
            name: asset.name,
            imageURL: asset.imageURL,
            amount: asset.amount,
            pricePerToken: asset.pricePerToken,
            usdValue: asset.usdValue,
            priceChange24h: asset.priceChange24h,
            isNative: false
        )
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
            isNative: true
        )
    }
}

extension Array where Element == PortfolioRow {
    /// USD-descending order, rows without a price slide to the bottom.
    func sortedByValue() -> [PortfolioRow] {
        sorted { a, b in
            switch (a.usdValue, b.usdValue) {
            case let (l?, r?): return l > r
            case (nil, _): return false
            case (_, nil): return true
            default: return false
            }
        }
    }
}
