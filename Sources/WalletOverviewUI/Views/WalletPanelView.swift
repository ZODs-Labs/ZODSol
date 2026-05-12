import SolanaKit
import SwiftUI
import WalletOverviewDomain

public struct WalletPanelView: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Bindable private var viewModel: WalletOverviewViewModel

    public init(viewModel: WalletOverviewViewModel) {
        self.viewModel = viewModel
    }

    public var body: some View {
        self.content
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .onAppear { self.viewModel.panelDidAppear() }
            .onDisappear { self.viewModel.panelDidDisappear() }
    }

    @ViewBuilder
    private var content: some View {
        if !self.viewModel.hasAPIKey || self.viewModel.wallets.isEmpty {
            OnboardingView(viewModel: self.viewModel)
        } else {
            // Inline routes — the panel is the navigation surface. No
            // sheets, no popovers; every screen is rendered into the same
            // panel window.
            ZStack {
                switch self.viewModel.route {
                case .overview:
                    self.overviewBody
                        .transition(self.transitionForOverview)
                case .switcher:
                    WalletSwitcherView(viewModel: self.viewModel)
                        .transition(.push)
                case .manage:
                    ManageWalletsView(viewModel: self.viewModel)
                        .transition(.push)
                case let .rename(walletId):
                    RenameWalletView(viewModel: self.viewModel, walletId: walletId)
                        .transition(.push)
                case .addWallet:
                    AddWalletView(viewModel: self.viewModel)
                        .transition(.push)
                case let .send(intent):
                    SendNavigator(viewModel: self.makeSendViewModel(intent: intent))
                        .transition(.push)
                case let .assetPicker(intent):
                    AssetPickerView(intent: intent, viewModel: self.viewModel)
                        .transition(.push)
                case let .receive(intent):
                    ReceiveNavigator(viewModel: self.makeReceiveViewModel(intent: intent), parent: self.viewModel)
                        .transition(.push)
                }
            }
            .animation(self.reduceMotion ? nil : .easeInOut(duration: 0.22), value: self.viewModel.route)
        }
    }

    @ViewBuilder
    private var overviewBody: some View {
        switch self.viewModel.state {
        case .idle, .loading:
            LoadingView()
        case let .loaded(overview, _):
            WalletOverviewContentView(
                viewModel: self.viewModel,
                overview: overview)
        case let .partial(overview, _):
            WalletOverviewContentView(
                viewModel: self.viewModel,
                overview: overview)
        case let .failed(error):
            ErrorView(error: error, viewModel: self.viewModel)
        }
    }

    private func makeSendViewModel(intent: SendIntent) -> SendViewModel {
        let sendVM = SendViewModel(
            intent: intent,
            cluster: viewModel.network,
            service: self.viewModel.sendService,
            onDismiss: { [viewModel] in viewModel.route = .overview },
            recentRecipientsStore: self.viewModel.recentRecipientsStore)
        if let row = findPortfolioRow(for: intent.asset) {
            sendVM.assetBalanceBaseUnits = row.amount.amount
            sendVM.assetPriceUSD = row.pricePerToken
        }
        if let signature = viewModel.preloadConfirmingSignature {
            sendVM.preloadConfirming(signature: signature)
            self.viewModel.preloadConfirmingSignature = nil
        }
        return sendVM
    }

    private func findPortfolioRow(for asset: SendAssetKind) -> PortfolioRow? {
        let overview: WalletOverview
        switch self.viewModel.state {
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

    private func makeReceiveViewModel(intent: ReceiveIntent) -> ReceiveViewModel {
        ReceiveViewModel(intent: intent, cluster: self.viewModel.network)
    }

    private var transitionForOverview: AnyTransition {
        // When returning to overview from a deeper route, slide from the
        // leading edge to match native macOS navigation feel.
        .asymmetric(
            insertion: .move(edge: .leading).combined(with: .opacity),
            removal: .move(edge: .leading).combined(with: .opacity))
    }
}

extension AnyTransition {
    /// Pushed-onto-stack style for deeper routes — slides from trailing edge.
    fileprivate static var push: AnyTransition {
        .asymmetric(
            insertion: .move(edge: .trailing).combined(with: .opacity),
            removal: .move(edge: .trailing).combined(with: .opacity))
    }
}
