import SwiftUI
import WalletOverviewDomain

/// A pill at the top of the overview that names the active wallet. Tapping it
/// navigates the panel to the switcher route — Apple's Control Center pattern.
/// No popover or sheet, so clicks never spawn a separate NSWindow that the
/// status item's event monitor would treat as outside-the-panel.
struct WalletSwitcherChip: View {
    let viewModel: WalletOverviewViewModel
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        Button(action: openSwitcher) {
            HStack(spacing: 8) {
                Circle()
                    .fill(.tint)
                    .frame(width: 8, height: 8)
                if let identity = currentIdentity {
                    Text(identity.label)
                        .font(.callout.weight(.medium))
                        .foregroundStyle(.primary)
                        .lineLimit(1)
                    Text(identity.address.shortened())
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                } else {
                    Text("No wallet")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
                Image(systemName: "chevron.up.chevron.down")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(.ultraThinMaterial, in: Capsule(style: .continuous))
            .overlay(Capsule(style: .continuous).strokeBorder(.secondary.opacity(0.15), lineWidth: 0.5))
            .contentShape(Capsule(style: .continuous))
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Switch wallet")
    }

    private func openSwitcher() {
        withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.22)) {
            viewModel.route = .switcher
        }
    }

    private var currentIdentity: WalletIdentity? {
        guard let activeId = viewModel.activeWalletId else { return nil }
        return viewModel.wallets.first { $0.id == activeId }
    }
}
