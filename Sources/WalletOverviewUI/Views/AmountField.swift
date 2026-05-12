import Formatters
import SolanaKit
import SwiftUI
import WalletOverviewDomain

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
                TextField("0.0", text: self.amountBinding)
                    .textFieldStyle(.plain)
                    .font(.system(.body, design: .monospaced))
                    .focused(self.$focused, equals: .amount)
                    .accessibilityLabel("Amount")

                Text(self.unitLabel)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(Color(nsColor: .controlBackgroundColor)))
            .overlay(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .strokeBorder(self.borderColor, lineWidth: self.borderWidth))

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

    private var amountBinding: Binding<String> {
        Binding(
            get: { self.viewModel.amountText },
            set: { newValue in
                let filtered = Self.filterNumeric(newValue)
                guard filtered != self.viewModel.amountText else { return }
                self.viewModel.amountText = filtered
                self.viewModel.consumeAmountChange()
            })
    }

    /// Drop anything that is not a digit or a single decimal separator. Allow
    /// thousands commas because the parser already strips them. Keeps the
    /// field free of obvious garbage without rewriting the parse rules.
    private static func filterNumeric(_ text: String) -> String {
        var result = ""
        var sawDecimal = false
        for character in text {
            if character.isNumber || character == "," {
                result.append(character)
            } else if character == "." || character == Character(Locale.current.decimalSeparator ?? ".") {
                if !sawDecimal {
                    result.append(".")
                    sawDecimal = true
                }
            }
        }
        return result
    }

    private var borderColor: Color {
        let validation = self.viewModel.inputValidation
        switch validation {
        case .amountExceedsBalance, .amountTooSmall, .decimalsExceedMint, .belowFeeReserve:
            return Color.red.opacity(0.55)
        default:
            return self.focused == .amount
                ? Color.accentColor.opacity(0.55)
                : Color(nsColor: .separatorColor)
        }
    }

    private var borderWidth: CGFloat {
        self.focused == .amount ? 1.0 : 0.5
    }

    private var unitLabel: String {
        switch self.viewModel.fiatMode {
        case .token: self.viewModel.assetSymbol
        case .fiat: "USD"
        }
    }
}

#if DEBUG

private actor PreviewNoopAmountFieldService: SendAssetsService {
    func quote(_ request: SendRequest, tier: PriorityTier) async throws -> SendQuote {
        throw SendError.canceled
    }

    func send(quote: SendQuote) async throws -> SendOutcome {
        throw SendError.canceled
    }

    func resync(walletId: UUID) async -> [Signature: SendOutcome] {
        [:]
    }
}

@MainActor
private func makeAmountFieldPreviewVM(text: String) -> SendViewModel {
    let address = try! WalletAddress(base58: "So11111111111111111111111111111111111111112")
    let intent = SendIntent(walletId: UUID(), from: address, asset: .sol)
    let vm = SendViewModel(
        intent: intent,
        cluster: .mainnet,
        service: PreviewNoopAmountFieldService(),
        onDismiss: {})
    vm.amountText = text
    vm.assetBalanceBaseUnits = 2_500_000_000
    vm.assetPriceUSD = 150
    return vm
}

private struct AmountFieldPreviewHost: View {
    @State private var model: SendViewModel
    @FocusState private var focus: SendInputView.Field?

    init(text: String) {
        self._model = State(initialValue: makeAmountFieldPreviewVM(text: text))
    }

    var body: some View {
        AmountField(viewModel: self.model, focused: self.$focus)
            .padding(16)
            .frame(width: 380)
    }
}

#Preview("Empty") {
    AmountFieldPreviewHost(text: "")
}

#Preview("With value") {
    AmountFieldPreviewHost(text: "1.25")
}

#endif
