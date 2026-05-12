import SwiftUI
import SolanaKit
import Formatters

/// Wallet portfolio surface laid out like a system menu-bar popover (battery,
/// volume, control center): a title row, a hero, hairline-separated sections
/// labelled with semibold subheadlines, and content that uses SF dynamic-type
/// sizes so it tracks the user's text-size preference.
struct WalletOverviewContentView: View {
    let viewModel: WalletOverviewViewModel
    let overview: WalletOverview

    private let currencyFormatter = CurrencyFormatter(locale: Locale(identifier: "en_US"))
    private let deltaFormatter = PercentageDeltaFormatter(locale: Locale(identifier: "en_US"))
    private let amountFormatter = TokenAmountFormatter(locale: Locale(identifier: "en_US"))

    private let displayCap = 12

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                headerRow
                    .padding(.bottom, 12)

                hero

                Divider()
                    .padding(.vertical, 14)

                holdingsHeader
                    .padding(.bottom, 4)
                AssetListSection(
                    rows: pricedRows,
                    hiddenCount: hiddenCount,
                    totalUSD: overview.totalUSD,
                    displayCap: displayCap
                )

                if !overview.nfts.isEmpty {
                    Divider()
                        .padding(.vertical, 14)
                    nftsHeader
                        .padding(.bottom, 8)
                    NFTSummaryCard(summary: overview.nfts)
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 14)
        }
    }

    // MARK: - Header

    private var headerRow: some View {
        HStack(spacing: 8) {
            WalletSwitcherChip(viewModel: viewModel)
            Spacer(minLength: 0)
            refreshButton
        }
    }

    private var refreshButton: some View {
        Button {
            Task { await viewModel.refresh() }
        } label: {
            Image(systemName: "arrow.clockwise")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.secondary)
                .frame(width: 24, height: 24)
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Refresh")
    }

    // MARK: - Hero

    private var hero: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(currencyFormatter.displayValue(usd: overview.totalUSD ?? 0))
                .font(.system(size: 30, weight: .bold))
                .tracking(-0.6)
                .monospacedDigit()
                .foregroundStyle(.primary)
                .contentTransition(.numericText())
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            subtitle
        }
    }

    private var subtitle: some View {
        let holdingsCount = rows.count
        return HStack(spacing: 6) {
            Text("\(holdingsCount) holding\(holdingsCount == 1 ? "" : "s")")
                .font(.callout)
                .foregroundStyle(.secondary)
                .monospacedDigit()
            if overview.solBalance.rawValue > 0 {
                separator
                Text("~\(solLabel) SOL")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }
            if let change = overview.totalChange24h {
                separator
                Text("\(deltaFormatter.string(change)) 24h")
                    .font(.callout.weight(.medium))
                    .foregroundStyle(deltaColor(change))
                    .monospacedDigit()
                    .contentTransition(.numericText())
            }
        }
    }

    private var separator: some View {
        Text("·")
            .font(.callout)
            .foregroundStyle(.tertiary)
    }

    // MARK: - Section headers

    private var holdingsHeader: some View {
        Text("Holdings")
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(.primary)
    }

    private var nftsHeader: some View {
        HStack(spacing: 6) {
            Text("NFTs")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.primary)
            Spacer()
            Text("\(overview.nfts.count)")
                .font(.subheadline.weight(.medium))
                .foregroundStyle(.secondary)
                .monospacedDigit()
        }
    }

    // MARK: - Rows

    private var rows: [PortfolioRow] {
        var out: [PortfolioRow] = []
        if overview.solBalance.rawValue > 0 {
            out.append(.sol(
                balance: overview.solBalance,
                price: overview.solPriceUSD,
                change: overview.solChange24h
            ))
        }
        out.append(contentsOf: overview.tokens.map(PortfolioRow.from))
        return out.sortedByValue()
    }

    /// Rows we actually render. Spam airdrops and brand-new tokens routinely
    /// carry no price (`usdValue` nil or zero) and dominate the list visually
    /// without contributing to portfolio value. Native SOL is always shown
    /// when present, even if the price feed is momentarily missing.
    private var pricedRows: [PortfolioRow] {
        rows.filter { row in
            if row.isNative { return true }
            guard let usd = row.usdValue else { return false }
            return usd > 0
        }
    }

    private var hiddenCount: Int {
        rows.count - pricedRows.count
    }

    // MARK: - Helpers

    private var solLabel: String {
        let sol = Decimal(overview.solBalance.rawValue) / pow(Decimal(10), 9)
        return amountFormatter.largeNumber(sol)
    }

    private func deltaColor(_ delta: Double) -> Color {
        switch deltaFormatter.color(for: delta) {
        case .up: .green
        case .down: .red
        case .neutral: .secondary
        }
    }
}
