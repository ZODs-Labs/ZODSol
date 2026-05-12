import SwiftUI
import WalletOverviewDomain

public struct WalletPanelView: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Bindable private var viewModel: WalletOverviewViewModel

    public init(viewModel: WalletOverviewViewModel) {
        self.viewModel = viewModel
    }

    public var body: some View {
        content
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .onAppear { viewModel.panelDidAppear() }
            .onDisappear { viewModel.panelDidDisappear() }
    }

    @ViewBuilder
    private var content: some View {
        if !viewModel.hasAPIKey || viewModel.wallets.isEmpty {
            OnboardingView(viewModel: viewModel)
        } else {
            // Inline routes — the panel is the navigation surface. No
            // sheets, no popovers; every screen is rendered into the same
            // panel window.
            ZStack {
                switch viewModel.route {
                case .overview:
                    overviewBody
                        .transition(transitionForOverview)
                case .switcher:
                    WalletSwitcherView(viewModel: viewModel)
                        .transition(.push)
                case .manage:
                    ManageWalletsView(viewModel: viewModel)
                        .transition(.push)
                case .rename(let walletId):
                    RenameWalletView(viewModel: viewModel, walletId: walletId)
                        .transition(.push)
                case .addWallet:
                    AddWalletView(viewModel: viewModel)
                        .transition(.push)
                case let .send(intent):
                    SendNavigator(viewModel: makeSendViewModel(intent: intent))
                        .transition(.push)
                case let .assetPicker(intent):
                    AssetPickerView(intent: intent, viewModel: viewModel)
                        .transition(.push)
                case let .receive(intent):
                    ReceiveNavigator(viewModel: makeReceiveViewModel(intent: intent), parent: viewModel)
                        .transition(.push)
                }
            }
            .animation(reduceMotion ? nil : .easeInOut(duration: 0.22), value: viewModel.route)
        }
    }

    @ViewBuilder
    private var overviewBody: some View {
        switch viewModel.state {
        case .idle, .loading:
            LoadingView()
        case .loaded(let overview, _):
            WalletOverviewContentView(
                viewModel: viewModel,
                overview: overview
            )
        case .partial(let overview, _):
            WalletOverviewContentView(
                viewModel: viewModel,
                overview: overview
            )
        case .failed(let error):
            ErrorView(error: error, viewModel: viewModel)
        }
    }

    private func makeSendViewModel(intent: SendIntent) -> SendViewModel {
        let sendVM = SendViewModel(
            intent: intent,
            cluster: viewModel.network,
            service: viewModel.sendService,
            onDismiss: { [viewModel] in viewModel.route = .overview }
        )
        // Clear the pending handoff so a route bounce does not re-trigger it.
        // Wave 3G wires this signature into a real preloadConfirming(_:) call.
        viewModel.preloadConfirmingSignature = nil
        return sendVM
    }

    private func makeReceiveViewModel(intent: ReceiveIntent) -> ReceiveViewModel {
        ReceiveViewModel(intent: intent, cluster: viewModel.network)
    }

    private var transitionForOverview: AnyTransition {
        // When returning to overview from a deeper route, slide from the
        // leading edge to match native macOS navigation feel.
        .asymmetric(
            insertion: .move(edge: .leading).combined(with: .opacity),
            removal: .move(edge: .leading).combined(with: .opacity)
        )
    }
}

private extension AnyTransition {
    /// Pushed-onto-stack style for deeper routes — slides from trailing edge.
    static var push: AnyTransition {
        .asymmetric(
            insertion: .move(edge: .trailing).combined(with: .opacity),
            removal: .move(edge: .trailing).combined(with: .opacity)
        )
    }
}
