import SwiftUI
import SolanaKit
import WalletOverviewDomain

/// Pure-value rendering model the `PendingSendBanner` view consumes. Split out
/// so tests can assert the icon/title/subtitle wiring without rendering the
/// SwiftUI view itself.
struct PendingSendBannerViewModel: Sendable, Equatable {
    let iconName: String
    let title: String
    let subtitle: String

    init(info: PendingSendDisplayInfo) {
        let shortSig = Self.shortened(info.signature.base58)
        switch info.outcome {
        case .confirmed:
            self.iconName = "checkmark.circle.fill"
            self.title = "Send confirmed"
            self.subtitle = shortSig
        case .expired:
            self.iconName = "clock.badge.exclamationmark.fill"
            self.title = "Send expired"
            self.subtitle = shortSig
        case .failed:
            self.iconName = "xmark.circle.fill"
            self.title = "Send failed"
            self.subtitle = shortSig
        }
    }

    /// Pending preview model: used when a non-terminal outcome appears here in
    /// a future revision of `SendOutcome`. Kept as a separate factory so the
    /// view code stays the same when that case is added.
    static func pendingPreview(signature: Signature) -> PendingSendBannerViewModel {
        PendingSendBannerViewModel(
            iconName: "clock.badge",
            title: "Confirming send...",
            subtitle: Self.shortened(signature.base58)
        )
    }

    private init(iconName: String, title: String, subtitle: String) {
        self.iconName = iconName
        self.title = title
        self.subtitle = subtitle
    }

    static func shortened(_ base58: String) -> String {
        guard base58.count > 8 else { return base58 }
        return "\(base58.prefix(4))...\(base58.suffix(4))"
    }
}

struct PendingSendBanner: View {
    let info: PendingSendDisplayInfo
    let onTap: () -> Void

    private var model: PendingSendBannerViewModel {
        PendingSendBannerViewModel(info: info)
    }

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 8) {
                Image(systemName: model.iconName)
                    .foregroundStyle(iconColor)
                VStack(alignment: .leading, spacing: 2) {
                    Text(model.title)
                        .font(.callout)
                        .foregroundStyle(.primary)
                    Text(model.subtitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                }
                Spacer(minLength: 0)
                Image(systemName: "chevron.right")
                    .foregroundStyle(.secondary)
                    .font(.caption.weight(.semibold))
            }
            .padding(10)
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(Color.accentColor.opacity(0.12))
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Text("\(model.title). \(model.subtitle)"))
    }

    private var iconColor: Color {
        switch info.outcome {
        case .confirmed: return .green
        case .failed: return .red
        case .expired: return .secondary
        }
    }
}
