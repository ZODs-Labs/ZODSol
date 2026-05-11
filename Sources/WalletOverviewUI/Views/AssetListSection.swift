import SwiftUI

/// Flat, chromeless list of compact portfolio rows. Caps at `displayCap`
/// holdings; the remainder collapses to a tail counter so the panel stays
/// short and the list never scrolls past the popover edge.
struct AssetListSection: View {
    let rows: [PortfolioRow]
    let totalUSD: Decimal?
    var displayCap: Int = 12

    var body: some View {
        if rows.isEmpty {
            Text("No holdings")
                .font(.system(size: 11.5))
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 6)
                .padding(.vertical, 8)
        } else {
            VStack(alignment: .leading, spacing: 0) {
                ForEach(visible) { row in
                    AssetRowView(row: row, share: share(for: row))
                }
                if overflow > 0 {
                    Text("+ \(overflow) smaller")
                        .font(.system(size: 10.5))
                        .monospacedDigit()
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 6)
                        .padding(.top, 2)
                }
            }
        }
    }

    private var visible: [PortfolioRow] {
        Array(rows.prefix(displayCap))
    }

    private var overflow: Int {
        max(0, rows.count - visible.count)
    }

    private func share(for row: PortfolioRow) -> Double {
        guard let total = totalUSD,
              total > 0,
              let usd = row.usdValue else { return 0 }
        let ratio = (usd / total) * 100
        return NSDecimalNumber(decimal: ratio).doubleValue
    }
}
