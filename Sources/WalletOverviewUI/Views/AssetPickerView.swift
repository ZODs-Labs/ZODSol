import Formatters
import SolanaKit
import SwiftUI
import WalletOverviewDomain

/// Sub-route that lists the wallet's priced holdings so the user can pick one
/// asset before continuing into either the send or receive flow. The screen
/// reuses the same priced filter the overview applies so the picker never
/// surfaces spam airdrops or zero-priced rows.
struct AssetPickerView: View {
    let intent: AssetPickerIntent
    @Bindable var viewModel: WalletOverviewViewModel
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        VStack(spacing: 0) {
            self.header
                .padding(.horizontal, 16)
                .padding(.top, 12)

            Divider()
                .padding(.vertical, 8)

            ScrollView {
                LazyVStack(spacing: 2) {
                    switch self.loadingState {
                    case .loading:
                        HStack {
                            Spacer()
                            ProgressView()
                            Spacer()
                        }
                        .padding(.vertical, 24)
                    case .failed:
                        Text("Could not load assets")
                            .font(.callout)
                            .foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity, alignment: .center)
                            .padding(.vertical, 24)
                    case .empty:
                        Text(self.emptyText)
                            .font(.callout)
                            .foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity, alignment: .center)
                            .padding(.vertical, 24)
                    case .ready:
                        ForEach(self.pickerRows) { row in
                            Button {
                                self.viewModel.handleAssetPicked(row)
                            } label: {
                                AssetPickerRow(row: row)
                            }
                            .buttonStyle(.plain)
                            .padding(.horizontal, 12)
                            .accessibilityLabel(self.accessibilityLabel(for: row))
                        }
                    }
                }
                .padding(.bottom, 12)
            }
        }
        .animation(self.reduceMotion ? nil : .default, value: self.pickerRows)
    }

    private enum LoadingDisplay {
        case loading
        case failed
        case empty
        case ready
    }

    private var loadingState: LoadingDisplay {
        switch self.viewModel.state {
        case .idle, .loading: .loading
        case .failed: .failed
        case .loaded, .partial: self.pickerRows.isEmpty ? .empty : .ready
        }
    }

    private var header: some View {
        HStack(spacing: 8) {
            Text(self.titleText)
                .font(.headline)
                .foregroundStyle(.primary)
            Spacer(minLength: 0)
            Button("Cancel") {
                self.cancel()
            }
            .buttonStyle(.borderless)
            .keyboardShortcut(.escape, modifiers: [])
            .accessibilityLabel("Cancel asset selection")
        }
    }

    private var titleText: String {
        switch self.intent.mode {
        case .send: "Send"
        case .receive: "Request"
        }
    }

    private var emptyText: String {
        "No assets with prices"
    }

    private func accessibilityLabel(for row: PortfolioRow) -> String {
        let action = switch self.intent.mode {
        case .send: "Send"
        case .receive: "Request"
        }
        return "\(action) \(row.symbol)"
    }

    /// Source of truth for the priced subset. Mirrors the inline filter in
    /// `WalletOverviewContentView.pricedRows` so the picker never diverges
    /// from what the overview chose to show.
    private var pickerRows: [PortfolioRow] {
        guard let overview = self.currentOverview else { return [] }
        var rows: [PortfolioRow] = []
        if overview.solBalance.rawValue > 0 {
            rows.append(.sol(
                balance: overview.solBalance,
                price: overview.solPriceUSD,
                change: overview.solChange24h))
        }
        rows.append(contentsOf: overview.tokens.map(PortfolioRow.from))
        return rows.sortedByValue().filter { row in
            if row.isNative { return true }
            guard let usd = row.usdValue else { return false }
            return usd > 0
        }
    }

    private var currentOverview: WalletOverview? {
        switch self.viewModel.state {
        case let .loaded(overview, _): overview
        case let .partial(overview, _): overview
        case .idle, .loading, .failed: nil
        }
    }

    private func cancel() {
        switch self.intent.mode {
        case .send:
            self.viewModel.route = .overview
        case let .receive(receiveIntent):
            self.viewModel.route = .receive(receiveIntent)
        }
    }
}

private struct AssetPickerRow: View {
    let row: PortfolioRow

    private let amountFormatter = TokenAmountFormatter(locale: Locale(identifier: "en_US"))
    private let currencyFormatter = CurrencyFormatter(locale: Locale(identifier: "en_US"))

    var body: some View {
        HStack(alignment: .center, spacing: 10) {
            self.icon
                .frame(width: 22, height: 22)

            VStack(alignment: .leading, spacing: 1) {
                Text(self.row.symbol)
                    .font(.callout.weight(.medium))
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                if let name = self.row.name, !name.isEmpty, name != self.row.symbol {
                    Text(name)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
            }

            Spacer(minLength: 8)

            VStack(alignment: .trailing, spacing: 1) {
                Text(self.amountFormatter.largeNumber(self.row.amount.uiAmount))
                    .font(.callout.weight(.semibold))
                    .foregroundStyle(.primary)
                    .monospacedDigit()
                    .lineLimit(1)
                Text(self.valueText)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
                    .lineLimit(1)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .fill(Color.primary.opacity(0)))
        .contentShape(Rectangle())
    }

    private var valueText: String {
        guard let usd = self.row.usdValue, usd > 0 else { return "·" }
        return self.currencyFormatter.displayValue(usd: usd)
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
        } else if let url = self.row.imageURL {
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
