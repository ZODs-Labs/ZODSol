import SwiftUI
import WalletOverviewDomain

/// Inline switcher screen — replaces the previous `.popover`. The whole panel
/// is the switcher while this route is active. A header with a back chevron
/// returns to the overview. A "Manage" entry navigates deeper to the manage
/// route. No child windows are ever created.
struct WalletSwitcherView: View {
    let viewModel: WalletOverviewViewModel
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        VStack(spacing: 0) {
            navBar
            Divider().opacity(0.4)
            list
            Divider().opacity(0.4)
            footer
        }
    }

    // MARK: - Nav bar

    private var navBar: some View {
        HStack(spacing: 6) {
            Button(action: back) {
                HStack(spacing: 4) {
                    Image(systemName: "chevron.left")
                    Text("Overview")
                }
                .font(.callout)
                .foregroundStyle(.primary)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Back to overview")

            Spacer()

            Text("Wallets")
                .font(.headline)
                .foregroundStyle(.primary)

            Spacer()

            // Symmetric placeholder for visual balance with the back button.
            Color.clear.frame(width: 70, height: 1)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
    }

    // MARK: - List

    private var list: some View {
        ScrollView {
            LazyVStack(spacing: 0) {
                ForEach(viewModel.wallets) { wallet in
                    row(for: wallet)
                    if wallet.id != viewModel.wallets.last?.id {
                        Divider().padding(.leading, 16).opacity(0.35)
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }

    private func row(for wallet: WalletIdentity) -> some View {
        Button(action: { select(wallet) }) {
            HStack(spacing: 10) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(wallet.label)
                        .font(.callout.weight(.medium))
                        .foregroundStyle(.primary)
                        .lineLimit(1)
                    Text(wallet.address.shortened())
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                Spacer()
                if wallet.id == viewModel.activeWalletId {
                    Image(systemName: "checkmark")
                        .font(.callout.weight(.semibold))
                        .foregroundStyle(.tint)
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    // MARK: - Footer

    private var footer: some View {
        Button(action: openManage) {
            HStack(spacing: 8) {
                Image(systemName: "slider.horizontal.3")
                Text("Manage wallets")
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            .font(.callout)
            .foregroundStyle(.primary)
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    // MARK: - Actions

    private func back() {
        withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.22)) {
            viewModel.route = .overview
        }
    }

    private func openManage() {
        withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.22)) {
            viewModel.route = .manage
        }
    }

    private func select(_ wallet: WalletIdentity) {
        Task {
            await viewModel.selectWallet(wallet.id)
        }
    }
}
