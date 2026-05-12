import Foundation
import SolanaKit
import WalletOverviewDomain
import XCTest
@testable import WalletOverviewUI

/// Coverage for `WalletOverviewViewModel.handleAssetPicked`, the routing seam
/// the asset picker drives. The view itself is exercised indirectly: it calls
/// the same entry point with a `PortfolioRow`.
final class AssetPickerViewModelTests: XCTestCase {
    @MainActor
    func test_handleAssetPicked_send_setsRouteToSendIntent() async throws {
        let (walletStore, identity) = try await TestWalletStoreFactory.makeWithWallet()
        let viewModel = self.makeViewModel(walletStore: walletStore)

        viewModel.panelDidAppear()
        await self.waitUntil { viewModel.activeWalletId == identity.id }

        viewModel.route = .assetPicker(AssetPickerIntent(
            walletId: identity.id,
            from: identity.address,
            mode: .send))

        let solRow = PortfolioRow.sol(
            balance: Lamports(rawValue: 1_500_000_000), price: nil, change: nil)
        viewModel.handleAssetPicked(solRow)

        guard case let .send(sendIntent) = viewModel.route else {
            return XCTFail("Expected route to transition to .send")
        }
        XCTAssertEqual(sendIntent.walletId, identity.id)
        XCTAssertEqual(sendIntent.from, identity.address)
        guard case .sol = sendIntent.asset else {
            return XCTFail("Expected asset to be .sol for a native row")
        }
        XCTAssertNil(viewModel.pendingReceiveAsset)
    }

    @MainActor
    func test_handleAssetPicked_receive_setsRouteToReceiveAndPendingAsset() async throws {
        let (walletStore, identity) = try await TestWalletStoreFactory.makeWithWallet()
        let viewModel = self.makeViewModel(walletStore: walletStore)

        viewModel.panelDidAppear()
        await self.waitUntil { viewModel.activeWalletId == identity.id }

        let receiveIntent = ReceiveIntent(
            walletId: identity.id, address: identity.address, network: .mainnet)
        viewModel.route = .assetPicker(AssetPickerIntent(
            walletId: identity.id,
            from: identity.address,
            mode: .receive(receiveIntent)))

        let usdcRow = self.makeUSDCRow()
        viewModel.handleAssetPicked(usdcRow)

        guard case let .receive(routed) = viewModel.route else {
            return XCTFail("Expected route to transition to .receive")
        }
        XCTAssertEqual(routed, receiveIntent)
        XCTAssertEqual(viewModel.pendingReceiveAsset, usdcRow)
    }

    @MainActor
    func test_handleAssetPicked_outsideAssetPickerRoute_isNoOp() async throws {
        let (walletStore, identity) = try await TestWalletStoreFactory.makeWithWallet()
        let viewModel = self.makeViewModel(walletStore: walletStore)

        viewModel.panelDidAppear()
        await self.waitUntil { viewModel.activeWalletId == identity.id }

        XCTAssertEqual(viewModel.route, .overview)
        let solRow = PortfolioRow.sol(
            balance: Lamports(rawValue: 1), price: nil, change: nil)
        viewModel.handleAssetPicked(solRow)

        XCTAssertEqual(viewModel.route, .overview)
        XCTAssertNil(viewModel.pendingReceiveAsset)
    }

    @MainActor
    func test_handleAssetPicked_send_withSPLToken_routesWithSPLAsset() async throws {
        let (walletStore, identity) = try await TestWalletStoreFactory.makeWithWallet()
        let viewModel = self.makeViewModel(walletStore: walletStore)

        viewModel.panelDidAppear()
        await self.waitUntil { viewModel.activeWalletId == identity.id }

        viewModel.route = .assetPicker(AssetPickerIntent(
            walletId: identity.id,
            from: identity.address,
            mode: .send))

        let usdcRow = self.makeUSDCRow()
        viewModel.handleAssetPicked(usdcRow)

        guard case let .send(sendIntent) = viewModel.route else {
            return XCTFail("Expected route to transition to .send")
        }
        XCTAssertEqual(sendIntent.walletId, identity.id)
        guard case let .splToken(mint, decimals, symbol, _) = sendIntent.asset else {
            return XCTFail("Expected asset to be .splToken for a non-native row")
        }
        XCTAssertEqual(mint.base58, usdcRow.id)
        XCTAssertEqual(decimals, 6)
        XCTAssertEqual(symbol, "USDC")
    }

    // MARK: - Helpers

    @MainActor
    private func makeViewModel(walletStore: WalletStore) -> WalletOverviewViewModel {
        WalletOverviewViewModel(
            service: MockWalletOverviewService(),
            walletStore: walletStore,
            apiKeyStore: MockAPIKeyStore(key: "key"),
            sendService: MockSendAssetsService(),
            network: .mainnet)
    }

    private func makeUSDCRow() -> PortfolioRow {
        // Canonical USDC mainnet mint. Picked because it round-trips through
        // `Mint(base58:)` cleanly, so the `splToken` branch is reached.
        let mintBase58 = "EPjFWdd5AufqSSqeM2qN1xzybapC8G4wEGGkZwyTDt1v"
        return PortfolioRow(
            id: mintBase58,
            symbol: "USDC",
            name: "USD Coin",
            imageURL: nil,
            amount: TokenAmount(amount: 1_000_000, decimals: 6),
            pricePerToken: 1,
            usdValue: 1,
            priceChange24h: nil,
            isNative: false,
            tokenProgram: nil)
    }

    @MainActor
    private func waitUntil(
        timeout: TimeInterval = 2.0,
        _ condition: @MainActor () -> Bool
    ) async {
        let deadline = Date().addingTimeInterval(timeout)
        while !condition(), Date() < deadline {
            try? await Task.sleep(for: .milliseconds(10))
        }
    }
}
