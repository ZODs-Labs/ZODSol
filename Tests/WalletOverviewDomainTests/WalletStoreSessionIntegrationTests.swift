import Foundation
import KeychainKit
import XCTest
@testable import WalletOverviewDomain

/// Proves the session vault short-circuits the Keychain on cache hits.
///
/// These tests do not require `ZODSOL_KEYCHAIN_TEST=1` and **must not**
/// invoke `LAContext` - they inject `StaticBiometricAuthenticator` so the
/// fallback Keychain read path runs without prompting the developer's
/// Touch ID sensor on every `swift test` invocation.
private struct Fixture {
    let store: WalletStore
    let session: WalletSession
    let secureStore: SecureItemStore
    let defaultsSuiteName: String
    let service: String
}

private func makeFixture(
    policy: WalletSession.Policy = .init(
        trigger: .untilAppQuit,
        lockOnSystemSleep: true,
        lockOnScreenLock: true),
    nowProvider: @Sendable @escaping () -> Date = { Date() }) -> Fixture
{
    let unique = UUID().uuidString
    let service = "dev.zods.zodsol.test.\(unique)"
    let suiteName = "WalletStoreSession.\(unique)"
    let defaults = UserDefaults(suiteName: suiteName)!
    defaults.removePersistentDomain(forName: suiteName)
    // `.allow` so the fallback path proceeds to `SecItemCopyMatching` (which
    // returns errSecItemNotFound on these empty test services) without
    // invoking LAContext. Touch ID never engages during the suite.
    let secureStore = SecureItemStore(
        service: service,
        authenticator: StaticBiometricAuthenticator(.allow))
    let session = WalletSession(policy: policy, nowProvider: nowProvider)
    let store = WalletStore(
        secureStore: secureStore,
        defaults: defaults,
        service: service,
        selectedWalletKey: "test.selectedWalletId.\(unique)",
        session: session)
    return Fixture(
        store: store,
        session: session,
        secureStore: secureStore,
        defaultsSuiteName: suiteName,
        service: service)
}

private func cleanup(_ fixture: Fixture) {
    UserDefaults.standard.removePersistentDomain(forName: fixture.defaultsSuiteName)
}

final class WalletStoreSessionIntegrationTests: XCTestCase {
    func test_withPrivateKey_returnsCachedSeed_withoutKeychainRead() async throws {
        let fixture = makeFixture()
        let walletId = UUID()
        let seed = Data(repeating: 0x33, count: 64)
        await fixture.session.cache(walletId: walletId, seed: seed)

        let captured: Data = try await fixture.store.withPrivateKey(
            walletId: walletId, prompt: "Sign Solana transfer")
        { buffer in
            buffer
        }
        XCTAssertEqual(captured, seed)
        cleanup(fixture)
    }

    func test_idleExpiry_fallsBackToKeychain_whichThrowsBiometricInvalidated() async throws {
        // After cache expiry the fast path returns nil, so withPrivateKey
        // proceeds to read the Keychain. Without a stored entry the read
        // throws itemNotFound, which the store translates to
        // biometricInvalidated. This proves the fallback path executes.
        let clock = FakeFixtureClock()
        let fixture = makeFixture(
            policy: .init(
                trigger: .afterIdle(minutes: 1),
                lockOnSystemSleep: true,
                lockOnScreenLock: true),
            nowProvider: { clock.now() })

        let walletId = UUID()
        await fixture.session.cache(walletId: walletId, seed: Data(repeating: 0x44, count: 64))
        clock.advance(seconds: 2 * 60)

        do {
            _ = try await fixture.store.withPrivateKey(walletId: walletId, prompt: "x") { buf in buf }
            XCTFail("expected biometricInvalidated for missing keychain item")
        } catch let error as WalletOverviewError {
            XCTAssertEqual(error, .biometricInvalidated)
        }
        cleanup(fixture)
    }

    func test_lockNow_evictsCache_andSubsequentReadFallsBackToKeychain() async throws {
        let fixture = makeFixture()
        let walletId = UUID()
        await fixture.session.cache(walletId: walletId, seed: Data(repeating: 0x55, count: 64))

        let firstHit: Data = try await fixture.store.withPrivateKey(
            walletId: walletId, prompt: "x") { $0 }
        XCTAssertEqual(firstHit.count, 64)

        await fixture.session.lockAll()

        do {
            _ = try await fixture.store.withPrivateKey(walletId: walletId, prompt: "x") { $0 }
            XCTFail("expected fallback Keychain read to fail (no stored item)")
        } catch let error as WalletOverviewError {
            XCTAssertEqual(error, .biometricInvalidated)
        }
        cleanup(fixture)
    }
}

private final class FakeFixtureClock: @unchecked Sendable {
    private let lock = NSLock()
    private var current: Date = .init(timeIntervalSince1970: 1_700_000_000)

    func now() -> Date {
        self.lock.lock(); defer { self.lock.unlock() }
        return self.current
    }

    func advance(seconds: TimeInterval) {
        self.lock.lock(); defer { self.lock.unlock() }
        self.current = self.current.addingTimeInterval(seconds)
    }
}
