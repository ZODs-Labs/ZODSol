import Foundation
import WalletOverviewDomain
import XCTest
@testable import WalletOverviewUI

private enum MockLoginItemError: Error { case refused }

/// Thread-safe stub. `LaunchAtLoginViewModel.setEnabled` calls `enable`/
/// `disable` off the main actor via `Task.detached`, so every field is guarded.
private final class MockLoginItem: LoginItemManaging, @unchecked Sendable {
    private struct State {
        var status: LoginItemStatus
        var enableCount = 0
        var disableCount = 0
        var openSettingsCount = 0
        var enableThrows = false
        var disableThrows = false
    }

    private let lock = NSLock()
    private var state: State

    init(status: LoginItemStatus, enableThrows: Bool = false, disableThrows: Bool = false) {
        self.state = State(status: status, enableThrows: enableThrows, disableThrows: disableThrows)
    }

    func currentStatus() -> LoginItemStatus {
        self.lock.withLock { self.state.status }
    }

    func enable() throws {
        try self.lock.withLock {
            self.state.enableCount += 1
            if self.state.enableThrows { throw MockLoginItemError.refused }
            self.state.status = .enabled
        }
    }

    func disable() throws {
        try self.lock.withLock {
            self.state.disableCount += 1
            if self.state.disableThrows { throw MockLoginItemError.refused }
            self.state.status = .notRegistered
        }
    }

    func openSettings() {
        self.lock.withLock { self.state.openSettingsCount += 1 }
    }

    var enableCount: Int {
        self.lock.withLock { self.state.enableCount }
    }

    var disableCount: Int {
        self.lock.withLock { self.state.disableCount }
    }

    var openSettingsCount: Int {
        self.lock.withLock { self.state.openSettingsCount }
    }

    func setStatus(_ status: LoginItemStatus) {
        self.lock.withLock { self.state.status = status }
    }
}

private func makeDefaults() -> UserDefaults {
    let suiteName = "LaunchAtLoginViewModelTests-\(UUID().uuidString)"
    let defaults = UserDefaults(suiteName: suiteName)!
    defaults.removePersistentDomain(forName: suiteName)
    return defaults
}

@MainActor
private func makeModel(
    item: MockLoginItem,
    defaults: UserDefaults) -> LaunchAtLoginViewModel
{
    LaunchAtLoginViewModel(item: item, defaults: defaults, didAutoEnableKey: "test.launchAtLogin.didAutoEnable")
}

@MainActor
final class LaunchAtLoginViewModelTests: XCTestCase {
    // MARK: - First-run default-on

    func testFirstRunRegistersWhenNotRegistered() {
        let item = MockLoginItem(status: .notRegistered)
        let model = makeModel(item: item, defaults: makeDefaults())

        model.activateDefaultOnFirstRun()

        XCTAssertEqual(item.enableCount, 1)
        XCTAssertTrue(model.isEnabled)
        XCTAssertEqual(model.status, .enabled)
    }

    func testFirstRunIsOneShotAcrossInstances() {
        let defaults = makeDefaults()
        let first = MockLoginItem(status: .notRegistered)
        makeModel(item: first, defaults: defaults).activateDefaultOnFirstRun()
        XCTAssertEqual(first.enableCount, 1)

        // A later launch with the item back to notRegistered (e.g. the user
        // turned it off) must not re-register.
        let second = MockLoginItem(status: .notRegistered)
        makeModel(item: second, defaults: defaults).activateDefaultOnFirstRun()

        XCTAssertEqual(second.enableCount, 0)
    }

    func testFirstRunRegistersWhenNotFound() {
        // A fresh install can report `.notFound` before it has ever registered;
        // default-on must still register in that state.
        let item = MockLoginItem(status: .notFound)
        let model = makeModel(item: item, defaults: makeDefaults())

        model.activateDefaultOnFirstRun()

        XCTAssertEqual(item.enableCount, 1)
        XCTAssertTrue(model.isEnabled)
    }

    func testFirstRunSkipsWhenAlreadyEnabled() {
        let item = MockLoginItem(status: .enabled)
        let model = makeModel(item: item, defaults: makeDefaults())

        model.activateDefaultOnFirstRun()

        XCTAssertEqual(item.enableCount, 0)
        XCTAssertTrue(model.isEnabled)
    }

    func testFirstRunSkipsWhenRequiresApproval() {
        let item = MockLoginItem(status: .requiresApproval)
        let model = makeModel(item: item, defaults: makeDefaults())

        model.activateDefaultOnFirstRun()

        XCTAssertEqual(item.enableCount, 0)
        XCTAssertTrue(model.needsApproval)
        XCTAssertFalse(model.isEnabled)
    }

    // MARK: - User toggle

    func testSetEnabledTrueRegisters() async {
        let item = MockLoginItem(status: .notRegistered)
        let model = makeModel(item: item, defaults: makeDefaults())

        await model.setEnabled(true)

        XCTAssertEqual(item.enableCount, 1)
        XCTAssertTrue(model.isEnabled)
        XCTAssertNil(model.lastErrorMessage)
    }

    func testSetEnabledFalseUnregisters() async {
        let item = MockLoginItem(status: .enabled)
        let model = makeModel(item: item, defaults: makeDefaults())

        await model.setEnabled(false)

        XCTAssertEqual(item.disableCount, 1)
        XCTAssertFalse(model.isEnabled)
        XCTAssertEqual(model.status, .notRegistered)
    }

    func testSetEnabledFailureSurfacesMessageAndReconcilesStatus() async {
        let item = MockLoginItem(status: .notRegistered, enableThrows: true)
        let model = makeModel(item: item, defaults: makeDefaults())

        await model.setEnabled(true)

        XCTAssertNotNil(model.lastErrorMessage)
        // Optimistic flip must be reconciled back to the true system state.
        XCTAssertFalse(model.isEnabled)
        XCTAssertEqual(model.status, .notRegistered)
    }

    func testSetEnabledBenignThrowReachingGoalShowsNoError() async {
        // Unregistering something already off throws (job-not-found) but leaves
        // the system in the intended state, so no error should surface.
        let item = MockLoginItem(status: .notRegistered, disableThrows: true)
        let model = makeModel(item: item, defaults: makeDefaults())

        await model.setEnabled(false)

        XCTAssertNil(model.lastErrorMessage)
        XCTAssertFalse(model.isEnabled)
        XCTAssertEqual(model.status, .notRegistered)
    }

    // MARK: - Settings deep link

    func testOpenLoginItemsSettingsDelegatesToItem() {
        let item = MockLoginItem(status: .requiresApproval)
        let model = makeModel(item: item, defaults: makeDefaults())

        model.openLoginItemsSettings()

        XCTAssertEqual(item.openSettingsCount, 1)
    }

    // MARK: - Status sync

    func testRefreshReadsLiveSystemStatus() {
        let item = MockLoginItem(status: .notRegistered)
        let model = makeModel(item: item, defaults: makeDefaults())
        XCTAssertFalse(model.isEnabled)

        item.setStatus(.enabled)
        model.refresh()

        XCTAssertTrue(model.isEnabled)
    }

    func testNeedsApprovalReflectsStatus() {
        let item = MockLoginItem(status: .requiresApproval)
        let model = makeModel(item: item, defaults: makeDefaults())

        XCTAssertTrue(model.needsApproval)
        XCTAssertFalse(model.isEnabled)
    }
}
