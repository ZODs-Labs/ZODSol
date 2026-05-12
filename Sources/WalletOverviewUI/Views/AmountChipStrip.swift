import Formatters
import SwiftUI

/// Quick-amount chip strip plus the token/fiat mode toggle. Lives under the
/// amount field so the user can fill a percentage of the spendable balance
/// without typing. The trailing toggle is disabled when the active asset has
/// no USD price - there is no fiat axis to flip to.
struct AmountChipStrip: View {
    @Bindable var viewModel: SendViewModel

    var body: some View {
        HStack(spacing: 8) {
            self.chip(label: "25%", percent: 0.25)
            self.chip(label: "50%", percent: 0.5)
            self.chip(label: "75%", percent: 0.75)
            self.chip(label: "Max", percent: 1.0)
            Spacer(minLength: 0)
            Button {
                self.viewModel.toggleFiatMode()
            } label: {
                Text(self.toggleLabel)
                    .font(.caption.weight(.medium))
            }
            .buttonStyle(.bordered)
            .disabled(self.viewModel.assetPriceUSD == nil)
            .accessibilityLabel("Switch entry units")
        }
    }

    @ViewBuilder
    private func chip(label: String, percent: Double) -> some View {
        let disabled = self.isChipDisabled(for: percent)
        Button {
            self.viewModel.selectChip(percent)
        } label: {
            Text(label)
                .font(.caption.weight(.medium))
        }
        .buttonStyle(.bordered)
        .disabled(disabled)
        .help(disabled ? "Not enough balance after fee reserve" : "")
        .accessibilityLabel("\(label) of available balance")
    }

    private func isChipDisabled(for percent: Double) -> Bool {
        let calc = SendAmountCalculator()
        let input = self.viewModel.amountInputForChips()
        let spendable = calc.maxSpendable(input: input)
        if percent == 1.0 { return spendable == 0 }
        return false
    }

    private var toggleLabel: String {
        switch self.viewModel.fiatMode {
        case .token: return self.viewModel.assetSymbol
        case .fiat: return "USD"
        }
    }
}
