import SwiftUI
import WalletOverviewDomain

/// Inline manage-wallets screen — replaces the previous `.sheet`. Reached by
/// tapping Manage in the switcher. Supports add (navigates to addWallet
/// route), rename (navigates to rename route), and delete (confirmation alert
/// kept inline — alerts attach to the panel window itself and are safe).
struct ManageWalletsView: View {
    let viewModel: WalletOverviewViewModel

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var pendingDeletion: WalletIdentity?

    var body: some View {
        VStack(spacing: 0) {
            navBar
            Divider().opacity(0.4)
            content
            Divider().opacity(0.4)
            footer
        }
        .alert(item: $pendingDeletion) { wallet in
            Alert(
                title: Text("Delete “\(wallet.label)”?"),
                message: Text("The signing key and wallet address will be removed from this Mac."),
                primaryButton: .destructive(Text("Delete")) {
                    Task { await viewModel.removeWallet(wallet.id) }
                },
                secondaryButton: .cancel()
            )
        }
    }

    // MARK: - Nav bar

    private var navBar: some View {
        HStack(spacing: 6) {
            Button(action: back) {
                HStack(spacing: 4) {
                    Image(systemName: "chevron.left")
                    Text("Wallets")
                }
                .font(.callout)
                .foregroundStyle(.primary)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Back to wallets")

            Spacer()

            Text("Manage")
                .font(.headline)
                .foregroundStyle(.primary)

            Spacer()

            Color.clear.frame(width: 70, height: 1)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
    }

    // MARK: - Content

    @ViewBuilder
    private var content: some View {
        if viewModel.wallets.isEmpty {
            emptyState
        } else {
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
    }

    private func row(for wallet: WalletIdentity) -> some View {
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
            Menu {
                Button("Rename…") { startRename(wallet) }
                Button("Delete", role: .destructive) { pendingDeletion = wallet }
            } label: {
                Image(systemName: "ellipsis.circle")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
            .menuStyle(.borderlessButton)
            .frame(width: 32)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .contentShape(Rectangle())
    }

    private var emptyState: some View {
        VStack(spacing: 6) {
            Image(systemName: "tray")
                .font(.system(size: 22, weight: .regular))
                .foregroundStyle(.secondary)
            Text("No wallets yet")
                .font(.callout)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Footer

    private var footer: some View {
        Button(action: openAddWallet) {
            HStack(spacing: 8) {
                Image(systemName: "plus.circle.fill")
                Text("Add wallet")
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
            viewModel.route = .switcher
        }
    }

    private func startRename(_ wallet: WalletIdentity) {
        withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.22)) {
            viewModel.route = .rename(walletId: wallet.id)
        }
    }

    private func openAddWallet() {
        withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.22)) {
            viewModel.route = .addWallet
        }
    }
}
