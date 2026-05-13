import Foundation
import SolanaKit
import WalletOverviewDomain
import XCTest
@testable import WalletOverviewUI

final class WalletOverviewViewModelTests: XCTestCase {
    @MainActor
    func testInitialStateIsIdle() {
        let viewModel = self.makeViewModel()

        if case .idle = viewModel.state {
            // expected
        } else {
            XCTFail("Expected initial state to be .idle")
        }
        XCTAssertEqual(viewModel.wallets, [])
        XCTAssertNil(viewModel.activeWalletId)
        XCTAssertFalse(viewModel.hasAPIKey)
    }

    @MainActor
    func testPanelDidAppearWithNoAPIKeyLeavesStateIdle() async {
        let apiKeyStore = MockAPIKeyStore(key: nil)
        let viewModel = self.makeViewModel(apiKeyStore: apiKeyStore)

        viewModel.panelDidAppear()
        await self.waitUntil { !viewModel.hasAPIKey && viewModel.wallets.isEmpty }
        viewModel.panelDidDisappear()

        XCTAssertFalse(viewModel.hasAPIKey)
        XCTAssertTrue(viewModel.wallets.isEmpty)
        if case .idle = viewModel.state {
            // expected
        } else {
            XCTFail("Expected state to remain .idle when no API key is present")
        }
    }

    @MainActor
    func testPanelDidAppearWithAPIKeyButNoWalletsKeepsStateIdle() async {
        let apiKeyStore = MockAPIKeyStore(key: "helius-test-key")
        let viewModel = self.makeViewModel(apiKeyStore: apiKeyStore)

        viewModel.panelDidAppear()
        await self.waitUntil { viewModel.hasAPIKey }
        viewModel.panelDidDisappear()

        XCTAssertTrue(viewModel.hasAPIKey)
        XCTAssertTrue(viewModel.wallets.isEmpty)
        XCTAssertNil(viewModel.activeWalletId)
        if case .idle = viewModel.state {
            // expected — no wallets means we never transition past idle
        } else {
            XCTFail("Expected state to remain .idle when no wallets are present")
        }
    }

    @MainActor
    func testPanelDidDisappearIsSafeToCallRepeatedly() {
        let viewModel = self.makeViewModel()

        viewModel.panelDidAppear()
        viewModel.panelDidDisappear()
        viewModel.panelDidDisappear()

        // Reaching this point without crash confirms cancellation is idempotent.
        XCTAssertTrue(true)
    }

    @MainActor
    func testSetAPIKeyMarksHasAPIKey() async throws {
        let apiKeyStore = MockAPIKeyStore(key: nil)
        let viewModel = self.makeViewModel(apiKeyStore: apiKeyStore)

        XCTAssertFalse(viewModel.hasAPIKey)
        try await viewModel.setAPIKey("new-helius-key")

        XCTAssertTrue(viewModel.hasAPIKey)
        let stored = try await apiKeyStore.currentKey()
        XCTAssertEqual(stored, "new-helius-key")
    }

    @MainActor
    func testClearAPIKeyResetsHasAPIKey() async throws {
        let apiKeyStore = MockAPIKeyStore(key: "existing-key")
        let viewModel = self.makeViewModel(apiKeyStore: apiKeyStore)

        try await viewModel.setAPIKey("existing-key")
        XCTAssertTrue(viewModel.hasAPIKey)

        await viewModel.clearAPIKey()

        XCTAssertFalse(viewModel.hasAPIKey)
        let stored = try await apiKeyStore.currentKey()
        XCTAssertNil(stored)
    }

    @MainActor
    func testClearAPIKeyFromUnauthorizedStateReturnsToEditableSetup() async throws {
        let apiKeyStore = MockAPIKeyStore(key: "bad-key")
        let service = MockWalletOverviewService(loadResult: .failed(.unauthorized))
        let (walletStore, identity) = try await TestWalletStoreFactory.makeWithWallet()
        let viewModel = self.makeViewModel(
            service: service,
            walletStore: walletStore,
            apiKeyStore: apiKeyStore)

        viewModel.panelDidAppear()
        await self.waitUntil { viewModel.activeWalletId == identity.id && viewModel.hasAPIKey }
        await viewModel.refresh()

        guard case .failed(.unauthorized) = viewModel.state else {
            return XCTFail("Expected unauthorized failure before recovery")
        }

        await viewModel.clearAPIKey()

        XCTAssertFalse(viewModel.hasAPIKey)
        XCTAssertEqual(viewModel.activeWalletId, identity.id)
        if case .idle = viewModel.state {
            // expected — the panel can render onboarding/API-key entry again.
        } else {
            XCTFail("Expected state to reset to .idle after clearing API key")
        }
    }

    @MainActor
    func testReplacingAPIKeyWithActiveWalletReloadsPortfolio() async throws {
        let apiKeyStore = MockAPIKeyStore(key: nil)
        let service = MockWalletOverviewService(loadResult: .failed(.unauthorized))
        let (walletStore, identity) = try await TestWalletStoreFactory.makeWithWallet()
        let viewModel = self.makeViewModel(
            service: service,
            walletStore: walletStore,
            apiKeyStore: apiKeyStore)

        viewModel.panelDidAppear()
        await self.waitUntil { viewModel.activeWalletId == identity.id }

        try await viewModel.setAPIKey("replacement-key")

        XCTAssertTrue(viewModel.hasAPIKey)
        XCTAssertEqual(viewModel.activeWalletId, identity.id)
        let invalidations = await service.invalidateAllCallCount
        XCTAssertEqual(invalidations, 1)
        if case .loading = viewModel.state {
            // expected — stale unauthorized screen is replaced by a fresh load.
        } else {
            XCTFail("Expected replacement API key to trigger a loading state")
        }
    }

    @MainActor
    func testRefreshWithoutActiveWalletDoesNothing() async {
        let service = MockWalletOverviewService(loadResult: .loading)
        let viewModel = self.makeViewModel(service: service)

        await viewModel.refresh()

        let calls = await service.loadCallCount
        XCTAssertEqual(calls, 0, "refresh() must short-circuit when no wallet is active")
        if case .idle = viewModel.state {
            // expected — state must not move
        } else {
            XCTFail("Expected state to remain .idle when no wallet is active")
        }
    }

    // MARK: - Routing (Wave 2)

    @MainActor
    func testHandleHeaderSendSetsRouteToAssetPickerSend() async throws {
        let (walletStore, identity) = try await TestWalletStoreFactory.makeWithWallet()
        let apiKeyStore = MockAPIKeyStore(key: "key")
        let viewModel = self.makeViewModel(walletStore: walletStore, apiKeyStore: apiKeyStore)

        viewModel.panelDidAppear()
        await self.waitUntil { viewModel.activeWalletId == identity.id }

        viewModel.handleHeaderSend()

        guard case let .assetPicker(intent) = viewModel.route else {
            return XCTFail("Expected route to be .assetPicker after handleHeaderSend")
        }
        XCTAssertEqual(intent.walletId, identity.id)
        XCTAssertEqual(intent.from, identity.address)
        XCTAssertEqual(intent.mode, .send)
    }

    @MainActor
    func testHandleHeaderReceiveSetsRouteToReceive() async throws {
        let (walletStore, identity) = try await TestWalletStoreFactory.makeWithWallet()
        let apiKeyStore = MockAPIKeyStore(key: "key")
        let viewModel = self.makeViewModel(walletStore: walletStore, apiKeyStore: apiKeyStore)

        viewModel.panelDidAppear()
        await self.waitUntil { viewModel.activeWalletId == identity.id }

        viewModel.handleHeaderReceive()

        guard case let .receive(intent) = viewModel.route else {
            return XCTFail("Expected route to be .receive after handleHeaderReceive")
        }
        XCTAssertEqual(intent.walletId, identity.id)
        XCTAssertEqual(intent.address, identity.address)
        XCTAssertEqual(intent.network, .mainnet)
    }

    @MainActor
    func testHandleAssetPickedSendSetsRouteToSend() async throws {
        let (walletStore, identity) = try await TestWalletStoreFactory.makeWithWallet()
        let apiKeyStore = MockAPIKeyStore(key: "key")
        let viewModel = self.makeViewModel(walletStore: walletStore, apiKeyStore: apiKeyStore)

        viewModel.panelDidAppear()
        await self.waitUntil { viewModel.activeWalletId == identity.id }

        viewModel.handleHeaderSend()
        let solRow = PortfolioRow.sol(
            balance: Lamports(rawValue: 1_000_000_000), price: nil, change: nil)
        viewModel.handleAssetPicked(solRow)

        guard case let .send(intent) = viewModel.route else {
            return XCTFail("Expected route to be .send after handleAssetPicked")
        }
        XCTAssertEqual(intent.walletId, identity.id)
        XCTAssertEqual(intent.from, identity.address)
        if case .sol = intent.asset {
            // expected
        } else {
            XCTFail("Expected asset to be .sol")
        }
    }

    @MainActor
    func testHandleAssetPickedReceiveSetsRouteToReceiveAndStashesAsset() async throws {
        let (walletStore, identity) = try await TestWalletStoreFactory.makeWithWallet()
        let apiKeyStore = MockAPIKeyStore(key: "key")
        let viewModel = self.makeViewModel(walletStore: walletStore, apiKeyStore: apiKeyStore)

        viewModel.panelDidAppear()
        await self.waitUntil { viewModel.activeWalletId == identity.id }

        let receiveIntent = ReceiveIntent(
            walletId: identity.id, address: identity.address, network: .mainnet)
        viewModel.route = .assetPicker(AssetPickerIntent(
            walletId: identity.id,
            from: identity.address,
            mode: .receive(receiveIntent)))
        let solRow = PortfolioRow.sol(
            balance: Lamports(rawValue: 2_000_000_000), price: nil, change: nil)
        viewModel.handleAssetPicked(solRow)

        guard case let .receive(intent) = viewModel.route else {
            return XCTFail("Expected route to be .receive after handleAssetPicked")
        }
        XCTAssertEqual(intent, receiveIntent)
        XCTAssertEqual(viewModel.pendingReceiveAsset, solRow)
    }

    @MainActor
    func testHandleAssetPickedOutsideAssetPickerRouteIsNoOp() async throws {
        let (walletStore, identity) = try await TestWalletStoreFactory.makeWithWallet()
        let apiKeyStore = MockAPIKeyStore(key: "key")
        let viewModel = self.makeViewModel(walletStore: walletStore, apiKeyStore: apiKeyStore)

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
    func testPanelDidAppearShowsPendingSendBannerWhenResyncReturnsTerminalOutcome() async throws {
        let (walletStore, identity) = try await TestWalletStoreFactory.makeWithWallet()
        let apiKeyStore = MockAPIKeyStore(key: "key")
        let sendService = MockSendAssetsService()
        let signatureBytes = Data(repeating: 7, count: 64)
        let signature = try Signature(bytes: signatureBytes)
        await sendService.setResyncResults([
            PendingSendResolution(
                signature: signature,
                outcome: .confirmed(signature, slot: 100),
                createdAt: Date(timeIntervalSince1970: 10)),
        ])

        let viewModel = self.makeViewModel(
            walletStore: walletStore, apiKeyStore: apiKeyStore, sendService: sendService)

        viewModel.panelDidAppear()
        await self.waitUntil { viewModel.activeWalletId == identity.id }
        try? await Task.sleep(for: .milliseconds(20))

        XCTAssertEqual(viewModel.pendingSendBanner, PendingSendDisplayInfo(signature: signature, outcome: .confirmed(signature, slot: 100)))
    }

    @MainActor
    func testPanelDidAppearPicksOldestPendingSendResolutionDeterministically() async throws {
        let (walletStore, identity) = try await TestWalletStoreFactory.makeWithWallet()
        let apiKeyStore = MockAPIKeyStore(key: "key")
        let sendService = MockSendAssetsService()
        let older = try Signature(bytes: Data(repeating: 8, count: 64))
        let newer = try Signature(bytes: Data(repeating: 9, count: 64))
        await sendService.setResyncResults([
            PendingSendResolution(
                signature: newer,
                outcome: .confirmed(newer, slot: 200),
                createdAt: Date(timeIntervalSince1970: 20)),
            PendingSendResolution(
                signature: older,
                outcome: .confirmed(older, slot: 100),
                createdAt: Date(timeIntervalSince1970: 10)),
        ])

        let viewModel = self.makeViewModel(
            walletStore: walletStore, apiKeyStore: apiKeyStore, sendService: sendService)

        viewModel.panelDidAppear()
        await self.waitUntil { viewModel.activeWalletId == identity.id }
        try? await Task.sleep(for: .milliseconds(20))

        XCTAssertEqual(viewModel.pendingSendBanner, PendingSendDisplayInfo(signature: older, outcome: .confirmed(older, slot: 100)))
    }

    @MainActor
    func testCanSendOrReceiveIsFalseUntilOverviewLoads() async throws {
        let (walletStore, identity) = try await TestWalletStoreFactory.makeWithWallet()
        let apiKeyStore = MockAPIKeyStore(key: "key")
        let overview = WalletOverview(
            walletId: identity.id,
            address: identity.address,
            solBalance: Lamports(rawValue: 0),
            solPriceUSD: nil,
            solChange24h: nil,
            tokens: [],
            nfts: NFTSummary(count: 0, collectionPreviews: []),
            totalUSD: nil,
            totalChange24h: nil,
            asOf: Date(),
            isPartial: false)
        let loaded: LoadState<WalletOverview> = .loaded(overview, lastRefreshed: Date())
        let service = MockWalletOverviewService(
            loadResult: loaded,
            streamStates: [loaded])
        let viewModel = self.makeViewModel(
            service: service, walletStore: walletStore, apiKeyStore: apiKeyStore)

        XCTAssertFalse(viewModel.canSendOrReceive)

        viewModel.panelDidAppear()
        await self.waitUntil {
            if case .loaded = viewModel.state { return viewModel.activeWalletId == identity.id }
            return false
        }

        XCTAssertTrue(viewModel.canSendOrReceive)
    }

    @MainActor
    func testPanelDidAppearClearsPendingSendBannerWhenResyncReturnsNothing() async throws {
        let (walletStore, identity) = try await TestWalletStoreFactory.makeWithWallet()
        let apiKeyStore = MockAPIKeyStore(key: "key")
        let sendService = MockSendAssetsService()
        await sendService.setResyncResults([])

        let viewModel = self.makeViewModel(
            walletStore: walletStore, apiKeyStore: apiKeyStore, sendService: sendService)

        viewModel.panelDidAppear()
        await self.waitUntil { viewModel.activeWalletId == identity.id }
        try? await Task.sleep(for: .milliseconds(20))

        XCTAssertNil(viewModel.pendingSendBanner)
    }

    // MARK: - Helpers

    @MainActor
    private func makeViewModel(
        service: MockWalletOverviewService? = nil,
        walletStore: WalletStore? = nil,
        apiKeyStore: MockAPIKeyStore? = nil,
        sendService: MockSendAssetsService? = nil) -> WalletOverviewViewModel
    {
        WalletOverviewViewModel(
            service: service ?? MockWalletOverviewService(),
            walletStore: walletStore ?? TestWalletStoreFactory.makeEmpty(),
            apiKeyStore: apiKeyStore ?? MockAPIKeyStore(),
            sendService: sendService ?? MockSendAssetsService(),
            network: .mainnet)
    }

    @MainActor
    private func waitUntil(
        timeout: TimeInterval = 2.0,
        _ condition: @MainActor () -> Bool) async
    {
        let deadline = Date().addingTimeInterval(timeout)
        while !condition(), Date() < deadline {
            try? await Task.sleep(for: .milliseconds(10))
        }
    }
}
