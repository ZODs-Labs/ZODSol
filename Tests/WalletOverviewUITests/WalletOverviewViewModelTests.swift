import Foundation
import XCTest
import SolanaKit
import WalletOverviewDomain
@testable import WalletOverviewUI

final class WalletOverviewViewModelTests: XCTestCase {

    @MainActor
    func testInitialStateIsIdle() {
        let viewModel = makeViewModel()

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
        let viewModel = makeViewModel(apiKeyStore: apiKeyStore)

        viewModel.panelDidAppear()
        await waitUntil { !viewModel.hasAPIKey && viewModel.wallets.isEmpty }
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
        let viewModel = makeViewModel(apiKeyStore: apiKeyStore)

        viewModel.panelDidAppear()
        await waitUntil { viewModel.hasAPIKey }
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
    func testPanelDidDisappearIsSafeToCallRepeatedly() async {
        let viewModel = makeViewModel()

        viewModel.panelDidAppear()
        viewModel.panelDidDisappear()
        viewModel.panelDidDisappear()

        // Reaching this point without crash confirms cancellation is idempotent.
        XCTAssertTrue(true)
    }

    @MainActor
    func testSetAPIKeyMarksHasAPIKey() async throws {
        let apiKeyStore = MockAPIKeyStore(key: nil)
        let viewModel = makeViewModel(apiKeyStore: apiKeyStore)

        XCTAssertFalse(viewModel.hasAPIKey)
        try await viewModel.setAPIKey("new-helius-key")

        XCTAssertTrue(viewModel.hasAPIKey)
        let stored = try await apiKeyStore.currentKey()
        XCTAssertEqual(stored, "new-helius-key")
    }

    @MainActor
    func testClearAPIKeyResetsHasAPIKey() async throws {
        let apiKeyStore = MockAPIKeyStore(key: "existing-key")
        let viewModel = makeViewModel(apiKeyStore: apiKeyStore)

        try await viewModel.setAPIKey("existing-key")
        XCTAssertTrue(viewModel.hasAPIKey)

        await viewModel.clearAPIKey()

        XCTAssertFalse(viewModel.hasAPIKey)
        let stored = try await apiKeyStore.currentKey()
        XCTAssertNil(stored)
    }

    @MainActor
    func testRefreshWithoutActiveWalletDoesNothing() async {
        let service = MockWalletOverviewService(loadResult: .loading)
        let viewModel = makeViewModel(service: service)

        await viewModel.refresh()

        let calls = await service.loadCallCount
        XCTAssertEqual(calls, 0, "refresh() must short-circuit when no wallet is active")
        if case .idle = viewModel.state {
            // expected — state must not move
        } else {
            XCTFail("Expected state to remain .idle when no wallet is active")
        }
    }

    // MARK: - Helpers

    @MainActor
    private func makeViewModel(
        service: MockWalletOverviewService? = nil,
        apiKeyStore: MockAPIKeyStore? = nil
    ) -> WalletOverviewViewModel {
        return WalletOverviewViewModel(
            service: service ?? MockWalletOverviewService(),
            walletStore: TestWalletStoreFactory.makeEmpty(),
            apiKeyStore: apiKeyStore ?? MockAPIKeyStore()
        )
    }

    @MainActor
    private func waitUntil(
        timeout: TimeInterval = 2.0,
        _ condition: @MainActor () -> Bool
    ) async {
        let deadline = Date().addingTimeInterval(timeout)
        while !condition() && Date() < deadline {
            try? await Task.sleep(for: .milliseconds(10))
        }
    }
}
