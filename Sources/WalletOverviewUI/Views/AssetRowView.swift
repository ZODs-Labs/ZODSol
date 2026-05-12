import SwiftUI
import SolanaKit
import Formatters

/// One row in the portfolio list, laid out like a native macOS menu-bar item:
/// 22pt icon · two-line label (symbol + name on top, balance × price below)
/// · right-aligned value and share. System dynamic-type sizes throughout so
/// the panel respects the user's text-size preference.
struct AssetRowView: View {
    let row: PortfolioRow
    let share: Double

    private let amountFormatter = TokenAmountFormatter(locale: Locale(identifier: "en_US"))
    private let currencyFormatter = CurrencyFormatter(locale: Locale(identifier: "en_US"))
    private let deltaFormatter = PercentageDeltaFormatter(locale: Locale(identifier: "en_US"))

    @State private var isHovered = false

    var body: some View {
        HStack(alignment: .center, spacing: 10) {
            icon
                .frame(width: 22, height: 22)

            VStack(alignment: .leading, spacing: 1) {
                HStack(spacing: 6) {
                    Text(row.symbol)
                        .font(.callout.weight(.medium))
                        .foregroundStyle(.primary)
                        .lineLimit(1)
                    if let name = row.name, !name.isEmpty, name != row.symbol {
                        Text(name)
                            .font(.callout)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                            .layoutPriority(-1)
                    }
                }
                HStack(spacing: 4) {
                    Text(amountFormatter.largeNumber(row.amount.uiAmount))
                        .foregroundStyle(.secondary)
                    Text("×")
                        .foregroundStyle(.tertiary)
                    Text(priceText)
                        .foregroundStyle(.secondary)
                }
                .font(.caption)
                .monospacedDigit()
                .lineLimit(1)
            }

            Spacer(minLength: 8)

            VStack(alignment: .trailing, spacing: 1) {
                Text(valueText)
                    .font(.callout.weight(.semibold))
                    .foregroundStyle(hasValue ? .primary : .tertiary)
                    .monospacedDigit()
                    .contentTransition(.numericText())
                    .lineLimit(1)
                Text(shareText)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
                    .lineLimit(1)
            }
        }
        .padding(.horizontal, 4)
        .padding(.vertical, 6)
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
                RoundedRectangle(cornerRadius: 5, style: .continuous)
                    .fill(.secondary.opacity(0.18))
                Text("◎")
                    .font(.system(size: 12, weight: .semibold))
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
            .clipShape(RoundedRectangle(cornerRadius: 5, style: .continuous))
        } else {
            placeholder
        }
    }

    private var placeholder: some View {
        RoundedRectangle(cornerRadius: 5, style: .continuous)
            .fill(.secondary.opacity(0.18))
    }
}
