import SwiftUI

/// Inline onboarding flow — the form lives directly in the panel, no sheet,
/// no popover. Two steps: connect Helius (API key) then import the first
/// signing key. Steps cross-fade in place. Apple's menu-bar UX never uses a sheet
/// for in-panel data entry; Control Center and Battery use inline navigation
/// for the same reason — sheets spawn a separate NSWindow whose clicks would
/// dismiss the panel.
struct OnboardingView: View {
    let viewModel: WalletOverviewViewModel

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var step: Step = .apiKey
    @State private var apiKey: String = ""
    @State private var privateKeyText: String = ""
    @State private var label: String = ""
    @State private var isWorking: Bool = false
    @State private var errorMessage: String?

    enum Step: Equatable {
        case apiKey
        case wallet
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            self.header

            Group {
                switch self.step {
                case .apiKey:
                    self.apiKeyForm
                        .transition(.opacity.combined(with: .move(edge: .trailing)))
                case .wallet:
                    self.walletForm
                        .transition(.opacity.combined(with: .move(edge: .trailing)))
                }
            }
            .animation(self.reduceMotion ? nil : .easeInOut(duration: 0.22), value: self.step)

            if let errorMessage {
                Text(errorMessage)
                    .font(.caption)
                    .foregroundStyle(.red)
                    .transition(.opacity)
            }

            Spacer(minLength: 0)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 18)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .onAppear {
            if self.viewModel.hasAPIKey {
                self.step = .wallet
            }
        }
    }

    // MARK: - Header

    private var header: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 8) {
                Image(systemName: self.step == .apiKey ? "key.fill" : "wallet.pass.fill")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(.tint)
                    .frame(width: 22, height: 22)
                    .background(
                        Circle().fill(.tint.opacity(0.12)))
                Text(self.step == .apiKey ? "Connect Helius" : "Import wallet")
                    .font(.headline)
                    .foregroundStyle(.primary)
            }
            Text(self.step == .apiKey
                ? "Paste your Helius API key. It is stored in the macOS Keychain."
                : "Paste your Solana signing key. It is stored in Keychain behind Touch ID or your Mac password.")
                .font(.callout)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    // MARK: - Step 1: API key

    private var apiKeyForm: some View {
        VStack(alignment: .leading, spacing: 10) {
            SecureField("Helius API key", text: self.$apiKey)
                .textFieldStyle(.roundedBorder)
                .disableAutocorrection(true)
                .onSubmit { self.saveAPIKey() }

            Button(action: self.saveAPIKey) {
                HStack {
                    if self.isWorking {
                        ProgressView().controlSize(.small)
                    }
                    Text(self.isWorking ? "Saving…" : "Save API key")
                        .frame(maxWidth: .infinity)
                }
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .keyboardShortcut(.defaultAction)
            .disabled(self.trimmedAPIKey.isEmpty || self.isWorking)
        }
    }

    // MARK: - Step 2: Wallet import

    private var walletForm: some View {
        VStack(alignment: .leading, spacing: 10) {
            TextField("Wallet label (e.g. Main)", text: self.$label)
                .textFieldStyle(.roundedBorder)

            SecureField("Solana private key", text: self.$privateKeyText)
                .font(.system(.callout, design: .monospaced))
                .textFieldStyle(.roundedBorder)
                .disableAutocorrection(true)
                .onSubmit { self.importWallet() }

            HStack(spacing: 8) {
                Button(action: { self.step = .apiKey }) {
                    Image(systemName: "chevron.left")
                    Text("Back")
                }
                .buttonStyle(.bordered)
                .controlSize(.large)
                .disabled(self.isWorking)

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
        }
    }

    // MARK: - Helpers

    private var trimmedAPIKey: String {
        self.apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var canImport: Bool {
        !self.privateKeyText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && !self.label.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private func saveAPIKey() {
        let trimmed = self.trimmedAPIKey
        guard !trimmed.isEmpty, !self.isWorking else { return }
        self.isWorking = true
        self.errorMessage = nil
        Task {
            do {
                try await self.viewModel.setAPIKey(trimmed)
                self.apiKey = ""
                self.step = .wallet
            } catch {
                self.errorMessage = error.localizedDescription
            }
            self.isWorking = false
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
            } catch {
                self.errorMessage = error.localizedDescription
            }
            self.isWorking = false
        }
    }
}
