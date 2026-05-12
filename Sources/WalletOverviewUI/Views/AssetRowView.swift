import AppKit
import Formatters
import SolanaKit
import SwiftUI

/// One row in the portfolio list, laid out like a native macOS menu-bar item:
/// 22pt icon · two-line label (symbol + name on top, balance × price below)
/// · right-aligned value and share. System dynamic-type sizes throughout so
/// the panel respects the user's text-size preference.
///
/// Click opens the Solscan target (token page for SPL, account page for
/// native SOL). Right-click reveals copy / open actions.
struct AssetRowView: View {
    let row: PortfolioRow
    let wallet: WalletAddress
    let share: Double

    private let amountFormatter = TokenAmountFormatter(locale: Locale(identifier: "en_US"))
    private let currencyFormatter = CurrencyFormatter(locale: Locale(identifier: "en_US"))
    private let deltaFormatter = PercentageDeltaFormatter(locale: Locale(identifier: "en_US"))

    @State private var isHovered = false

    var body: some View {
        HStack(alignment: .center, spacing: 10) {
            self.icon
                .frame(width: 22, height: 22)

            VStack(alignment: .leading, spacing: 1) {
                HStack(spacing: 6) {
                    Text(self.row.symbol)
                        .font(.callout.weight(.medium))
                        .foregroundStyle(.primary)
                        .lineLimit(1)
                    if let name = row.name, !name.isEmpty, name != row.symbol {
                        Text(name)
                            .font(.callout)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                            .truncationMode(.middle)
                            .layoutPriority(-1)
                    }
                }
                HStack(spacing: 4) {
                    Text(self.amountFormatter.largeNumber(self.row.amount.uiAmount))
                        .foregroundStyle(.secondary)
                    Text("×")
                        .foregroundStyle(.tertiary)
                    Text(self.priceText)
                        .foregroundStyle(.secondary)
                }
                .font(.caption)
                .monospacedDigit()
                .lineLimit(1)
            }

            Spacer(minLength: 8)

            VStack(alignment: .trailing, spacing: 1) {
                Text(self.valueText)
                    .font(.callout.weight(.semibold))
                    .foregroundStyle(self.hasValue ? .primary : .tertiary)
                    .monospacedDigit()
                    .contentTransition(.numericText())
                    .lineLimit(1)
                Text(self.shareText)
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
                .fill(Color.primary.opacity(self.isHovered ? 0.05 : 0)))
        .contentShape(Rectangle())
        .onHover { self.isHovered = $0 }
        .onTapGesture { Solscan.open(self.solscanURL) }
        .help(self.helpText)
        .contextMenu { self.contextMenu }
        .accessibilityElement(children: .combine)
        .accessibilityHint(Text(self.helpText))
        .accessibilityAddTraits(.isButton)
    }

    // MARK: - Interaction

    private var solscanURL: URL {
        if self.row.isNative {
            return Solscan.account(address: self.wallet.base58)
        }
        return Solscan.token(mint: self.row.id)
    }

    private var helpText: String {
        if self.row.isNative {
            return "View account on Solscan"
        }
        return "View \(self.row.symbol) on Solscan"
    }

    @ViewBuilder
    private var contextMenu: some View {
        Button("View on Solscan") {
            Solscan.open(self.solscanURL)
        }
        Divider()
        if self.row.isNative {
            Button("Copy Wallet Address") {
                WalletPasteboard.copy(self.wallet.base58)
            }
        } else {
            Button("Copy Mint Address") {
                WalletPasteboard.copy(self.row.id)
            }
        }
    }

    // MARK: - Formatting

    private var hasValue: Bool {
        guard let usd = row.usdValue else { return false }
        return usd > 0
    }

    private var valueText: String {
        guard let usd = row.usdValue, usd > 0 else { return "·" }
        return self.currencyFormatter.displayValue(usd: usd)
    }

    private var priceText: String {
        guard let price = row.pricePerToken else { return "·" }
        return self.currencyFormatter.priceUSD(price)
    }

    private var shareText: String {
        guard self.hasValue else { return "·" }
        return self.deltaFormatter.share(self.share)
    }

    @ViewBuilder
    private var icon: some View {
        if self.row.isNative {
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
                case let .success(image):
                    image
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                case .empty, .failure:
                    self.placeholder
                @unknown default:
                    self.placeholder
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: 5, style: .continuous))
        } else {
            self.placeholder
        }
    }

    private var placeholder: some View {
        RoundedRectangle(cornerRadius: 5, style: .continuous)
            .fill(.secondary.opacity(0.18))
    }
}
