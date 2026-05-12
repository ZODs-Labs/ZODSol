import Formatters
import SwiftUI

/// Amount input row. Echoes the converted value (token <-> fiat) below the
/// field so the user always sees both numbers. The unit suffix flips with
/// `viewModel.fiatMode` so the AmountChipStrip toggle stays in sync with the
/// active mode without touching the text.
struct AmountField: View {
    @Bindable var viewModel: SendViewModel
    @FocusState.Binding var focused: SendInputView.Field?

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                TextField("0.0", text: self.$viewModel.amountText)
                    .textFieldStyle(.plain)
                    .font(.system(.body, design: .monospaced))
                    .focused(self.$focused, equals: .amount)
                    .onChange(of: self.viewModel.amountText) { _, _ in
                        self.viewModel.scheduleQuote()
                    }
                    .accessibilityLabel("Amount")

                Text(self.unitLabel)
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(Color.secondary.opacity(0.06))
            )

            if let echo = self.viewModel.echoText {
                Text(echo)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .contentTransition(.numericText(value: 0))
                    .animation(.default, value: self.viewModel.amountText)
                    .accessibilityLabel("Equivalent: \(echo)")
            }
        }
    }

    private var unitLabel: String {
        switch self.viewModel.fiatMode {
        case .token: return self.viewModel.assetSymbol
        case .fiat: return "USD"
        }
    }
}
