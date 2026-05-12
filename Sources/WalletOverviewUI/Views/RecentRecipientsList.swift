import Foundation
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
                    Button {
                        self.viewModel.consumeRecipientText(recent.address.base58)
                    } label: {
                        HStack {
                            Text(Self.shorten(recent.address.base58))
                                .font(.system(.caption, design: .monospaced))
                                .foregroundStyle(.primary)
                            Spacer(minLength: 8)
                            Text(Self.relative(recent.lastSentAt))
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                        .padding(.vertical, 3)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Recipient \(recent.address.base58)")
                }
            }
        }
    }

    private static func shorten(_ base58: String) -> String {
        guard base58.count > 12 else { return base58 }
        return "\(base58.prefix(4))…\(base58.suffix(4))"
    }

    private static func relative(_ date: Date) -> String {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .abbreviated
        return formatter.localizedString(for: date, relativeTo: Date())
    }
}
