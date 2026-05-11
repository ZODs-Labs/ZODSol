import SwiftUI
import WalletOverviewDomain

/// Inline signing-key import reached from the manage route.
struct AddWalletView: View {
    let viewModel: WalletOverviewViewModel

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var label: String = ""
    @State private var privateKeyText: String = ""
    @State private var isWorking: Bool = false
    @State private var errorMessage: String?
    @FocusState private var labelFocused: Bool

    var body: some View {
        VStack(spacing: 0) {
            navBar
            Divider().opacity(0.4)
            form
            Spacer(minLength: 0)
        }
        .onAppear { labelFocused = true }
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

            Text("Add wallet")
                .font(.headline)
                .foregroundStyle(.primary)

            Spacer()

            Color.clear.frame(width: 70, height: 1)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
    }

    private var form: some View {
        VStack(alignment: .leading, spacing: 10) {
            TextField("Wallet label (e.g. Main)", text: $label)
                .textFieldStyle(.roundedBorder)
                .focused($labelFocused)

            SecureField("Solana private key", text: $privateKeyText)
                .font(.system(.callout, design: .monospaced))
                .textFieldStyle(.roundedBorder)
                .disableAutocorrection(true)
                .onSubmit { importWallet() }

            if let errorMessage {
                Text(errorMessage)
                    .font(.caption)
                    .foregroundStyle(.red)
            }

            Button(action: importWallet) {
                HStack {
                    if isWorking { ProgressView().controlSize(.small) }
                    Text(isWorking ? "Importing…" : "Import wallet")
                        .frame(maxWidth: .infinity)
                }
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .keyboardShortcut(.defaultAction)
            .disabled(!canImport || isWorking)
        }
        .padding(.horizontal, 16)
        .padding(.top, 14)
    }

    private var canImport: Bool {
        !privateKeyText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && !label.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private func back() {
        withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.22)) {
            viewModel.route = .manage
        }
    }

    private func importWallet() {
        let trimmedKey = privateKeyText.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedLabel = label.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedKey.isEmpty, !trimmedLabel.isEmpty, !isWorking else { return }
        isWorking = true
        errorMessage = nil
        Task {
            do {
                try await viewModel.addWallet(privateKeyText: trimmedKey, label: trimmedLabel)
                privateKeyText = ""
                label = ""
                withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.22)) {
                    viewModel.route = .overview
                }
            } catch {
                errorMessage = error.localizedDescription
            }
            isWorking = false
        }
    }
}
