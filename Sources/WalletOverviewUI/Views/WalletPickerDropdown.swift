import AppKit
import SolanaKit
import SwiftUI
import WalletOverviewDomain

/// Domain-specific dropdown wired on top of `SelectMenu`. Surfaces the user's
/// other ZODSol wallets as recipient suggestions; mounted by `SendInputView`
/// as an overlay anchored under `RecipientField` so opening it never reflows
/// the surrounding form.
struct WalletPickerDropdown: View {
    let isOpen: Bool
    let wallets: [WalletIdentity]
    let onSelect: (WalletIdentity) -> Void

    var body: some View {
        SelectMenu(
            isOpen: self.isOpen,
            items: self.wallets,
            maxVisibleHeight: 184,
            onSelect: self.onSelect,
            row: { wallet, isHighlighted in
                WalletPickerRow(wallet: wallet, isHighlighted: isHighlighted)
            },
            header: { WalletPickerHeader(count: self.wallets.count) })
    }
}

private struct WalletPickerHeader: View {
    let count: Int

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: "wallet.pass.fill")
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(.secondary)
            Text("Your wallets")
                .font(.caption.weight(.medium))
                .foregroundStyle(.secondary)
            Spacer(minLength: 0)
            Text("\(self.count)")
                .font(.caption2.monospacedDigit())
                .foregroundStyle(AnyShapeStyle(.tertiary))
        }
        .padding(.horizontal, 10)
        .padding(.top, 8)
        .padding(.bottom, 6)
    }
}

private struct WalletPickerRow: View {
    let wallet: WalletIdentity
    let isHighlighted: Bool

    var body: some View {
        HStack(spacing: 10) {
            self.avatar
            VStack(alignment: .leading, spacing: 1) {
                Text(self.wallet.label)
                    .font(.callout.weight(.medium))
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                    .truncationMode(.tail)
                Text(self.wallet.address.shortened(prefix: 6, suffix: 6))
                    .font(.system(.caption, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Spacer(minLength: 8)
            Image(systemName: "arrow.up.right")
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(self.isHighlighted
                    ? AnyShapeStyle(Color.accentColor)
                    : AnyShapeStyle(.tertiary))
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .fill(self.isHighlighted
                    ? Color(nsColor: .selectedContentBackgroundColor).opacity(0.22)
                    : Color.clear))
        .padding(.horizontal, 4)
        .padding(.vertical, 1)
        .contentShape(Rectangle())
        .accessibilityLabel("Send to \(self.wallet.label), \(self.wallet.address.base58)")
    }

    private var avatar: some View {
        ZStack {
            Circle()
                .fill(LinearGradient(
                    colors: [
                        Color.accentColor.opacity(0.65),
                        Color.accentColor.opacity(0.32),
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing))
            Text(self.initials)
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.white)
        }
        .frame(width: 22, height: 22)
        .overlay(
            Circle().strokeBorder(Color.white.opacity(0.20), lineWidth: 0.5))
    }

    private var initials: String {
        let trimmed = self.wallet.label.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return "•" }
        let parts = trimmed.split(separator: " ").prefix(2)
        let chars = parts.compactMap(\.first).map { String($0) }
        return chars.joined().uppercased()
    }
}

#if DEBUG

private func walletPickerPreviewWallets(count: Int) -> [WalletIdentity] {
    let bases = [
        "5x38Kp4hvdomTCnCrAny4UtMUt5rQBdB6px2K1Ui45Wq",
        "9WzDXwBbmkg8ZTbNMqUxvQRAyrZzDsGYdLVL9zYtAWWM",
        "EPjFWdd5AufqSSqeM2qN1xzybapC8G4wEGGkZwyTDt1v",
    ]
    let labels = ["Main", "Trading", "Cold Storage", "Hot Spend", "Vault", "Trial", "Hardware", "Test"]
    return (0..<count).map { idx in
        WalletIdentity(
            id: UUID(),
            address: try! WalletAddress(base58: bases[idx % bases.count]),
            label: labels[idx % labels.count],
            createdAt: Date())
    }
}

#Preview("Three wallets") {
    WalletPickerDropdown(
        isOpen: true,
        wallets: walletPickerPreviewWallets(count: 3),
        onSelect: { _ in })
        .padding(16)
        .frame(width: 360)
        .background(Color(nsColor: .windowBackgroundColor))
}

#Preview("Many wallets - scrolls") {
    WalletPickerDropdown(
        isOpen: true,
        wallets: walletPickerPreviewWallets(count: 8),
        onSelect: { _ in })
        .padding(16)
        .frame(width: 360)
        .background(Color(nsColor: .windowBackgroundColor))
}

#endif
