import AppKit
import SwiftUI

struct CopyButton: View {
    enum Style: Sendable, Equatable {
        case icon
        case iconLabel
        case prominent
    }

    let text: String
    let label: String
    let style: Style
    let onCopy: (@MainActor () -> Void)?

    @State private var copied: Bool = false
    @State private var hovered: Bool = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    init(
        text: String,
        label: String = "Copy",
        style: Style = .icon,
        onCopy: (@MainActor () -> Void)? = nil
    ) {
        self.text = text
        self.label = label
        self.style = style
        self.onCopy = onCopy
    }

    var body: some View {
        Group {
            if self.style == .prominent {
                Button(action: self.copyToPasteboard) { self.content }
                    .buttonStyle(.bordered)
            } else {
                Button(action: self.copyToPasteboard) { self.content }
                    .buttonStyle(.borderless)
            }
        }
        .accessibilityLabel(self.copied ? "Copied" : "Copy \(self.label.lowercased())")
        .help(self.copied ? "Copied" : "Copy")
        .onHover { hovering in
            self.hovered = hovering
            if hovering {
                NSCursor.pointingHand.push()
            } else {
                NSCursor.pop()
            }
        }
    }

    @ViewBuilder
    private var content: some View {
        switch self.style {
        case .icon:
            self.iconView
        case .iconLabel:
            HStack(spacing: 4) {
                self.iconView
                Text(self.copied ? "Copied" : self.label)
                    .font(.caption)
                    .contentTransition(.numericText())
            }
            .foregroundStyle(self.copied ? Color.green : Color.secondary)
        case .prominent:
            HStack(spacing: 6) {
                self.iconView
                Text(self.copied ? "Copied" : self.label)
                    .contentTransition(.numericText())
            }
            .foregroundStyle(self.copied ? Color.green : Color.primary)
        }
    }

    private var iconView: some View {
        Image(systemName: self.copied ? "checkmark" : "doc.on.doc")
            .font(.system(size: 12, weight: .medium))
            .frame(width: 22, height: 22)
            .contentShape(Rectangle())
            .contentTransition(.symbolEffect(.replace.byLayer))
            .foregroundStyle(self.copied ? Color.green : Color.secondary)
            .symbolEffect(.bounce, value: self.copied)
            .animation(self.reduceMotion ? nil : .spring(response: 0.3, dampingFraction: 0.7), value: self.copied)
    }

    private func copyToPasteboard() {
        WalletPasteboard.copy(self.text)
        NSHapticFeedbackManager.defaultPerformer.perform(.alignment, performanceTime: .now)
        self.copied = true
        self.onCopy?()
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(1.6))
            self.copied = false
        }
    }
}

#if DEBUG

#Preview("CopyButton - icon") {
    CopyButton(text: "So11111111111111111111111111111111111111112")
        .padding()
        .frame(width: 120)
}

#Preview("CopyButton - iconLabel") {
    CopyButton(text: "So11111111111111111111111111111111111111112", style: .iconLabel)
        .padding()
        .frame(width: 160)
}

#Preview("CopyButton - prominent") {
    CopyButton(text: "So11111111111111111111111111111111111111112", label: "Copy address", style: .prominent)
        .padding()
        .frame(width: 220)
}

#endif
