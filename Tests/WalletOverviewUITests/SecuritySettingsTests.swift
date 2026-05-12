import Foundation
import WalletOverviewDomain
import XCTest
@testable import WalletOverviewUI

/// Behavior tests for the session-related additions on `WalletOverviewViewModel`
/// and the `AutoLockOption` mapping used by `SecuritySettingsView`.
final class SecuritySettingsTests: XCTestCase {
    // MARK: - AutoLockOption mapping

    func test_autoLockOption_immediately_maps() {
        XCTAssertEqual(AutoLockOption.immediately.trigger, .immediately)
        XCTAssertTrue(AutoLockOption.immediately.matches(.immediately))
        XCTAssertFalse(AutoLockOption.immediately.matches(.afterIdle(minutes: 5)))
    }

    func test_autoLockOption_after5min_matchesExactMinutes() {
        XCTAssertEqual(AutoLockOption.after5min.trigger, .afterIdle(minutes: 5))
        XCTAssertTrue(AutoLockOption.after5min.matches(.afterIdle(minutes: 5)))
        XCTAssertFalse(AutoLockOption.after5min.matches(.afterIdle(minutes: 15)))
    }

    func test_autoLockOption_after15min_matchesExactMinutes() {
        XCTAssertEqual(AutoLockOption.after15min.trigger, .afterIdle(minutes: 15))
        XCTAssertTrue(AutoLockOption.after15min.matches(.afterIdle(minutes: 15)))
    }

    func test_autoLockOption_after1hour_isSixtyMinutes() {
        XCTAssertEqual(AutoLockOption.after1hour.trigger, .afterIdle(minutes: 60))
        XCTAssertTrue(AutoLockOption.after1hour.matches(.afterIdle(minutes: 60)))
    }

    func test_autoLockOption_untilPanelClose_maps() {
        XCTAssertEqual(AutoLockOption.untilPanelClose.trigger, .untilPanelClose)
        XCTAssertTrue(AutoLockOption.untilPanelClose.matches(.untilPanelClose))
    }

    func test_autoLockOption_untilAppQuit_maps() {
        XCTAssertEqual(AutoLockOption.untilAppQuit.trigger, .untilAppQuit)
        XCTAssertTrue(AutoLockOption.untilAppQuit.matches(.untilAppQuit))
    }

    func test_autoLockOption_unknownIdle_doesNotMatchAnyOption() {
        // Idle window the UI does not expose (e.g. legacy persisted value).
        for option in AutoLockOption.allCases {
            XCTAssertFalse(
                option.matches(.afterIdle(minutes: 3)),
                "\(option) should not match an unknown idle window")
        }
    }

    func test_autoLockOption_allCasesCoverAllUITriggers() {
        // Sanity: every UI radio option produces a distinct trigger value.
        let triggers = AutoLockOption.allCases.map(\.trigger)
        XCTAssertEqual(Set(triggers.map(String.init(describing:))).count, AutoLockOption.allCases.count)
    }

    // MARK: - View-model session wiring

    @MainActor
    func test_updateSessionPolicy_appliesToSessionAndPersists() async {
        let suiteName = "SecuritySettingsTests-\(UUID().uuidString)"
        let policyStore = makePolicyStore(suiteName: suiteName)
        let session = WalletSession(policy: .default)
        let viewModel = self.makeViewModel(session: session, sessionPolicyStore: policyStore)

        let newPolicy = WalletSession.Policy(
            trigger: .afterIdle(minutes: 5),
            lockOnSystemSleep: false,
            lockOnScreensaver: true)
        await viewModel.updateSessionPolicy(newPolicy)

        XCTAssertEqual(viewModel.sessionPolicy, newPolicy)
        let persisted = await policyStore.load()
        XCTAssertEqual(persisted, newPolicy)
        let onSession = await session.currentPolicy()
        XCTAssertEqual(onSession, newPolicy)

        UserDefaults.standard.removePersistentDomain(forName: suiteName)
    }

    @MainActor
    func test_lockNow_clearsCachedSeeds() async {
        let session = WalletSession(policy: .init(
            trigger: .untilAppQuit, lockOnSystemSleep: true, lockOnScreensaver: true))
        let viewModel = self.makeViewModel(session: session)
        let walletId = UUID()
        await session.cache(walletId: walletId, seed: Data(repeating: 0x77, count: 32))

        viewModel.lockNow()

        // lockNow dispatches a Task, so spin until isUnlocked flips.
        let deadline = Date().addingTimeInterval(2.0)
        var isUnlocked = await session.isUnlocked(walletId: walletId)
        while isUnlocked, Date() < deadline {
            try? await Task.sleep(for: .milliseconds(10))
            isUnlocked = await session.isUnlocked(walletId: walletId)
        }
        XCTAssertFalse(isUnlocked)
    }

    @MainActor
    func test_panelDidDisappear_locksWhenPolicyIsUntilPanelClose() async {
        let session = WalletSession(policy: .init(
            trigger: .untilPanelClose, lockOnSystemSleep: true, lockOnScreensaver: true))
        let viewModel = self.makeViewModel(session: session)
        let walletId = UUID()
        await session.cache(walletId: walletId, seed: Data(repeating: 0x88, count: 32))

        viewModel.panelDidDisappear()

        let deadline = Date().addingTimeInterval(2.0)
        var isUnlocked = await session.isUnlocked(walletId: walletId)
        while isUnlocked, Date() < deadline {
            try? await Task.sleep(for: .milliseconds(10))
            isUnlocked = await session.isUnlocked(walletId: walletId)
        }
        XCTAssertFalse(isUnlocked)
    }

    @MainActor
    func test_panelDidDisappear_doesNotLockWhenPolicyIsUntilAppQuit() async {
        let session = WalletSession(policy: .init(
            trigger: .untilAppQuit, lockOnSystemSleep: true, lockOnScreensaver: true))
        let viewModel = self.makeViewModel(session: session)
        let walletId = UUID()
        await session.cache(walletId: walletId, seed: Data(repeating: 0x99, count: 32))

        viewModel.panelDidDisappear()
        // Give the dispatched task time to run.
        try? await Task.sleep(for: .milliseconds(50))

        let isUnlocked = await session.isUnlocked(walletId: walletId)
        XCTAssertTrue(isUnlocked)
    }

    @MainActor
    func test_loadInitialState_hydratesSessionPolicyFromStore() async {
        let suiteName = "SecuritySettingsTests-\(UUID().uuidString)"
        let policyStore = makePolicyStore(suiteName: suiteName)
        let persisted = WalletSession.Policy(
            trigger: .afterIdle(minutes: 60),
            lockOnSystemSleep: false,
            lockOnScreensaver: false)
        await policyStore.save(persisted)

        let session = WalletSession(policy: .default)
        let viewModel = self.makeViewModel(session: session, sessionPolicyStore: policyStore)

        viewModel.panelDidAppear()
        let deadline = Date().addingTimeInterval(2.0)
        while viewModel.sessionPolicy != persisted, Date() < deadline {
            try? await Task.sleep(for: .milliseconds(10))
        }
        viewModel.panelDidDisappear()

        XCTAssertEqual(viewModel.sessionPolicy, persisted)
        UserDefaults.standard.removePersistentDomain(forName: suiteName)
    }

    // MARK: - Helpers

    @MainActor
    private func makeViewModel(
        session: WalletSession? = nil,
        sessionPolicyStore: WalletSessionPolicyStore? = nil) -> WalletOverviewViewModel
    {
        WalletOverviewViewModel(
            service: MockWalletOverviewService(),
            walletStore: TestWalletStoreFactory.makeEmpty(),
            apiKeyStore: MockAPIKeyStore(),
            sendService: MockSendAssetsService(),
            network: .mainnet,
            session: session,
            sessionPolicyStore: sessionPolicyStore)
    }
}

/// Build a `WalletSessionPolicyStore` whose `UserDefaults` is created and
/// then immediately released. Swift 6 sending checks pass because the
/// `defaults` instance never escapes this scope - only the actor that owns it.
private func makePolicyStore(suiteName: String) -> WalletSessionPolicyStore {
    let defaults = UserDefaults(suiteName: suiteName)!
    defaults.removePersistentDomain(forName: suiteName)
    return WalletSessionPolicyStore(defaults: defaults, key: "test.session.policy")
}
