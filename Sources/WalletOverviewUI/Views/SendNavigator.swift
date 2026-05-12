import SolanaKit
import SwiftUI
import WalletOverviewDomain

/// Host for the send flow. Owns one `SendViewModel` whose state drives which
/// sub-screen is rendered (input -> confirm -> status).
struct SendNavigator: View {
    @Bindable var viewModel: SendViewModel
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ZStack {
            switch self.viewModel.state {
            case .input, .quoting:
                // Keep the input form mounted while quoting so the user
                // never loses sight of what they typed. The Review button
                // shows the spinner instead.
                SendInputView(viewModel: self.viewModel)
                    .transition(.identity)
            case let .readyToConfirm(quote):
                SendConfirmView(viewModel: self.viewModel, quote: quote)
                    .transition(.opacity.combined(with: .move(edge: .trailing)))
            case .signing, .broadcasting, .confirming, .confirmed, .expired, .failed:
                SendStatusView(viewModel: self.viewModel)
                    .transition(.opacity)
            }
        }
        .animation(self.reduceMotion ? nil : .smooth(duration: 0.22), value: self.viewModel.state)
    }
}

#if DEBUG

private actor PreviewNoopNavigatorService: SendAssetsService {
    func quote(_ request: SendRequest, tier: PriorityTier) async throws -> SendQuote {
        throw SendError.canceled
    }

    func send(quote: SendQuote) async throws -> SendOutcome {
        throw SendError.canceled
    }

    func resync(walletId: UUID) async -> [Signature: SendOutcome] { [:] }
}

@MainActor
private func makeNavigatorPreviewVM() -> SendViewModel {
    let address = try! WalletAddress(base58: "So11111111111111111111111111111111111111112")
    let intent = SendIntent(walletId: UUID(), from: address, asset: .sol)
    return SendViewModel(
        intent: intent,
        cluster: .mainnet,
        service: PreviewNoopNavigatorService(),
        onDismiss: {})
}

#Preview("SendNavigator - input state") {
    SendNavigator(viewModel: makeNavigatorPreviewVM())
        .frame(width: 380, height: 520)
}

#endif
