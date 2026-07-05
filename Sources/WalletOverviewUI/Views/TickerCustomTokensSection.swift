import SwiftUI
import WalletOverviewDomain

/// The "Custom tokens" block of the Menu Bar Widget settings: a list of pasted
/// tokens with remove buttons, a paste field that resolves a Solana mint or an
/// EVM contract address, and a chain picker shown when an EVM address is live on
/// more than one supported chain.
struct TickerCustomTokensSection: View {
    @Bindable var ticker: TickerSettingsViewModel
    @State private var tokenInput = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            self.header
            if !self.ticker.customEntries.isEmpty {
                self.entryList
            }
            self.pasteField
            if let choices = self.ticker.chainChoices, !choices.isEmpty {
                self.chainPicker(choices)
            }
            if let error = self.ticker.addError {
                Text(error)
                    .font(.caption)
                    .foregroundStyle(.red)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }

    private var header: some View {
        Text("Custom tokens")
            .font(.caption.weight(.semibold))
            .foregroundStyle(.secondary)
            .textCase(.uppercase)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 4)
    }

    private var entryList: some View {
        VStack(spacing: 0) {
            let entries = self.ticker.customEntries
            ForEach(Array(entries.enumerated()), id: \.element.id) { index, entry in
                self.row(entry)
                if index != entries.count - 1 {
                    Divider().padding(.leading, 16).opacity(0.35)
                }
            }
        }
        .background(.quaternary.opacity(0.4), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
    }

    private func row(_ entry: TickerEntry) -> some View {
        HStack(spacing: 10) {
            Text(entry.symbol)
                .font(.callout.weight(.medium))
            Text(entry.displayName)
                .font(.callout)
                .foregroundStyle(.secondary)
                .lineLimit(1)
            Spacer()
            Button(
                action: { self.ticker.removeEntry(id: entry.id) },
                label: {
                    Image(systemName: "minus.circle.fill")
                        .foregroundStyle(.secondary)
                })
                .buttonStyle(.plain)
                .accessibilityLabel("Remove \(entry.symbol)")
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
    }

    private var pasteField: some View {
        HStack(spacing: 8) {
            TextField("Paste a token address (Solana or 0x...)", text: self.$tokenInput)
                .textFieldStyle(.plain)
                .font(.callout)
                .lineLimit(1)
                .truncationMode(.middle)
                .disabled(self.ticker.isResolving)
                .onSubmit(self.submit)
            if self.ticker.isResolving {
                ProgressView().controlSize(.small)
            } else {
                Button("Add", action: self.submit)
                    .buttonStyle(.plain)
                    .foregroundStyle(.tint)
                    .disabled(self.isAddDisabled)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .background(.quaternary.opacity(0.4), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
    }

    private func chainPicker(_ choices: [PasteChainCandidate]) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Found on several chains. Pick one:")
                .font(.caption)
                .foregroundStyle(.secondary)
                .padding(.horizontal, 4)
            VStack(spacing: 0) {
                ForEach(choices) { choice in
                    Button {
                        self.ticker.chooseChain(choice)
                        self.tokenInput = ""
                    } label: {
                        HStack(spacing: 8) {
                            Text(choice.chainName)
                                .font(.callout.weight(.medium))
                            Spacer()
                            Text(Self.liquidity(choice.liquidityUSD))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        .contentShape(Rectangle())
                        .padding(.horizontal, 14)
                        .padding(.vertical, 10)
                    }
                    .buttonStyle(.plain)
                    if choice.id != choices.last?.id {
                        Divider().padding(.leading, 16).opacity(0.35)
                    }
                }
            }
            .background(.quaternary.opacity(0.4), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            Button("Cancel", action: self.ticker.cancelChainChoice)
                .buttonStyle(.plain)
                .font(.caption)
                .foregroundStyle(.tint)
                .padding(.horizontal, 4)
        }
    }

    private var isAddDisabled: Bool {
        self.tokenInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || !self.ticker.canAddMore
    }

    private func submit() {
        let raw = self.tokenInput
        Task {
            await self.ticker.addPasted(raw)
            if self.ticker.addError == nil, self.ticker.chainChoices == nil {
                self.tokenInput = ""
            }
        }
    }

    private static func liquidity(_ usd: Decimal) -> String {
        let value = (usd as NSDecimalNumber).doubleValue
        if value >= 1_000_000 { return String(format: "$%.1fM liq", value / 1_000_000) }
        if value >= 1000 { return String(format: "$%.0fK liq", value / 1000) }
        return String(format: "$%.0f liq", value)
    }
}
