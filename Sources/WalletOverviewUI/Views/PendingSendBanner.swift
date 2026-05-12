import SolanaKit
import SwiftUI
import WalletOverviewDomain

/// Pure-value rendering model the `PendingSendBanner` view consumes. Split out
/// so tests can assert the icon/title/subtitle wiring without rendering the
/// SwiftUI view itself.
struct PendingSendBannerViewModel: Equatable {
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
            subtitle: self.shortened(signature.base58))
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
        PendingSendBannerViewModel(info: self.info)
    }

    var body: some View {
        Button(action: self.onTap) {
            HStack(spacing: 8) {
                Image(systemName: self.model.iconName)
                    .foregroundStyle(self.iconColor)
                VStack(alignment: .leading, spacing: 2) {
                    Text(self.model.title)
                        .font(.callout)
                        .foregroundStyle(.primary)
                    Text(self.model.subtitle)
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
                    .fill(Color.accentColor.opacity(0.12)))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Text("\(self.model.title). \(self.model.subtitle)"))
    }

    private var iconColor: Color {
        switch self.info.outcome {
        case .confirmed: .green
        case .failed: .red
        case .expired: .secondary
        }
    }
}

#if DEBUG

private extension Signature {
    static var previewBytes: Signature {
        let bytes = Data(repeating: 0xAB, count: 64)
        return (try? Signature(bytes: bytes)) ?? Signature.preview
    }

    static var preview: Signature {
        try! Signature(bytes: Data(repeating: 0x01, count: 64))
    }
}

#Preview("Confirmed") {
    PendingSendBanner(
        info: PendingSendDisplayInfo(
            signature: .previewBytes,
            outcome: .confirmed(.previewBytes, slot: 247_198_023)),
        onTap: {})
        .padding(16)
        .frame(width: 380)
}

#Preview("Failed") {
    PendingSendBanner(
        info: PendingSendDisplayInfo(
            signature: .previewBytes,
            outcome: .failed(.previewBytes, error: "preflight failed")),
        onTap: {})
        .padding(16)
        .frame(width: 380)
}

#Preview("Expired") {
    PendingSendBanner(
        info: PendingSendDisplayInfo(
            signature: .previewBytes,
            outcome: .expired(.previewBytes)),
        onTap: {})
        .padding(16)
        .frame(width: 380)
}

#endif
