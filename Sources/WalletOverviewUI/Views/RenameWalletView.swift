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
            navBar
            Divider().opacity(0.4)
            form
            Spacer(minLength: 0)
        }
        .onAppear {
            if let wallet { label = wallet.label }
            fieldFocused = true
        }
    }

    private var wallet: WalletIdentity? {
        viewModel.wallets.first(where: { $0.id == walletId })
    }

    private var navBar: some View {
        HStack(spacing: 6) {
            Button(action: back) {
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
            TextField("Label", text: $label)
                .textFieldStyle(.roundedBorder)
                .focused($fieldFocused)
                .onSubmit { save() }

            if let errorMessage {
                Text(errorMessage)
                    .font(.caption)
                    .foregroundStyle(.red)
            }

            Button(action: save) {
                HStack {
                    if isWorking { ProgressView().controlSize(.small) }
                    Text("Save")
                        .frame(maxWidth: .infinity)
                }
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .keyboardShortcut(.defaultAction)
            .disabled(trimmed.isEmpty || isWorking)
        }
        .padding(.horizontal, 16)
        .padding(.top, 14)
    }

    private var trimmed: String {
        label.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func back() {
        withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.22)) {
            viewModel.route = .manage
        }
    }

    private func save() {
        let value = trimmed
        guard !value.isEmpty, !isWorking else { return }
        isWorking = true
        errorMessage = nil
        Task {
            await viewModel.renameWallet(walletId, to: value)
            isWorking = false
            withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.22)) {
                viewModel.route = .manage
            }
        }
    }
}
