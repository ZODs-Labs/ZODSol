import AppKit
import SwiftUI
import SolanaKit
import Formatters

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
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                headerRow
                    .padding(.bottom, 12)

                if let banner = viewModel.pendingSendBanner {
                    PendingSendBanner(
                        info: banner,
                        onTap: { viewModel.acknowledgePendingSend(banner) }
                    )
                    .padding(.bottom, 10)
                }

                hero

                Divider()
                    .padding(.vertical, 14)

                holdingsHeader
                    .padding(.bottom, 4)
                AssetListSection(
                    rows: pricedRows,
                    wallet: overview.address,
                    hiddenCount: hiddenCount,
                    totalUSD: overview.totalUSD,
                    displayCap: displayCap,
                    onSend: handleSend
                )

                if !overview.nfts.isEmpty {
                    Divider()
                        .padding(.vertical, 14)
                    nftsHeader
                        .padding(.bottom, 8)
                    NFTSummaryCard(summary: overview.nfts)
                }

                Divider()
                    .padding(.vertical, 14)

                footerLink
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
            sendButton
            receiveButton
            refreshButton
        }
    }

    private var sendButton: some View {
        Button {
            viewModel.handleHeaderSend()
        } label: {
            Image(systemName: "paperplane.fill")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.secondary)
                .frame(width: 24, height: 24)
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .keyboardShortcut("s", modifiers: .command)
        .help("Send (⌘S)")
        .accessibilityLabel("Send")
    }

    private var receiveButton: some View {
        Button {
            viewModel.handleHeaderReceive()
        } label: {
            Image(systemName: "qrcode")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.secondary)
                .frame(width: 24, height: 24)
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .keyboardShortcut("r", modifiers: [.command, .shift])
        .help("Receive (⌘⇧R)")
        .accessibilityLabel("Receive")
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
        .keyboardShortcut("r", modifiers: .command)
        .help("Refresh (⌘R)")
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
            NFTCountLink(count: overview.nfts.count, address: overview.address)
        }
    }

    // MARK: - Footer

    private var footerLink: some View {
        SolscanFooterLink(address: overview.address)
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

    // MARK: - Send

    private func handleSend(_ row: PortfolioRow) {
        guard let walletId = viewModel.activeWalletId else { return }
        let asset: SendAssetKind
        if row.isNative {
            asset = .sol
        } else {
            guard let mint = try? Mint(base58: row.id) else { return }
            asset = .splToken(
                mint: mint,
                decimals: row.amount.decimals,
                symbol: row.symbol,
                name: row.name
            )
        }
        viewModel.route = .send(SendIntent(
            walletId: walletId,
            from: overview.address,
            asset: asset
        ))
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
            Solscan.open(Solscan.nfts(address: address.base58))
        } label: {
            HStack(spacing: 4) {
                Text("\(count)")
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(isHovered ? .primary : .secondary)
                    .monospacedDigit()
                Image(systemName: "arrow.up.right")
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(isHovered ? .secondary : .tertiary)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
        .help("View collectibles on Solscan")
        .accessibilityLabel("\(count) collectibles, opens Solscan")
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
            Solscan.open(Solscan.account(address: address.base58))
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
                    .fill(Color.primary.opacity(isHovered ? 0.05 : 0))
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
        .help("Open this wallet on Solscan")
        .contextMenu {
            Button("Copy Wallet Address") {
                WalletPasteboard.copy(address.base58)
            }
            Button("Copy Solscan URL") {
                WalletPasteboard.copy(Solscan.account(address: address.base58).absoluteString)
            }
        }
    }
}
