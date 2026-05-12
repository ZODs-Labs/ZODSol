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
                Text(self.statusSubtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
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
            return sig
        default:
            return nil
        }
    }

    private var statusTitle: String {
        switch self.viewModel.state {
        case .signing:      return "Waiting for signature..."
        case .broadcasting: return "Sending..."
        case .confirming:   return "Confirming..."
        case .confirmed:    return "Send confirmed"
        case .expired:      return "Transaction expired"
        case .failed:       return "Send failed"
        default:            return ""
        }
    }

    private var statusSubtitle: String {
        switch self.viewModel.state {
        case .signing:
            return "Approve with Touch ID to broadcast."
        case .broadcasting:
            return "Submitting the signed transaction to the cluster."
        case .confirming:
            return "Waiting for cluster confirmation."
        case let .confirmed(_, slot):
            return "Reached confirmed commitment in slot \(slot)."
        case .expired:
            return "The blockhash window closed before confirmation. Try again."
        case let .failed(error):
            return self.errorMessage(error)
        default:
            return ""
        }
    }

    private var isTerminal: Bool {
        switch self.viewModel.state {
        case .confirmed, .expired, .failed:
            return true
        default:
            return false
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
            case .offCurveForSol:       return "Cannot send SOL to a program-derived address."
            case .knownProgramAddress:  return "Recipient is a known program - refusing."
            case .malformed:            return "Recipient address is not valid."
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
                        style: StrokeStyle(lineWidth: 6, lineCap: .round)
                    )
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
        case .signing, .broadcasting, .confirming: return true
        default:                                   return false
        }
    }

    private var inFlightIcon: String {
        switch self.state {
        case .signing:      return "touchid"
        case .broadcasting: return "paperplane.fill"
        case .confirming:   return "hourglass"
        default:            return "circle"
        }
    }

    private var terminalIcon: String {
        switch self.state {
        case .confirmed: return "checkmark.circle.fill"
        case .expired:   return "clock.badge.exclamationmark.fill"
        case .failed:    return "xmark.circle.fill"
        default:         return "circle"
        }
    }

    private var terminalColor: Color {
        switch self.state {
        case .confirmed: return .green
        case .expired:   return .orange
        case .failed:    return .red
        default:         return .secondary
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
                    .textSelection(.enabled)
            }
            Spacer(minLength: 8)
            CopyButton(text: self.signature.base58)
            Link(destination: Solscan.transaction(signature: self.signature.base58, network: self.network)) {
                Image(systemName: "arrow.up.right.square")
                    .font(.system(size: 13, weight: .medium))
            }
            .buttonStyle(.borderless)
            .accessibilityLabel("View on Solscan")
            .help("View on Solscan")
        }
        .padding(10)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(Color.secondary.opacity(0.08))
        )
    }

    private var shortened: String {
        let b58 = self.signature.base58
        guard b58.count > 16 else { return b58 }
        return "\(b58.prefix(8))...\(b58.suffix(6))"
    }
}
