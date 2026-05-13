import AppKit
import Formatters
import SolanaKit
import SwiftUI

/// Wallet portfolio surface laid out like a system menu-bar popover (battery,
/// volume, control center): a title row, a hero, hairline-separated sections
/// labelled with semibold subheadlines, and a footer link that goes to
/// Solscan - the same affordance "Battery Settings..." gives in the system
/// battery panel.
struct WalletOverviewContentView: View {
    let viewModel: WalletOverviewViewModel
    let overview: WalletOverview

    private let currencyFormatter = CurrencyFormatter(locale: Locale(identifier: "en_US"))
    private let deltaFormatter = PercentageDeltaFormatter(locale: Locale(identifier: "en_US"))
    private let amountFormatter = TokenAmountFormatter(locale: Locale(identifier: "en_US"))

    private let displayCap = 12

    var body: some View {
        MinimalScrollView {
            VStack(alignment: .leading, spacing: 0) {
                self.headerRow
                    .padding(.bottom, 12)

                if let banner = viewModel.pendingSendBanner {
                    PendingSendBanner(
                        info: banner,
                        onTap: { self.viewModel.acknowledgePendingSend(banner) })
                        .padding(.bottom, 10)
                }

                self.hero

                Divider()
                    .padding(.vertical, 14)

                self.holdingsHeader
                    .padding(.bottom, 4)
                AssetListSection(
                    rows: self.pricedRows,
                    wallet: self.overview.address,
                    hiddenCount: self.hiddenCount,
                    totalUSD: self.overview.totalUSD,
                    displayCap: self.displayCap)

                if !self.overview.nfts.isEmpty {
                    Divider()
                        .padding(.vertical, 14)
                    self.nftsHeader
                        .padding(.bottom, 8)
                    NFTSummaryCard(summary: self.overview.nfts)
                }

                Divider()
                    .padding(.vertical, 14)

                self.footerLink
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 14)
        }
    }

    // MARK: - Header

    private var headerRow: some View {
        HStack(spacing: 8) {
            WalletSwitcherChip(viewModel: self.viewModel)
            Spacer(minLength: 0)
            self.sendButton
            self.receiveButton
            self.refreshButton
        }
    }

    private var sendButton: some View {
        Button {
            self.viewModel.handleHeaderSend()
        } label: {
            Image(systemName: "paperplane.fill")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.secondary)
                .frame(width: 24, height: 24)
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .keyboardShortcut("s", modifiers: .command)
        .disabled(!self.viewModel.canSendOrReceive)
        .opacity(self.viewModel.canSendOrReceive ? 1.0 : 0.4)
        .help(self.viewModel.canSendOrReceive ? "Send (⌘S)" : "Waiting for wallet...")
        .accessibilityLabel("Send")
    }

    private var receiveButton: some View {
        Button {
            self.viewModel.handleHeaderReceive()
        } label: {
            Image(systemName: "qrcode")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.secondary)
                .frame(width: 24, height: 24)
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .keyboardShortcut("r", modifiers: [.command, .shift])
        .disabled(!self.viewModel.canSendOrReceive)
        .opacity(self.viewModel.canSendOrReceive ? 1.0 : 0.4)
        .help(self.viewModel.canSendOrReceive ? "Receive (⌘⇧R)" : "Waiting for wallet...")
        .accessibilityLabel("Receive")
    }

    private var refreshButton: some View {
        Button {
            Task { await self.viewModel.refresh() }
        } label: {
            Image(systemName: "arrow.clockwise")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.secondary)
                .frame(width: 24, height: 24)
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .keyboardShortcut("r", modifiers: .command)
        .help("Refresh (⌘R)")
        .accessibilityLabel("Refresh")
    }

    // MARK: - Hero

    private var hero: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(self.currencyFormatter.displayValue(usd: self.overview.totalUSD ?? 0))
                .font(.system(size: 30, weight: .bold))
                .tracking(-0.6)
                .monospacedDigit()
                .foregroundStyle(.primary)
                .contentTransition(.numericText())
                .lineLimit(1)
                .minimumScaleFactor(0.7)
                .padding(.bottom, 8)
            self.subtitle
            HStack(spacing: 0) {
                AddressView(address: self.overview.address, size: .metadata)
                Spacer(minLength: 0)
            }
            .padding(.top, 4)
        }
    }

    private var subtitle: some View {
        let holdingsCount = self.rows.count
        return HStack(spacing: 6) {
            Text("\(holdingsCount) holding\(holdingsCount == 1 ? "" : "s")")
                .font(.callout)
                .foregroundStyle(.secondary)
                .monospacedDigit()
            if self.overview.solBalance.rawValue > 0 {
                self.separator
                Text("~\(self.solLabel) SOL")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }
            if let change = overview.totalChange24h {
                self.separator
                Text("\(self.deltaFormatter.string(change)) 24h")
                    .font(.callout.weight(.medium))
                    .foregroundStyle(self.deltaColor(change))
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
            NFTCountLink(count: self.overview.nfts.count, address: self.overview.address)
        }
    }

    // MARK: - Footer

    private var footerLink: some View {
        SolscanFooterLink(address: self.overview.address)
    }

    // MARK: - Rows

    private var rows: [PortfolioRow] {
        var out: [PortfolioRow] = []
        if self.overview.solBalance.rawValue > 0 {
            out.append(.sol(
                balance: self.overview.solBalance,
                price: self.overview.solPriceUSD,
                change: self.overview.solChange24h))
        }
        out.append(contentsOf: self.overview.tokens.map(PortfolioRow.from))
        return out.sortedByValue()
    }

    /// Rows we actually render. Spam airdrops and brand-new tokens routinely
    /// carry no price (`usdValue` nil or zero) and dominate the list visually
    /// without contributing to portfolio value. Native SOL is always shown
    /// when present, even if the price feed is momentarily missing.
    private var pricedRows: [PortfolioRow] {
        self.rows.filter { row in
            if row.isNative { return true }
            guard let usd = row.usdValue else { return false }
            return usd > 0
        }
    }

    private var hiddenCount: Int {
        self.rows.count - self.pricedRows.count
    }

    // MARK: - Helpers

    private var solLabel: String {
        let sol = Decimal(overview.solBalance.rawValue) / pow(Decimal(10), 9)
        return self.amountFormatter.largeNumber(sol)
    }

    private func deltaColor(_ delta: Double) -> Color {
        switch self.deltaFormatter.color(for: delta) {
        case .up: .green
        case .down: .red
        case .neutral: .secondary
        }
    }
}

// MARK: - Solscan affordances

/// Right-aligned NFT count rendered as a quiet link to the wallet's
/// collectibles tab on Solscan. Hover lifts the count to primary so the
/// click affordance is obvious without the section getting visually noisy.
private struct NFTCountLink: View {
    let count: Int
    let address: WalletAddress
    @State private var isHovered = false

    var body: some View {
        Button {
            Solscan.open(Solscan.nfts(address: self.address.base58))
        } label: {
            HStack(spacing: 4) {
                Text("\(self.count)")
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(self.isHovered ? .primary : .secondary)
                    .monospacedDigit()
                Image(systemName: "arrow.up.right")
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(self.isHovered ? .secondary : .tertiary)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { self.isHovered = $0 }
        .help("View collectibles on Solscan")
        .accessibilityLabel("\(self.count) collectibles, opens Solscan")
    }
}

/// Footer-style external link, modelled on "Battery Settings…" in the
/// macOS Battery popover: subtle when at rest, hover-lifted background,
/// trailing arrow indicating the action leaves the app.
private struct SolscanFooterLink: View {
    let address: WalletAddress
    @State private var isHovered = false

    var body: some View {
        Button {
            Solscan.open(Solscan.account(address: self.address.base58))
        } label: {
            HStack(spacing: 6) {
                Text("View Account on Solscan")
                    .font(.callout)
                    .foregroundStyle(.primary)
                Spacer(minLength: 0)
                Image(systemName: "arrow.up.right")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 6)
            .padding(.vertical, 6)
            .frame(maxWidth: .infinity)
            .background(
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(Color.primary.opacity(self.isHovered ? 0.05 : 0)))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { self.isHovered = $0 }
        .help("Open this wallet on Solscan")
        .contextMenu {
            Button("Copy Wallet Address") {
                WalletPasteboard.copy(self.address.base58)
            }
            Button("Copy Solscan URL") {
                WalletPasteboard.copy(Solscan.account(address: self.address.base58).absoluteString)
            }
        }
    }
}
