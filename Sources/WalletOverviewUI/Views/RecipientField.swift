import AppKit
import SwiftUI

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
                .fill(Color.secondary.opacity(0.06))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(self.borderColor, lineWidth: 1)
        )
    }

    private var recipientBinding: Binding<String> {
        Binding(
            get: { self.viewModel.recipientText },
            set: { self.viewModel.consumeRecipientText($0) }
        )
    }

    private var borderColor: Color {
        if self.viewModel.recipientText.isEmpty { return .clear }
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
