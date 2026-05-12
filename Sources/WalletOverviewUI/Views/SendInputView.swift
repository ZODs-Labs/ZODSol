import AppKit
import Formatters
import SolanaKit
import SwiftUI

/// First step of the send flow. Combines the recipient field, recents,
/// dual-mode amount entry, percentage chips and a validation strip. The
/// "Review" button calls `requestQuote` which pushes the state machine into
/// `.quoting` and from there onto the confirm view.
struct SendInputView: View {
    @Bindable var viewModel: SendViewModel
    @FocusState private var focused: Field?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var isReviewing = false

    enum Field: Hashable {
        case recipient
        case amount
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            header
            assetHeaderCard

            RecipientField(viewModel: self.viewModel, focused: self.$focused)

            if let pill = self.viewModel.solanaPayPill {
                SolanaPayPillView(pill: pill)
            }

            RecentRecipientsList(viewModel: self.viewModel)

            AmountField(viewModel: self.viewModel, focused: self.$focused)

            AmountChipStrip(viewModel: self.viewModel)

            if let strip = self.validationStrip() {
                strip
            }

            if let legacy = self.viewModel.validationError {
                Text(legacy)
                    .font(.caption)
                    .foregroundStyle(.red)
            }

            Spacer(minLength: 0)

            footer
        }
        .padding(16)
        .task {
            await self.viewModel.loadRecents()
        }
        .onAppear {
            self.focused = .recipient
        }
    }

    // MARK: - Subviews

    private var header: some View {
        HStack {
            Text("Send \(self.viewModel.assetSymbol)")
                .font(.title3.weight(.semibold))
            Spacer()
            ClusterBadge(network: self.viewModel.cluster)
        }
    }

    private var assetHeaderCard: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(self.viewModel.assetName)
                    .font(.callout.weight(.semibold))
                Text("Balance")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
            VStack(alignment: .trailing, spacing: 2) {
                Text(self.viewModel.balanceDisplay)
                    .font(.callout.weight(.medium))
                    .monospacedDigit()
                if let usd = self.viewModel.balanceUSDDisplay {
                    Text(usd)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .padding(10)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(.gray.opacity(0.08))
        )
    }

    private var footer: some View {
        HStack {
            Button("Cancel") {
                self.viewModel.cancelDebouncedQuote()
                self.viewModel.dismiss()
            }
            .buttonStyle(.bordered)
            .keyboardShortcut(.cancelAction)

            Spacer()

            Button {
                self.isReviewing = true
                Task {
                    await self.viewModel.requestQuote()
                    self.isReviewing = false
                }
            } label: {
                if self.isReviewing {
                    ProgressView().controlSize(.small)
                } else {
                    Text("Review")
                }
            }
            .keyboardShortcut(.defaultAction)
            .buttonStyle(.borderedProminent)
            .disabled(self.isReviewing || !self.viewModel.canReview)
        }
    }

    private func validationStrip() -> ValidationStripView? {
        let validation = self.viewModel.inputValidation
        if case let .quoteError(message) = validation {
            if message.isEmpty { return nil }
            return ValidationStripView(text: message, style: .error)
        }
        if validation == .ok { return nil }
        return ValidationStripView(text: validation.userMessage, style: validation.stripStyle)
    }
}

/// Pill that surfaces the `label` and `message` fields from a Solana Pay URI
/// so the user can spot the merchant context before signing.
struct SolanaPayPillView: View {
    let pill: SolanaPayPill

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: "link.circle.fill")
                .foregroundStyle(Color.accentColor)
            VStack(alignment: .leading, spacing: 2) {
                if let label = self.pill.label, !label.isEmpty {
                    Text(label)
                        .font(.caption.weight(.medium))
                }
                if let message = self.pill.message, !message.isEmpty {
                    Text(message)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(.blue.opacity(0.08))
        )
    }
}

/// Inline status strip below the form. Carries either a hard error (red), a
/// warning (yellow) or an informational nudge (blue).
struct ValidationStripView: View {
    enum Style {
        case info
        case warning
        case error
    }

    let text: String
    let style: Style

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 6) {
            Image(systemName: self.iconName)
                .foregroundStyle(self.tint)
            Text(self.text)
                .font(.caption)
                .foregroundStyle(self.tint)
            Spacer(minLength: 0)
        }
        .padding(.vertical, 6)
        .padding(.horizontal, 10)
        .background(
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .fill(self.tint.opacity(0.08))
        )
    }

    private var iconName: String {
        switch self.style {
        case .info: return "info.circle"
        case .warning: return "exclamationmark.triangle"
        case .error: return "exclamationmark.octagon"
        }
    }

    private var tint: Color {
        switch self.style {
        case .info: return .accentColor
        case .warning: return .yellow
        case .error: return .red
        }
    }
}

private extension InputValidation {
    var stripStyle: ValidationStripView.Style {
        switch self {
        case .ok: return .info
        case .freshRecipientATA, .sendingToSelf: return .warning
        default: return .error
        }
    }
}

/// Small visual cue: green for devnet/testnet, red for mainnet so the user
/// can never confuse the two.
struct ClusterBadge: View {
    let network: SolanaNetwork

    var body: some View {
        let (label, color): (String, Color) = {
            switch self.network {
            case .mainnet: return ("Mainnet", .red)
            case .devnet: return ("Devnet", .green)
            case .testnet: return ("Testnet", .yellow)
            }
        }()
        Text(label)
            .font(.caption.weight(.medium))
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(
                Capsule().fill(color.opacity(0.16))
            )
            .overlay(
                Capsule().strokeBorder(color.opacity(0.55), lineWidth: 0.5)
            )
            .foregroundStyle(color)
    }
}

struct SendQuotingView: View {
    var body: some View {
        VStack(spacing: 10) {
            ProgressView()
            Text("Preparing transfer…")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
