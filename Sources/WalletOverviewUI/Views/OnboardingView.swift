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
            header

            Group {
                switch step {
                case .apiKey:
                    apiKeyForm
                        .transition(.opacity.combined(with: .move(edge: .trailing)))
                case .wallet:
                    walletForm
                        .transition(.opacity.combined(with: .move(edge: .trailing)))
                }
            }
            .animation(reduceMotion ? nil : .easeInOut(duration: 0.22), value: step)

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
            if viewModel.hasAPIKey {
                step = .wallet
            }
        }
    }

    // MARK: - Header

    private var header: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 8) {
                Image(systemName: step == .apiKey ? "key.fill" : "wallet.pass.fill")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(.tint)
                    .frame(width: 22, height: 22)
                    .background(
                        Circle().fill(.tint.opacity(0.12))
                    )
                Text(step == .apiKey ? "Connect Helius" : "Import wallet")
                    .font(.headline)
                    .foregroundStyle(.primary)
            }
            Text(step == .apiKey
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
            SecureField("Helius API key", text: $apiKey)
                .textFieldStyle(.roundedBorder)
                .disableAutocorrection(true)
                .onSubmit { saveAPIKey() }

            Button(action: saveAPIKey) {
                HStack {
                    if isWorking {
                        ProgressView().controlSize(.small)
                    }
                    Text(isWorking ? "Saving…" : "Save API key")
                        .frame(maxWidth: .infinity)
                }
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .keyboardShortcut(.defaultAction)
            .disabled(trimmedAPIKey.isEmpty || isWorking)
        }
    }

    // MARK: - Step 2: Wallet import

    private var walletForm: some View {
        VStack(alignment: .leading, spacing: 10) {
            TextField("Wallet label (e.g. Main)", text: $label)
                .textFieldStyle(.roundedBorder)

            SecureField("Solana private key", text: $privateKeyText)
                .font(.system(.callout, design: .monospaced))
                .textFieldStyle(.roundedBorder)
                .disableAutocorrection(true)
                .onSubmit { importWallet() }

            HStack(spacing: 8) {
                Button(action: { step = .apiKey }) {
                    Image(systemName: "chevron.left")
                    Text("Back")
                }
                .buttonStyle(.bordered)
                .controlSize(.large)
                .disabled(isWorking)

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
        }
    }

    // MARK: - Helpers

    private var trimmedAPIKey: String {
        apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var canImport: Bool {
        !privateKeyText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && !label.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private func saveAPIKey() {
        let trimmed = trimmedAPIKey
        guard !trimmed.isEmpty, !isWorking else { return }
        isWorking = true
        errorMessage = nil
        Task {
            do {
                try await viewModel.setAPIKey(trimmed)
                apiKey = ""
                step = .wallet
            } catch {
                errorMessage = error.localizedDescription
            }
            isWorking = false
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
            } catch {
                errorMessage = error.localizedDescription
            }
            isWorking = false
        }
    }
}
