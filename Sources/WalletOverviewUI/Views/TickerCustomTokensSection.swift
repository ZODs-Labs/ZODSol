import SwiftUI
import WalletOverviewDomain

/// The "Custom tokens" block of the Menu Bar Widget settings: a list of pasted
/// Solana mints with remove buttons, plus a paste field that resolves a mint to
/// a symbol and icon through Jupiter before adding it.
struct TickerCustomTokensSection: View {
    @Bindable var ticker: TickerSettingsViewModel
    @State private var mintInput = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            self.header
            if !self.ticker.customEntries.isEmpty {
                self.entryList
            }
            self.pasteField
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
            TextField("Paste a Solana mint address", text: self.$mintInput)
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

    private var isAddDisabled: Bool {
        self.mintInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || !self.ticker.canAddMore
    }

    private func submit() {
        let raw = self.mintInput
        Task {
            await self.ticker.addPastedMint(raw)
            if self.ticker.addError == nil { self.mintInput = "" }
        }
    }
}
