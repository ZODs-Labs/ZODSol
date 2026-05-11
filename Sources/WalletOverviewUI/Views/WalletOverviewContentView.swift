import SwiftUI
import SolanaKit
import Formatters

struct WalletOverviewContentView: View {
    let viewModel: WalletOverviewViewModel
    let overview: WalletOverview
    let isPartial: Bool

    private let currencyFormatter = CurrencyFormatter()
    private let deltaFormatter = PercentageDeltaFormatter()

    private let displayCap = 12

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                if isPartial {
                    PartialDataBanner()
                }
                header
                hero
                AssetListSection(
                    rows: rows,
                    totalUSD: overview.totalUSD,
                    displayCap: displayCap
                )
                if !overview.nfts.isEmpty {
                    NFTSummaryCard(summary: overview.nfts)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 12)
        }
    }

    // MARK: - Header

    private var header: some View {
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
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.secondary)
                .frame(width: 22, height: 22)
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Refresh")
    }

    // MARK: - Hero

    private var hero: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(currencyFormatter.string(usd: overview.totalUSD ?? 0))
                .font(.system(size: 28, weight: .semibold))
                .tracking(-0.5)
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
                .font(.system(size: 10.5))
                .foregroundStyle(.secondary)
                .monospacedDigit()
            if overview.solBalance.rawValue > 0 {
                separator
                Text("~\(solLabel) SOL")
                    .font(.system(size: 10.5))
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }
            if let change = overview.totalChange24h {
                separator
                Text("\(deltaFormatter.string(change)) 24h")
                    .font(.system(size: 10.5, weight: .medium))
                    .foregroundStyle(deltaColor(change))
                    .monospacedDigit()
                    .contentTransition(.numericText())
            }
        }
    }

    private var separator: some View {
        Text("·")
            .font(.system(size: 10.5))
            .foregroundStyle(.tertiary)
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

    // MARK: - Helpers

    private var solLabel: String {
        let sol = Decimal(overview.solBalance.rawValue) / pow(Decimal(10), 9)
        return decimalShort(sol)
    }

    private func decimalShort(_ v: Decimal) -> String {
        let f = NumberFormatter()
        f.numberStyle = .decimal
        f.minimumFractionDigits = 0
        f.maximumFractionDigits = 2
        f.usesGroupingSeparator = true
        return f.string(from: v as NSDecimalNumber) ?? "\(v)"
    }

    private func deltaColor(_ delta: Double) -> Color {
        switch deltaFormatter.color(for: delta) {
        case .up: .green
        case .down: .red
        case .neutral: .secondary
        }
    }
}
