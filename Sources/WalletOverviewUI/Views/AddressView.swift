import AppKit
import SolanaKit
import SwiftUI

struct AddressView: View {
    enum Size: Sendable, Equatable {
        case compact
        case standard
        case metadata
    }

    let address: WalletAddress
    let size: Size
    let caption: String?

    @State private var copied: Bool = false
    @State private var hovered: Bool = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    init(address: WalletAddress, size: Size = .standard, caption: String? = nil) {
        self.address = address
        self.size = size
        self.caption = caption
    }

    var body: some View {
        Button(action: self.copyToPasteboard) {
            self.content
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            self.hovered = hovering
            if hovering {
                NSCursor.pointingHand.push()
            } else {
                NSCursor.pop()
            }
        }
        .accessibilityLabel(self.copied
            ? "Address copied to clipboard"
            : "Copy address \(self.address.base58)")
        .help(self.copied ? "Copied" : self.address.base58)
        .draggable(self.address.base58)
        .animation(self.reduceMotion ? nil : .spring(response: 0.3, dampingFraction: 0.7), value: self.copied)
        .animation(self.reduceMotion ? nil : .easeInOut(duration: 0.15), value: self.hovered)
    }

    @ViewBuilder
    private var content: some View {
        switch self.size {
        case .compact:
            HStack(spacing: 4) {
                Text(self.shortAddress)
                    .font(.system(.caption, design: .monospaced))
                    .foregroundStyle(self.foregroundColor)
                self.iconView(size: 10)
            }
            .padding(.horizontal, 6)
            .padding(.vertical, 3)
            .background(self.background)
            .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
        case .standard:
            HStack(spacing: 6) {
                if let caption = self.caption {
                    Text(caption).font(.caption).foregroundStyle(.secondary)
                }
                Text(self.shortAddress)
                    .font(.system(.callout, design: .monospaced))
                    .foregroundStyle(self.foregroundColor)
                self.iconView(size: 12)
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 6)
            .background(self.background)
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            .overlay(self.borderOverlay(cornerRadius: 8))
        case .metadata:
            HStack(spacing: 4) {
                Text(self.address.shortened())
                    .font(.system(.caption, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
                    .lineLimit(1)
                    .truncationMode(.middle)
                Image(systemName: self.copied ? "checkmark" : "doc.on.doc")
                    .font(.system(size: 9, weight: .medium))
                    .foregroundStyle(self.copied ? Color.green : Color.secondary)
                    .contentTransition(.symbolEffect(.replace.byLayer))
                    .symbolEffect(.bounce, value: self.copied)
                    .opacity(self.copied || self.hovered ? 1.0 : 0.0)
                    .animation(self.reduceMotion ? nil : .easeInOut(duration: 0.15), value: self.hovered)
            }
            .padding(.horizontal, 4)
            .padding(.vertical, 2)
            .background(
                RoundedRectangle(cornerRadius: 4, style: .continuous)
                    .fill(self.metadataBackground))
        }
    }

    private func iconView(size: CGFloat) -> some View {
        Image(systemName: self.copied ? "checkmark" : "doc.on.doc")
            .font(.system(size: size, weight: .medium))
            .foregroundStyle(self.copied ? Color.green : Color.secondary)
            .contentTransition(.symbolEffect(.replace.byLayer))
            .symbolEffect(.bounce, value: self.copied)
    }

    private var shortAddress: String {
        self.address.shortened()
    }

    private var foregroundColor: Color {
        self.copied ? Color.green : Color.primary
    }

    @ViewBuilder
    private var background: some View {
        if self.copied {
            Color.green.opacity(0.12)
        } else if self.hovered {
            Color.accentColor.opacity(0.08)
        } else {
            Color(nsColor: .quaternaryLabelColor).opacity(0.5)
        }
    }

    private var metadataBackground: Color {
        if self.copied {
            Color.green.opacity(0.10)
        } else if self.hovered {
            Color(nsColor: .quaternaryLabelColor).opacity(0.6)
        } else {
            Color.clear
        }
    }

    private func borderOverlay(cornerRadius: CGFloat) -> some View {
        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
            .strokeBorder(Color(nsColor: .separatorColor), lineWidth: 0.5)
    }

    private func copyToPasteboard() {
        WalletPasteboard.copy(self.address.base58)
        NSHapticFeedbackManager.defaultPerformer.perform(.alignment, performanceTime: .now)
        self.copied = true
        let hold: Duration = self.size == .metadata ? .milliseconds(600) : .seconds(1.6)
        Task { @MainActor in
            try? await Task.sleep(for: hold)
            self.copied = false
        }
    }
}

#if DEBUG

#Preview("AddressView - compact") {
    AddressView(
        address: try! WalletAddress(base58: "5x38Kp4hvdomTCnCrAny4UtMUt5rQBdB6px2K1Ui45Wq"),
        size: .compact)
        .padding(16)
        .frame(width: 220)
}

#Preview("AddressView - standard") {
    AddressView(
        address: try! WalletAddress(base58: "5x38Kp4hvdomTCnCrAny4UtMUt5rQBdB6px2K1Ui45Wq"),
        size: .standard,
        caption: "To")
        .padding(16)
        .frame(width: 320)
}

#Preview("AddressView - metadata") {
    VStack(alignment: .leading, spacing: 6) {
        Text("Wallet 1").font(.subheadline.weight(.semibold))
        AddressView(
            address: try! WalletAddress(base58: "5x38Kp4hvdomTCnCrAny4UtMUt5rQBdB6px2K1Ui45Wq"),
            size: .metadata)
    }
    .padding(16)
    .frame(width: 380, alignment: .leading)
}

#endif
