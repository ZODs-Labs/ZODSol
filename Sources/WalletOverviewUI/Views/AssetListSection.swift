import SwiftUI

/// Flat, chromeless list of compact portfolio rows. Caps at `displayCap`
/// holdings; the remainder (plus any unpriced spam tokens passed in
/// `hiddenCount`) collapses to a single tail counter so the panel stays
/// short and the list never scrolls past the popover edge.
struct AssetListSection: View {
    let rows: [PortfolioRow]
    var hiddenCount: Int = 0
    let totalUSD: Decimal?
    var displayCap: Int = 12

    var body: some View {
        if rows.isEmpty && hiddenCount == 0 {
            Text("No holdings")
                .font(.callout)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.vertical, 6)
        } else {
            VStack(alignment: .leading, spacing: 0) {
                ForEach(visible) { row in
                    AssetRowView(row: row, share: share(for: row))
                }
                if overflow > 0 {
                    Text("+ \(overflow) smaller")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 4)
                        .padding(.top, 6)
                }
            }
        }
    }

    private var visible: [PortfolioRow] {
        Array(rows.prefix(displayCap))
    }

    private var overflow: Int {
        max(0, rows.count - visible.count) + hiddenCount
    }

    private func share(for row: PortfolioRow) -> Double {
        guard let total = totalUSD,
              total > 0,
              let usd = row.usdValue else { return 0 }
        let ratio = (usd / total) * 100
        return NSDecimalNumber(decimal: ratio).doubleValue
    }
}
