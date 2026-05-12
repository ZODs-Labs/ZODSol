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
                    .fill(.quaternary))
            .overlay(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .strokeBorder(Color(nsColor: .separatorColor), lineWidth: 0.5))

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

    func resync(walletId: UUID) async -> [Signature: SendOutcome] { [:] }
}

@MainActor
private func makeAmountFieldPreviewVM(text: String) -> SendViewModel {
    let address = try! WalletAddress(base58: "So11111111111111111111111111111111111111112")
    let intent = SendIntent(walletId: UUID(), from: address, asset: .sol)
    let vm = SendViewModel(
        intent: intent,
        cluster: .devnet,
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
