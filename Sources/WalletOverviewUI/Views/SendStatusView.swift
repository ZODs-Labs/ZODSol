import AppKit
import SolanaKit
import SwiftUI
import WalletOverviewDomain

struct SendStatusView: View {
    @Bindable var viewModel: SendViewModel

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var didRecordRecipient = false

    var body: some View {
        VStack(spacing: 16) {
            Spacer(minLength: 0)

            StateRing(state: self.viewModel.state, reduceMotion: self.reduceMotion)
                .frame(width: 80, height: 80)

            VStack(spacing: 4) {
                Text(self.statusTitle)
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(.primary)
                Text(self.statusSubtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 12)
            }

            if let signature = self.currentSignature {
                SignatureCard(signature: signature, network: self.viewModel.cluster)
            }

            Spacer(minLength: 0)

            self.actionBar
        }
        .padding(16)
        .onAppear {
            self.recordIfConfirmed(self.viewModel.state)
        }
        .onChange(of: self.viewModel.state) { _, newState in
            self.recordIfConfirmed(newState)
        }
    }

    @ViewBuilder
    private var actionBar: some View {
        if self.isTerminal {
            HStack {
                Button("Send another") { self.viewModel.back() }
                    .buttonStyle(.bordered)
                Spacer()
                Button("Done") { self.viewModel.dismiss() }
                    .buttonStyle(.borderedProminent)
                    .keyboardShortcut(.defaultAction)
            }
        } else {
            HStack {
                Spacer()
                Button("Hide") { self.viewModel.dismiss() }
                    .buttonStyle(.bordered)
            }
        }
    }

    // MARK: - Derived

    private var currentSignature: Signature? {
        switch self.viewModel.state {
        case let .broadcasting(sig), let .confirming(sig), let .confirmed(sig, _),
             let .expired(sig):
            sig
        default:
            nil
        }
    }

    private var statusTitle: String {
        switch self.viewModel.state {
        case .signing: "Waiting for signature..."
        case .broadcasting: "Sending..."
        case .confirming: "Confirming..."
        case .confirmed: "Send confirmed"
        case .expired: "Transaction expired"
        case .failed: "Send failed"
        default: ""
        }
    }

    private var statusSubtitle: String {
        switch self.viewModel.state {
        case .signing:
            "Approve with Touch ID to broadcast."
        case .broadcasting:
            "Submitting the signed transaction to the cluster."
        case .confirming:
            "Waiting for cluster confirmation."
        case let .confirmed(_, slot):
            "Reached confirmed commitment in slot \(slot)."
        case .expired:
            "The blockhash window closed before confirmation. Try again."
        case let .failed(error):
            self.errorMessage(error)
        default:
            ""
        }
    }

    private var isTerminal: Bool {
        switch self.viewModel.state {
        case .confirmed, .expired, .failed:
            true
        default:
            false
        }
    }

    private func recordIfConfirmed(_ state: SendViewModel.State) {
        guard case .confirmed = state, !self.didRecordRecipient else { return }
        guard let store = self.viewModel.recentRecipientsStore else { return }
        self.didRecordRecipient = true
        Task { @MainActor in
            await self.viewModel.recordRecipientOnConfirm(store)
        }
    }

    private func errorMessage(_ error: SendError) -> String {
        switch error {
        case let .invalidRecipient(reason):
            switch reason {
            case .offCurveForSol: return "Cannot send SOL to a program-derived address."
            case .knownProgramAddress: return "Recipient is a known program - refusing."
            case .malformed: return "Recipient address is not valid."
            }
        case let .insufficientSolForFee(required, available):
            return "Need \(self.formatSol(required)) for fees; wallet has \(self.formatSol(available))."
        case let .insufficientSolForRent(required, available):
            let need = self.formatSol(required)
            let have = self.formatSol(available)
            return "Need \(need) to fund the recipient token account; wallet has \(have)."
        case let .unsupportedToken2022Extension(reason):
            return reason
        case .mintNotFound:
            return "Could not find this token's mint on the cluster."
        case let .mintOwnedByUnknownProgram(owner):
            return "This token's program (\(owner)) is not supported."
        case let .simulationFailed(_, errorText):
            return "Simulation failed: \(errorText)"
        case let .transactionTooLarge(bytes):
            return "Transaction is too large (\(bytes) bytes)."
        case .canceled:
            return "Cancelled."
        case .walletAddressMismatch:
            return "Wallet address does not match the selected wallet."
        case let .rpc(inner):
            return "Network error: \(inner)"
        case .sendAlreadyInFlight:
            return "A previous send for this wallet is still in flight."
        case let .broadcastFailed(reason):
            return "Broadcast failed: \(reason)"
        }
    }

    private func formatSol(_ lamports: Lamports) -> String {
        let sol = Double(lamports.rawValue) / 1_000_000_000.0
        return String(format: "%.6f SOL", sol)
    }
}

// MARK: - State ring

private struct StateRing: View {
    let state: SendViewModel.State
    let reduceMotion: Bool

    @State private var rotation: Double = 0

    var body: some View {
        ZStack {
            Circle()
                .stroke(Color.secondary.opacity(0.18), lineWidth: 6)

            if self.isInFlight {
                Circle()
                    .trim(from: 0, to: 0.28)
                    .stroke(
                        Color.accentColor,
                        style: StrokeStyle(lineWidth: 6, lineCap: .round))
                    .rotationEffect(.degrees(self.reduceMotion ? 0 : self.rotation))

                if self.reduceMotion {
                    Image(systemName: self.inFlightIcon)
                        .font(.title2)
                        .foregroundStyle(Color.accentColor)
                }
            } else {
                Image(systemName: self.terminalIcon)
                    .font(.system(size: 34, weight: .semibold))
                    .foregroundStyle(self.terminalColor)
            }
        }
        .onAppear {
            guard self.isInFlight, !self.reduceMotion else { return }
            withAnimation(.linear(duration: 1.2).repeatForever(autoreverses: false)) {
                self.rotation = 360
            }
        }
        .accessibilityHidden(true)
    }

    private var isInFlight: Bool {
        switch self.state {
        case .signing, .broadcasting, .confirming: true
        default: false
        }
    }

    private var inFlightIcon: String {
        switch self.state {
        case .signing: "touchid"
        case .broadcasting: "paperplane.fill"
        case .confirming: "hourglass"
        default: "circle"
        }
    }

    private var terminalIcon: String {
        switch self.state {
        case .confirmed: "checkmark.circle.fill"
        case .expired: "clock.badge.exclamationmark.fill"
        case .failed: "xmark.circle.fill"
        default: "circle"
        }
    }

    private var terminalColor: Color {
        switch self.state {
        case .confirmed: .green
        case .expired: .orange
        case .failed: .red
        default: .secondary
        }
    }
}

// MARK: - Signature card

private struct SignatureCard: View {
    let signature: Signature
    let network: SolanaNetwork

    var body: some View {
        HStack(spacing: 8) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Signature")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                Text(self.shortened)
                    .font(.system(.caption, design: .monospaced))
                    .foregroundStyle(.primary)
                    .textSelection(.enabled)
            }
            Spacer(minLength: 8)
            CopyButton(text: self.signature.base58)
            Link(destination: Solscan.transaction(signature: self.signature.base58, network: self.network)) {
                Image(systemName: "arrow.up.right.square")
                    .font(.system(size: 13, weight: .medium))
            }
            .buttonStyle(.borderless)
            .foregroundStyle(.secondary)
            .accessibilityLabel("View on Solscan")
            .help("View on Solscan")
        }
        .padding(10)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(.background.opacity(0.6)))
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .strokeBorder(Color(nsColor: .separatorColor), lineWidth: 0.5))
    }

    private var shortened: String {
        let b58 = self.signature.base58
        guard b58.count > 16 else { return b58 }
        return "\(b58.prefix(8))...\(b58.suffix(6))"
    }
}

#if DEBUG

private actor PreviewNoopSendStatusService: SendAssetsService {
    func quote(_ request: SendRequest, tier: PriorityTier) async throws -> SendQuote {
        throw SendError.canceled
    }

    func send(quote: SendQuote) async throws -> SendOutcome {
        throw SendError.canceled
    }

    func resync(walletId: UUID) async -> [Signature: SendOutcome] { [:] }
}

@MainActor
private func makeSendStatusPreviewVM() -> SendViewModel {
    let address = try! WalletAddress(base58: "So11111111111111111111111111111111111111112")
    let intent = SendIntent(walletId: UUID(), from: address, asset: .sol)
    let vm = SendViewModel(
        intent: intent,
        cluster: .devnet,
        service: PreviewNoopSendStatusService(),
        onDismiss: {})
    let signature = try! Signature(bytes: Data(repeating: 0xAB, count: 64))
    vm.preloadConfirming(signature: signature)
    return vm
}

private func previewSignature() -> Signature {
    try! Signature(bytes: Data(repeating: 0xCD, count: 64))
}

#Preview("Confirming") {
    SendStatusView(viewModel: makeSendStatusPreviewVM())
        .frame(width: 380, height: 480)
}

#Preview("StateRing - signing") {
    StateRing(state: .signing, reduceMotion: false)
        .frame(width: 80, height: 80)
        .padding(32)
}

#Preview("StateRing - broadcasting") {
    StateRing(state: .broadcasting(previewSignature()), reduceMotion: true)
        .frame(width: 80, height: 80)
        .padding(32)
}

#Preview("StateRing - confirmed") {
    StateRing(state: .confirmed(previewSignature(), slot: 247_198_023), reduceMotion: false)
        .frame(width: 80, height: 80)
        .padding(32)
}

#Preview("StateRing - expired") {
    StateRing(state: .expired(previewSignature()), reduceMotion: false)
        .frame(width: 80, height: 80)
        .padding(32)
}

#Preview("StateRing - failed") {
    StateRing(state: .failed(.canceled), reduceMotion: false)
        .frame(width: 80, height: 80)
        .padding(32)
}

#Preview("SignatureCard") {
    SignatureCard(signature: previewSignature(), network: .devnet)
        .padding(16)
        .frame(width: 380)
}

#endif
