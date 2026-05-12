import Foundation
import XCTest
@testable import WalletOverviewDomain

/// Mutable clock the session can consult deterministically.
private final class FakeClock: @unchecked Sendable {
    private let lock = NSLock()
    private var current: Date

    init(_ start: Date = Date(timeIntervalSince1970: 1_700_000_000)) {
        self.current = start
    }

    func now() -> Date {
        self.lock.lock(); defer { self.lock.unlock() }
        return self.current
    }

    func advance(seconds: TimeInterval) {
        self.lock.lock(); defer { self.lock.unlock() }
        self.current = self.current.addingTimeInterval(seconds)
    }
}

final class WalletSessionTests: XCTestCase {
    // MARK: - Caching

    func test_cacheThenWithSeed_returnsCachedSeed() async throws {
        let clock = FakeClock()
        let session = WalletSession(
            policy: .init(
                trigger: .afterIdle(minutes: 15),
                lockOnSystemSleep: true,
                lockOnScreensaver: true),
            nowProvider: { clock.now() })
        let walletId = UUID()
        let seed = Data(repeating: 0x42, count: 32)

        await session.cache(walletId: walletId, seed: seed)

        let captured: Data? = try await session.withSeed(walletId: walletId) { buffer in
            buffer
        }
        XCTAssertEqual(captured, seed)
    }

    func test_withSeed_returnsNil_whenNoEntry() async throws {
        let session = WalletSession()
        let result: Data? = try await session.withSeed(walletId: UUID()) { $0 }
        XCTAssertNil(result)
    }

    func test_isUnlocked_falseWhenNoEntry() async {
        let session = WalletSession()
        let result = await session.isUnlocked(walletId: UUID())
        XCTAssertFalse(result)
    }

    func test_isUnlocked_trueAfterCache() async {
        let session = WalletSession()
        let walletId = UUID()
        await session.cache(walletId: walletId, seed: Data(repeating: 1, count: 32))
        let result = await session.isUnlocked(walletId: walletId)
        XCTAssertTrue(result)
    }

    // MARK: - Idle expiry

    func test_idle_expiresAfterConfiguredWindow() async throws {
        let clock = FakeClock()
        let session = WalletSession(
            policy: .init(
                trigger: .afterIdle(minutes: 5),
                lockOnSystemSleep: true,
                lockOnScreensaver: true),
            nowProvider: { clock.now() })
        let walletId = UUID()
        await session.cache(walletId: walletId, seed: Data(repeating: 7, count: 32))

        clock.advance(seconds: 4 * 60)
        let stillFresh = await session.isUnlocked(walletId: walletId)
        XCTAssertTrue(stillFresh)

        clock.advance(seconds: 60 + 1) // total elapsed > 5 minutes
        let expired = await session.isUnlocked(walletId: walletId)
        XCTAssertFalse(expired)

        // Access after expiry returns nil so the caller falls back to Keychain.
        let result: Data? = try await session.withSeed(walletId: walletId) { $0 }
        XCTAssertNil(result)
    }

    func test_lastUsedAt_slidesForwardOnAccess() async throws {
        let clock = FakeClock()
        let session = WalletSession(
            policy: .init(
                trigger: .afterIdle(minutes: 5),
                lockOnSystemSleep: true,
                lockOnScreensaver: true),
            nowProvider: { clock.now() })
        let walletId = UUID()
        await session.cache(walletId: walletId, seed: Data(repeating: 9, count: 32))

        // Three accesses, each 4 minutes apart. Total elapsed = 12 min but
        // the idle window resets on every access, so the entry stays fresh.
        for _ in 0..<3 {
            clock.advance(seconds: 4 * 60)
            let value: Data? = try await session.withSeed(walletId: walletId) { $0 }
            XCTAssertNotNil(value)
        }
    }

    // MARK: - Policy.immediately

    func test_immediatelyPolicy_skipsCaching() async {
        let session = WalletSession(
            policy: .init(
                trigger: .immediately,
                lockOnSystemSleep: true,
                lockOnScreensaver: true))
        let walletId = UUID()
        await session.cache(walletId: walletId, seed: Data(repeating: 5, count: 32))
        let count = await session.unlockedWalletCount()
        XCTAssertEqual(count, 0)
    }

    // MARK: - Policy.untilPanelClose / untilAppQuit

    func test_untilPanelClose_doesNotExpireOnIdle() async {
        let clock = FakeClock()
        let session = WalletSession(
            policy: .init(
                trigger: .untilPanelClose,
                lockOnSystemSleep: true,
                lockOnScreensaver: true),
            nowProvider: { clock.now() })
        let walletId = UUID()
        await session.cache(walletId: walletId, seed: Data(repeating: 3, count: 32))

        clock.advance(seconds: 24 * 60 * 60) // a day later
        let stillUnlocked = await session.isUnlocked(walletId: walletId)
        XCTAssertTrue(stillUnlocked)
    }

    func test_untilPanelClose_locksOnPanelDisappear() async {
        let session = WalletSession(
            policy: .init(
                trigger: .untilPanelClose,
                lockOnSystemSleep: true,
                lockOnScreensaver: true))
        let walletId = UUID()
        await session.cache(walletId: walletId, seed: Data(repeating: 3, count: 32))

        await session.handlePanelDidDisappear()
        let unlocked = await session.isUnlocked(walletId: walletId)
        XCTAssertFalse(unlocked)
    }

    func test_untilAppQuit_doesNotLockOnPanelDisappear() async {
        let session = WalletSession(
            policy: .init(
                trigger: .untilAppQuit,
                lockOnSystemSleep: true,
                lockOnScreensaver: true))
        let walletId = UUID()
        await session.cache(walletId: walletId, seed: Data(repeating: 3, count: 32))

        await session.handlePanelDidDisappear()
        let unlocked = await session.isUnlocked(walletId: walletId)
        XCTAssertTrue(unlocked)
    }

    // MARK: - System events

    func test_systemSleep_locksWhenEnabled() async {
        let session = WalletSession(policy: .init(
            trigger: .untilAppQuit, lockOnSystemSleep: true, lockOnScreensaver: false))
        let walletId = UUID()
        await session.cache(walletId: walletId, seed: Data(repeating: 1, count: 32))
        await session.handleSystemSleep()
        let result = await session.isUnlocked(walletId: walletId)
        XCTAssertFalse(result)
    }

    func test_systemSleep_isNoOpWhenDisabled() async {
        let session = WalletSession(policy: .init(
            trigger: .untilAppQuit, lockOnSystemSleep: false, lockOnScreensaver: false))
        let walletId = UUID()
        await session.cache(walletId: walletId, seed: Data(repeating: 1, count: 32))
        await session.handleSystemSleep()
        let result = await session.isUnlocked(walletId: walletId)
        XCTAssertTrue(result)
    }

    func test_screensaver_locksWhenEnabled() async {
        let session = WalletSession(policy: .init(
            trigger: .untilAppQuit, lockOnSystemSleep: false, lockOnScreensaver: true))
        let walletId = UUID()
        await session.cache(walletId: walletId, seed: Data(repeating: 1, count: 32))
        await session.handleScreensaver()
        let result = await session.isUnlocked(walletId: walletId)
        XCTAssertFalse(result)
    }

    func test_screensaver_isNoOpWhenDisabled() async {
        let session = WalletSession(policy: .init(
            trigger: .untilAppQuit, lockOnSystemSleep: false, lockOnScreensaver: false))
        let walletId = UUID()
        await session.cache(walletId: walletId, seed: Data(repeating: 1, count: 32))
        await session.handleScreensaver()
        let result = await session.isUnlocked(walletId: walletId)
        XCTAssertTrue(result)
    }

    // MARK: - lockAll and lock(walletId:)

    func test_lockAll_clearsEveryEntry() async {
        let session = WalletSession()
        let a = UUID()
        let b = UUID()
        await session.cache(walletId: a, seed: Data(repeating: 1, count: 32))
        await session.cache(walletId: b, seed: Data(repeating: 2, count: 32))
        await session.lockAll()
        let count = await session.unlockedWalletCount()
        XCTAssertEqual(count, 0)
    }

    func test_lockSingle_clearsOnlyThatWallet() async {
        let session = WalletSession()
        let a = UUID()
        let b = UUID()
        await session.cache(walletId: a, seed: Data(repeating: 1, count: 32))
        await session.cache(walletId: b, seed: Data(repeating: 2, count: 32))
        await session.lock(walletId: a)
        let unlockedA = await session.isUnlocked(walletId: a)
        let unlockedB = await session.isUnlocked(walletId: b)
        XCTAssertFalse(unlockedA)
        XCTAssertTrue(unlockedB)
    }

    // MARK: - setPolicy

    func test_setPolicy_immediatelyPurgesAllEntries() async {
        let session = WalletSession()
        let walletId = UUID()
        await session.cache(walletId: walletId, seed: Data(repeating: 1, count: 32))
        await session.setPolicy(.init(
            trigger: .immediately, lockOnSystemSleep: true, lockOnScreensaver: true))
        let result = await session.isUnlocked(walletId: walletId)
        XCTAssertFalse(result)
    }

    func test_setPolicy_tightensIdle_purgesAlreadyExpired() async {
        let clock = FakeClock()
        let session = WalletSession(
            policy: .init(
                trigger: .afterIdle(minutes: 60),
                lockOnSystemSleep: true,
                lockOnScreensaver: true),
            nowProvider: { clock.now() })
        let walletId = UUID()
        await session.cache(walletId: walletId, seed: Data(repeating: 7, count: 32))
        clock.advance(seconds: 10 * 60)
        let stillFresh = await session.isUnlocked(walletId: walletId)
        XCTAssertTrue(stillFresh)

        await session.setPolicy(.init(
            trigger: .afterIdle(minutes: 5),
            lockOnSystemSleep: true,
            lockOnScreensaver: true))
        let expiredAfterTighten = await session.isUnlocked(walletId: walletId)
        XCTAssertFalse(expiredAfterTighten)
    }

    // MARK: - Defensive copy / zeroization

    func test_cache_makesDefensiveCopy() async throws {
        let session = WalletSession()
        let walletId = UUID()
        var seed = Data(repeating: 0xAA, count: 32)
        await session.cache(walletId: walletId, seed: seed)
        // Mutate the original; the cached copy must be unaffected.
        seed.resetBytes(in: 0..<seed.count)
        let captured: Data? = try await session.withSeed(walletId: walletId) { $0 }
        XCTAssertEqual(captured, Data(repeating: 0xAA, count: 32))
    }

    func test_withSeed_zeroesWorkingCopyAfterClosure() async throws {
        let session = WalletSession()
        let walletId = UUID()
        await session.cache(walletId: walletId, seed: Data(repeating: 0xBB, count: 32))

        // The cache must still hold the seed after the closure completes -
        // we zero only the per-call working copy, not the canonical entry.
        _ = try await session.withSeed(walletId: walletId) { buffer in
            buffer.resetBytes(in: 0..<buffer.count)
            return 0
        }
        let again: Data? = try await session.withSeed(walletId: walletId) { $0 }
        XCTAssertEqual(again, Data(repeating: 0xBB, count: 32))
    }
}
