import AppKit
import SolanaKit
import SwiftUI
import WalletOverviewDomain

/// Recipient input row used by `SendInputView`. Combines a text field, a quick
/// paste affordance and an inline clear button. Border colour reflects the
/// view model's `inputValidation` so the user gets immediate feedback when an
/// address looks wrong.
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

            if !self.viewModel.recipientText.isEmpty {
                Button {
                    self.viewModel.recipientText = ""
                    self.viewModel.consumeRecipientText("")
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.borderless)
                .accessibilityLabel("Clear")
                .help("Clear")
            }

            Button {
                self.pasteFromClipboard()
            } label: {
                Image(systemName: "doc.on.clipboard")
            }
            .buttonStyle(.borderless)
            .accessibilityLabel("Paste")
            .help("Paste")
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(.quaternary))
        .overlay(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .strokeBorder(self.borderColor, lineWidth: 0.5))
    }

    private var recipientBinding: Binding<String> {
        Binding(
            get: { self.viewModel.recipientText },
            set: { self.viewModel.consumeRecipientText($0) })
    }

    private var borderColor: Color {
        if self.viewModel.recipientText.isEmpty {
            return Color(nsColor: .separatorColor)
        }
        switch self.viewModel.inputValidation {
        case .ok, .freshRecipientATA:
            return .green.opacity(0.55)
        case .sendingToSelf:
            return .yellow.opacity(0.7)
        default:
            return .red.opacity(0.55)
        }
    }

    private func pasteFromClipboard() {
        if let value = NSPasteboard.general.string(forType: .string) {
            self.viewModel.consumeRecipientText(value)
        }
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

    func resync(walletId: UUID) async -> [Signature: SendOutcome] { [:] }
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
