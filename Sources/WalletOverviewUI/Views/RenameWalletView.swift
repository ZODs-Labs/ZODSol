import SwiftUI
import WalletOverviewDomain

/// Inline rename screen reached from the manage route. No sheet — the rename
/// form is a panel page so the panel's event monitor never sees a foreign
/// window when the text field is clicked.
struct RenameWalletView: View {
    let viewModel: WalletOverviewViewModel
    let walletId: UUID

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var label: String = ""
    @State private var isWorking: Bool = false
    @State private var errorMessage: String?
    @FocusState private var fieldFocused: Bool

    var body: some View {
        VStack(spacing: 0) {
            self.navBar
            Divider().opacity(0.4)
            self.form
            Spacer(minLength: 0)
        }
        .onAppear {
            if let wallet { self.label = wallet.label }
            self.fieldFocused = true
        }
    }

    private var wallet: WalletIdentity? {
        self.viewModel.wallets.first(where: { $0.id == self.walletId })
    }

    private var navBar: some View {
        HStack(spacing: 6) {
            Button(action: self.back) {
                HStack(spacing: 4) {
                    Image(systemName: "chevron.left")
                    Text("Manage")
                }
                .font(.callout)
                .foregroundStyle(.primary)
            }
            .buttonStyle(.plain)

            Spacer()

            Text("Rename")
                .font(.headline)
                .foregroundStyle(.primary)

            Spacer()

            Color.clear.frame(width: 70, height: 1)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
    }

    private var form: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Wallet label")
                .font(.caption)
                .foregroundStyle(.secondary)
            TextField("Label", text: self.$label)
                .textFieldStyle(.roundedBorder)
                .focused(self.$fieldFocused)
                .onSubmit { self.save() }

            if let errorMessage {
                Text(errorMessage)
                    .font(.caption)
                    .foregroundStyle(.red)
            }

            Button(action: self.save) {
                HStack {
                    if self.isWorking { ProgressView().controlSize(.small) }
                    Text("Save")
                        .frame(maxWidth: .infinity)
                }
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .keyboardShortcut(.defaultAction)
            .disabled(self.trimmed.isEmpty || self.isWorking)
        }
        .padding(.horizontal, 16)
        .padding(.top, 14)
    }

    private var trimmed: String {
        self.label.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func back() {
        withAnimation(self.reduceMotion ? nil : .easeInOut(duration: 0.22)) {
            self.viewModel.route = .manage
        }
    }

    private func save() {
        let value = self.trimmed
        guard !value.isEmpty, !self.isWorking else { return }
        self.isWorking = true
        self.errorMessage = nil
        Task {
            await self.viewModel.renameWallet(self.walletId, to: value)
            self.isWorking = false
            withAnimation(self.reduceMotion ? nil : .easeInOut(duration: 0.22)) {
                self.viewModel.route = .manage
            }
        }
    }
}
