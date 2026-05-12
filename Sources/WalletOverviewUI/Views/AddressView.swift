import AppKit
import SolanaKit
import SwiftUI

struct AddressView: View {
    enum Size: Sendable, Equatable {
        case compact
        case standard
        case prominent
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
        case .prominent:
            HStack(spacing: 8) {
                VStack(alignment: .leading, spacing: 2) {
                    if let caption = self.caption {
                        Text(caption).font(.caption).foregroundStyle(.secondary)
                    }
                    Text(self.address.base58)
                        .font(.system(.callout, design: .monospaced))
                        .foregroundStyle(self.foregroundColor)
                        .lineLimit(1)
                        .truncationMode(.middle)
                        .textSelection(.enabled)
                }
                Spacer(minLength: 0)
                self.iconView(size: 14)
                    .padding(6)
                    .background(
                        Circle()
                            .fill(self.copied ? Color.green.opacity(0.15) : Color.clear))
            }
            .padding(10)
            .background(self.background)
            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            .overlay(self.borderOverlay(cornerRadius: 10))
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

    private func borderOverlay(cornerRadius: CGFloat) -> some View {
        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
            .strokeBorder(Color(nsColor: .separatorColor), lineWidth: 0.5)
    }

    private func copyToPasteboard() {
        WalletPasteboard.copy(self.address.base58)
        NSHapticFeedbackManager.defaultPerformer.perform(.alignment, performanceTime: .now)
        self.copied = true
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(1.6))
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

#Preview("AddressView - prominent") {
    AddressView(
        address: try! WalletAddress(base58: "5x38Kp4hvdomTCnCrAny4UtMUt5rQBdB6px2K1Ui45Wq"),
        size: .prominent,
        caption: "Address")
        .padding(16)
        .frame(width: 380)
}

#endif
