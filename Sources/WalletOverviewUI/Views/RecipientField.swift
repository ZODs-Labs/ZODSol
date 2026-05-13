import AppKit
import SolanaKit
import SwiftUI
import WalletOverviewDomain

/// Recipient input row used by `SendInputView`. Combines a text field, a quick
/// paste affordance and an inline clear button. Border styling is subtle and
/// macOS-native: a separator-coloured edge by default, accent on focus, red
/// only on hard validation errors. Successful recipients are confirmed via a
/// trailing checkmark glyph - we never paint the field green.
struct RecipientField: View {
    @Bindable var viewModel: SendViewModel
    @FocusState.Binding var focused: SendInputView.Field?

    var body: some View {
        HStack(spacing: 6) {
            TextField("Recipient address", text: self.recipientBinding)
                .textFieldStyle(.plain)
                .font(.system(.body, design: .monospaced))
                .lineLimit(1)
                .truncationMode(.middle)
                .focused(self.$focused, equals: .recipient)
                .accessibilityLabel("Recipient address")

            if self.showValidCheckmark {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(.green)
                    .imageScale(.medium)
                    .transition(.scale.combined(with: .opacity))
                    .accessibilityLabel("Address is valid")
            }

            if !self.viewModel.recipientText.isEmpty {
                IconBarButton(systemName: "xmark.circle.fill", help: "Clear") {
                    self.viewModel.consumeRecipientText("")
                }
                .accessibilityLabel("Clear")
            }

            IconBarButton(systemName: "doc.on.clipboard", help: "Paste") {
                self.pasteFromClipboard()
            }
            .accessibilityLabel("Paste")
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(.thinMaterial))
        .overlay(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .strokeBorder(self.borderColor, lineWidth: self.borderWidth))
        .animation(.smooth(duration: 0.16), value: self.viewModel.inputValidation)
        .animation(.smooth(duration: 0.16), value: self.focused)
    }

    private var recipientBinding: Binding<String> {
        Binding(
            get: { self.viewModel.recipientText },
            set: { self.viewModel.consumeRecipientText($0) })
    }

    private var showValidCheckmark: Bool {
        guard !self.viewModel.recipientText.isEmpty else { return false }
        switch self.viewModel.inputValidation {
        case .ok, .freshRecipientATA: return true
        default: return false
        }
    }

    private var borderColor: Color {
        if self.viewModel.recipientText.isEmpty {
            return self.focused == .recipient
                ? Color.accentColor.opacity(0.55)
                : Color(nsColor: .separatorColor)
        }
        switch self.viewModel.inputValidation {
        case .ok, .freshRecipientATA, .sendingToSelf:
            return self.focused == .recipient
                ? Color.accentColor.opacity(0.55)
                : Color(nsColor: .separatorColor)
        case let .quoteError(message) where message.isEmpty:
            return self.focused == .recipient
                ? Color.accentColor.opacity(0.55)
                : Color(nsColor: .separatorColor)
        default:
            return Color.red.opacity(0.55)
        }
    }

    private var borderWidth: CGFloat {
        self.focused == .recipient ? 1.0 : 0.5
    }

    private func pasteFromClipboard() {
        if let value = NSPasteboard.general.string(forType: .string) {
            self.viewModel.consumeRecipientText(value)
        }
    }
}

/// Compact icon button used inside a text field. Matches the visual weight of
/// `NSTextField` accessory glyphs - 24x24pt pointer target, subtle hover
/// background, secondary tint that flips to primary on hover.
private struct IconBarButton: View {
    let systemName: String
    let help: String
    let action: () -> Void

    @State private var isHovered = false

    var body: some View {
        Button(action: self.action) {
            Image(systemName: self.systemName)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(self.isHovered ? .primary : .secondary)
                .frame(width: 24, height: 24)
                .background(
                    RoundedRectangle(cornerRadius: 5, style: .continuous)
                        .fill(self.isHovered
                            ? Color.primary.opacity(0.08)
                            : Color.clear))
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { self.isHovered = $0 }
        .help(self.help)
    }
}

#if DEBUG

private actor PreviewNoopSendService: SendAssetsService {
    func quote(_ request: SendRequest, tier: PriorityTier) async throws -> SendQuote {
        throw SendError.canceled
    }

    func send(quote: SendQuote) async throws -> SendOutcome {
        throw SendError.canceled
    }

    func resync(walletId: UUID) async -> [PendingSendResolution] {
        []
    }
}

@MainActor
private func makePreviewSendVMRecipient(text: String, validation: InputValidation) -> SendViewModel {
    let address = try! WalletAddress(base58: "So11111111111111111111111111111111111111112")
    let intent = SendIntent(walletId: UUID(), from: address, asset: .sol)
    let vm = SendViewModel(
        intent: intent,
        cluster: .mainnet,
        service: PreviewNoopSendService(),
        onDismiss: {})
    vm.recipientText = text
    vm.inputValidation = validation
    return vm
}

private struct RecipientFieldPreviewHost: View {
    @State private var model: SendViewModel
    @FocusState private var focus: SendInputView.Field?

    init(prepopulated text: String = "", validation: InputValidation = .ok) {
        self._model = State(initialValue: makePreviewSendVMRecipient(text: text, validation: validation))
    }

    var body: some View {
        RecipientField(viewModel: self.model, focused: self.$focus)
            .padding(16)
            .frame(width: 380)
    }
}

#Preview("Empty") {
    RecipientFieldPreviewHost()
}

#Preview("Valid address") {
    RecipientFieldPreviewHost(
        prepopulated: "5x38Kp4hvdomTCnCrAny4UtMUt5rQBdB6px2K1Ui45Wq",
        validation: .ok)
}

#Preview("Invalid address") {
    RecipientFieldPreviewHost(
        prepopulated: "not-a-valid-address",
        validation: .quoteError("Invalid address"))
}

#endif
