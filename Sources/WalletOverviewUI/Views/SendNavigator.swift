import SolanaKit
import SwiftUI
import WalletOverviewDomain

/// Host for the send flow. Owns one `SendViewModel` in `@State` so polling-
/// driven re-renders of the panel never recreate it mid-flight - clicking
/// Review must not reset the form back to the input screen.
struct SendNavigator: View {
    @State private var viewModel: SendViewModel
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    init(intent: SendIntent, parent: WalletOverviewViewModel) {
        _viewModel = State(wrappedValue: Self.makeViewModel(intent: intent, parent: parent))
    }

    #if DEBUG
    init(viewModel: SendViewModel) {
        _viewModel = State(wrappedValue: viewModel)
    }
    #endif

    var body: some View {
        @Bindable var viewModel = self.viewModel
        ZStack {
            switch viewModel.state {
            case .input, .quoting:
                // Keep the input form mounted while quoting so the user
                // never loses sight of what they typed. The Review button
                // shows the spinner instead.
                SendInputView(viewModel: viewModel)
                    .transition(.identity)
            case let .readyToConfirm(quote):
                SendConfirmView(viewModel: viewModel, quote: quote)
                    .transition(.opacity.combined(with: .move(edge: .trailing)))
            case .signing, .broadcasting, .confirming, .confirmed, .expired, .failed:
                SendStatusView(viewModel: viewModel)
                    .transition(.opacity)
            }
        }
        .animation(self.reduceMotion ? nil : .smooth(duration: 0.22), value: viewModel.state)
    }

    @MainActor
    private static func makeViewModel(
        intent: SendIntent,
        parent: WalletOverviewViewModel) -> SendViewModel
    {
        let lookup: @MainActor (Mint) -> (decimals: UInt8, symbol: String, name: String)? = { [weak parent] mint in
            guard let parent else { return nil }
            return Self.splInfo(for: mint, in: parent.state)
        }
        let onDismiss: @MainActor () -> Void = { [weak parent] in
            parent?.route = .overview
        }
        let sendVM = SendViewModel(
            intent: intent,
            cluster: parent.network,
            service: parent.sendService,
            onDismiss: onDismiss,
            recentRecipientsStore: parent.recentRecipientsStore,
            splTokenLookup: lookup)
        if let row = Self.findPortfolioRow(for: intent.asset, in: parent.state) {
            sendVM.assetBalanceBaseUnits = row.amount.amount
            sendVM.assetPriceUSD = row.pricePerToken
        }
        if let signature = parent.preloadConfirmingSignature {
            sendVM.preloadConfirming(signature: signature)
            parent.preloadConfirmingSignature = nil
        }
        return sendVM
    }

    private static func splInfo(
        for mint: Mint,
        in state: LoadState<WalletOverview>) -> (decimals: UInt8, symbol: String, name: String)?
    {
        let overview: WalletOverview
        switch state {
        case let .loaded(value, _): overview = value
        case let .partial(value, _): overview = value
        default: return nil
        }
        guard let asset = overview.tokens.first(where: { $0.id == mint }) else { return nil }
        let symbol = asset.symbol ?? "token"
        let name = asset.name ?? symbol
        return (decimals: asset.amount.decimals, symbol: symbol, name: name)
    }

    private static func findPortfolioRow(
        for asset: SendAssetKind,
        in state: LoadState<WalletOverview>) -> PortfolioRow?
    {
        let overview: WalletOverview
        switch state {
        case let .loaded(value, _):
            overview = value
        case let .partial(value, _):
            overview = value
        default:
            return nil
        }
        switch asset {
        case .sol:
            return .sol(
                balance: overview.solBalance,
                price: overview.solPriceUSD,
                change: overview.solChange24h)
        case let .splToken(mint, _, _, _):
            let mintBase58 = mint.base58
            guard let match = overview.tokens.first(where: { $0.id.base58 == mintBase58 }) else {
                return nil
            }
            return PortfolioRow.from(match)
        }
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

    func resync(walletId: UUID) async -> [Signature: SendOutcome] {
        [:]
    }
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
