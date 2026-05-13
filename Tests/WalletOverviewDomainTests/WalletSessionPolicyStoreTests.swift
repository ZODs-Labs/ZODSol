import Foundation
import XCTest
@testable import WalletOverviewDomain

private struct DefaultsFixture: @unchecked Sendable {
    let defaults: UserDefaults
    let suiteName: String
    let key: String
}

private func makeFixture() -> DefaultsFixture {
    let suiteName = "WalletSessionPolicyStoreTests-\(UUID().uuidString)"
    let defaults = UserDefaults(suiteName: suiteName)!
    defaults.removePersistentDomain(forName: suiteName)
    return DefaultsFixture(
        defaults: defaults,
        suiteName: suiteName,
        key: "test.session.policy.\(UUID().uuidString)")
}

private func cleanup(_ fixture: DefaultsFixture) {
    fixture.defaults.removePersistentDomain(forName: fixture.suiteName)
}

final class WalletSessionPolicyStoreTests: XCTestCase {
    func test_load_returnsDefault_whenNothingPersisted() async {
        let fixture = makeFixture(); defer { cleanup(fixture) }
        let store = WalletSessionPolicyStore(defaults: fixture.defaults, key: fixture.key)
        let policy = await store.load()
        XCTAssertEqual(policy, .default)
    }

    func test_saveLoadRoundTrip_preservesEveryField() async {
        let fixture = makeFixture(); defer { cleanup(fixture) }
        let store = WalletSessionPolicyStore(defaults: fixture.defaults, key: fixture.key)
        let policy = WalletSession.Policy(
            trigger: .afterIdle(minutes: 5),
            lockOnSystemSleep: false,
            lockOnScreenLock: true)
        await store.save(policy)

        let loaded = await store.load()
        XCTAssertEqual(loaded, policy)
    }

    func test_load_falsifiesCorruptedJSON_returnsDefault() async {
        let fixture = makeFixture(); defer { cleanup(fixture) }
        fixture.defaults.set(Data("not-json".utf8), forKey: fixture.key)

        let store = WalletSessionPolicyStore(defaults: fixture.defaults, key: fixture.key)
        let policy = await store.load()
        XCTAssertEqual(policy, .default)
    }

    func test_immediately_triggerSurvivesRoundTrip() async {
        let fixture = makeFixture(); defer { cleanup(fixture) }
        let store = WalletSessionPolicyStore(defaults: fixture.defaults, key: fixture.key)
        let policy = WalletSession.Policy(
            trigger: .immediately, lockOnSystemSleep: true, lockOnScreenLock: true)
        await store.save(policy)
        let loaded = await store.load()
        XCTAssertEqual(loaded.trigger, .immediately)
    }

    func test_untilAppQuit_triggerSurvivesRoundTrip() async {
        let fixture = makeFixture(); defer { cleanup(fixture) }
        let store = WalletSessionPolicyStore(defaults: fixture.defaults, key: fixture.key)
        let policy = WalletSession.Policy(
            trigger: .untilAppQuit, lockOnSystemSleep: false, lockOnScreenLock: false)
        await store.save(policy)
        let loaded = await store.load()
        XCTAssertEqual(loaded, policy)
    }

    /// Pre-rename builds wrote the screen-lock flag under `lockOnScreensaver`.
    /// Any policy persisted by those builds must still decode so the user
    /// does not silently lose their choice on the next launch.
    func test_legacyScreensaverKey_decodesIntoScreenLock() async {
        let fixture = makeFixture(); defer { cleanup(fixture) }
        let legacyJSON = """
        {
          "trigger": {"immediately": {}},
          "lockOnSystemSleep": true,
          "lockOnScreensaver": false
        }
        """
        fixture.defaults.set(Data(legacyJSON.utf8), forKey: fixture.key)

        let store = WalletSessionPolicyStore(defaults: fixture.defaults, key: fixture.key)
        let loaded = await store.load()
        XCTAssertEqual(loaded.trigger, .immediately)
        XCTAssertTrue(loaded.lockOnSystemSleep)
        XCTAssertFalse(loaded.lockOnScreenLock)
    }
}
