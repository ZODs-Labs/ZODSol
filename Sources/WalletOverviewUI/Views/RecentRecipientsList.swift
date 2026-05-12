import Foundation
import SolanaKit
import SwiftUI
import WalletOverviewDomain

/// Compact list of recipients the user has previously sent to from this
/// wallet. Tapping a row fills the recipient field via
/// `consumeRecipientText`, so any validation rules apply just like a manual
/// paste. Hidden when the wallet has no recents yet.
struct RecentRecipientsList: View {
    @Bindable var viewModel: SendViewModel

    var body: some View {
        if self.viewModel.recents.isEmpty {
            EmptyView()
        } else {
            VStack(alignment: .leading, spacing: 4) {
                Text("Recent")
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.secondary)
                ForEach(Array(self.viewModel.recents.prefix(5))) { recent in
                    RecentRecipientRow(recent: recent) {
                        self.viewModel.consumeRecipientText(recent.address.base58)
                    }
                }
            }
        }
    }

    static func shorten(_ base58: String) -> String {
        guard base58.count > 12 else { return base58 }
        return "\(base58.prefix(4))…\(base58.suffix(4))"
    }

    static func relative(_ date: Date) -> String {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .abbreviated
        return formatter.localizedString(for: date, relativeTo: Date())
    }
}

private struct RecentRecipientRow: View {
    let recent: RecentRecipient
    let onTap: () -> Void

    @State private var isHovered = false

    var body: some View {
        Button(action: self.onTap) {
            HStack {
                Text(RecentRecipientsList.shorten(self.recent.address.base58))
                    .font(.system(.caption, design: .monospaced))
                    .foregroundStyle(.primary)
                Spacer(minLength: 8)
                Text(RecentRecipientsList.relative(self.recent.lastSentAt))
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 5)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(self.isHovered ? Color.accentColor.opacity(0.08) : Color.clear))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { self.isHovered = $0 }
        .accessibilityLabel("Recipient \(self.recent.address.base58)")
        .contextMenu {
            Button("Copy Address") {
                WalletPasteboard.copy(self.recent.address.base58)
            }
        }
    }
}

#if DEBUG

private actor PreviewNoopRecentService: SendAssetsService {
    func quote(_ request: SendRequest, tier: PriorityTier) async throws -> SendQuote {
        throw SendError.canceled
    }

    func send(quote: SendQuote) async throws -> SendOutcome {
        throw SendError.canceled
    }

    func resync(walletId: UUID) async -> [Signature: SendOutcome] { [:] }
}

@MainActor
private func makeRecentRecipientsPreviewVM(samples: [RecentRecipient]) -> SendViewModel {
    let address = try! WalletAddress(base58: "So11111111111111111111111111111111111111112")
    let intent = SendIntent(walletId: UUID(), from: address, asset: .sol)
    let vm = SendViewModel(
        intent: intent,
        cluster: .mainnet,
        service: PreviewNoopRecentService(),
        onDismiss: {})
    vm.recents = samples
    return vm
}

#Preview("Three recents") {
    let wallet = UUID()
    let now = Date()
    let samples = [
        RecentRecipient(
            walletId: wallet,
            address: try! WalletAddress(base58: "5x38Kp4hvdomTCnCrAny4UtMUt5rQBdB6px2K1Ui45Wq"),
            lastSentAt: now.addingTimeInterval(-3600)),
        RecentRecipient(
            walletId: wallet,
            address: try! WalletAddress(base58: "9WzDXwBbmkg8ZTbNMqUxvQRAyrZzDsGYdLVL9zYtAWWM"),
            lastSentAt: now.addingTimeInterval(-86_400)),
        RecentRecipient(
            walletId: wallet,
            address: try! WalletAddress(base58: "TokenkegQfeZyiNwAJbNbGKPFXCWuBvf9Ss623VQ5DA"),
            lastSentAt: now.addingTimeInterval(-7 * 86_400)),
    ]
    return RecentRecipientsList(viewModel: makeRecentRecipientsPreviewVM(samples: samples))
        .padding(16)
        .frame(width: 380)
}

#endif
