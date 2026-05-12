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
            self.navBar
            Divider().opacity(0.4)
            self.form
            Spacer(minLength: 0)
        }
        .onAppear { self.labelFocused = true }
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
            TextField("Wallet label (e.g. Main)", text: self.$label)
                .textFieldStyle(.roundedBorder)
                .focused(self.$labelFocused)

            SecureField("Solana private key", text: self.$privateKeyText)
                .font(.system(.callout, design: .monospaced))
                .textFieldStyle(.roundedBorder)
                .disableAutocorrection(true)
                .onSubmit { self.importWallet() }

            if let errorMessage {
                Text(errorMessage)
                    .font(.caption)
                    .foregroundStyle(.red)
            }

            Button(action: self.importWallet) {
                HStack {
                    if self.isWorking { ProgressView().controlSize(.small) }
                    Text(self.isWorking ? "Importing…" : "Import wallet")
                        .frame(maxWidth: .infinity)
                }
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .keyboardShortcut(.defaultAction)
            .disabled(!self.canImport || self.isWorking)
        }
        .padding(.horizontal, 16)
        .padding(.top, 14)
    }

    private var canImport: Bool {
        !self.privateKeyText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && !self.label.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private func back() {
        withAnimation(self.reduceMotion ? nil : .easeInOut(duration: 0.22)) {
            self.viewModel.route = .manage
        }
    }

    private func importWallet() {
        let trimmedKey = self.privateKeyText.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedLabel = self.label.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedKey.isEmpty, !trimmedLabel.isEmpty, !self.isWorking else { return }
        self.isWorking = true
        self.errorMessage = nil
        Task {
            do {
                try await self.viewModel.addWallet(privateKeyText: trimmedKey, label: trimmedLabel)
                self.privateKeyText = ""
                self.label = ""
                withAnimation(self.reduceMotion ? nil : .easeInOut(duration: 0.22)) {
                    self.viewModel.route = .overview
                }
            } catch {
                self.errorMessage = error.localizedDescription
            }
            self.isWorking = false
        }
    }
}
