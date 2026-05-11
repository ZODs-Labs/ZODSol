import SwiftUI
import SolanaKit
import Formatters

/// One row in the compact portfolio list. Single-line layout with tabular
/// figures throughout so the value column scans cleanly when amounts change.
struct AssetRowView: View {
    let row: PortfolioRow
    let share: Double

    private let amountFormatter = TokenAmountFormatter()
    private let currencyFormatter = CurrencyFormatter()
    private let deltaFormatter = PercentageDeltaFormatter()

    @State private var isHovered = false

    var body: some View {
        HStack(alignment: .center, spacing: 6) {
            icon
                .frame(width: 14, height: 14)

            Text(row.symbol)
                .font(.system(size: 11.5, weight: .medium))
                .foregroundStyle(.primary)
                .lineLimit(1)

            if let name = row.name, !name.isEmpty, name != row.symbol {
                Text(name)
                    .font(.system(size: 10.5))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .layoutPriority(-1)
            }

            Text(amountFormatter.string(row.amount, symbol: nil))
                .font(.system(size: 10.5))
                .monospacedDigit()
                .foregroundStyle(.secondary)
                .lineLimit(1)

            Text("×")
                .font(.system(size: 10.5))
                .foregroundStyle(.tertiary)

            Text(priceText)
                .font(.system(size: 10.5))
                .monospacedDigit()
                .foregroundStyle(.secondary)
                .lineLimit(1)

            Spacer(minLength: 6)

            Text(valueText)
                .font(.system(size: 11.5, weight: .semibold))
                .monospacedDigit()
                .foregroundStyle(hasValue ? .primary : .tertiary)
                .lineLimit(1)
                .contentTransition(.numericText())

            Text(shareText)
                .font(.system(size: 10.5))
                .monospacedDigit()
                .foregroundStyle(.secondary)
                .frame(width: 44, alignment: .trailing)
                .lineLimit(1)
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 3)
        .background(
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .fill(Color.primary.opacity(isHovered ? 0.05 : 0))
        )
        .contentShape(Rectangle())
        .onHover { isHovered = $0 }
        .accessibilityElement(children: .combine)
    }

    private var hasValue: Bool {
        guard let usd = row.usdValue else { return false }
        return usd > 0
    }

    private var valueText: String {
        guard let usd = row.usdValue, usd > 0 else { return "·" }
        return currencyFormatter.displayValue(usd: usd)
    }

    private var priceText: String {
        guard let price = row.pricePerToken else { return "·" }
        return currencyFormatter.priceUSD(price)
    }

    private var shareText: String {
        guard hasValue else { return "·" }
        return deltaFormatter.share(share)
    }

    @ViewBuilder
    private var icon: some View {
        if row.isNative {
            ZStack {
                RoundedRectangle(cornerRadius: 4, style: .continuous)
                    .fill(.secondary.opacity(0.18))
                Text("◎")
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(.secondary)
            }
        } else if let url = row.imageURL {
            AsyncImage(url: url) { phase in
                switch phase {
                case .success(let image):
                    image
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                case .empty, .failure:
                    placeholder
                @unknown default:
                    placeholder
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: 4, style: .continuous))
        } else {
            placeholder
        }
    }

    private var placeholder: some View {
        RoundedRectangle(cornerRadius: 4, style: .continuous)
            .fill(.secondary.opacity(0.18))
    }
}
