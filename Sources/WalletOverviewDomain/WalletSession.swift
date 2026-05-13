import Foundation
import OSLog

/// In-process unlock vault for wallet signing seeds.
///
/// After a successful biometric prompt in `WalletStore.withPrivateKey`, the
/// decrypted 32-byte seed is cached here so subsequent sends within the
/// active unlock window do not have to re-read the Keychain - and therefore
/// do not re-trigger Touch ID nor the legacy login-keychain ACL prompts that
/// ad-hoc-signed builds suffer from on every signing identity change.
///
/// Locking is driven by:
///   - Explicit `lock(walletId:)` / `lockAll()` from the UI ("Lock now").
///   - Idle expiry: each access updates `lastUsedAt` and any call that lands
///     after `lastUsedAt + idle` finds the entry already purged.
///   - System sleep - the app layer calls `handleSystemSleep()`.
///   - Real screen lock (user invoked Lock Screen) - `handleScreenLock()`.
///   - Panel close when policy is `.untilPanelClose`.
///
/// Display sleep (energy-saver dimming the panel after a couple minutes idle)
/// is deliberately not a lock trigger. It is a power event, not a security
/// event - the user is still sitting in front of the Mac and forcing a
/// re-prompt every time the screen dims defeats the cache.
///
/// Top-level so the type lives at nesting depth 0 (SwiftLint's nesting rule
/// rejects `WalletSession.Policy.Trigger` at depth 2). Aliased back into
/// `WalletSession.Policy` below for ergonomic call sites.
public enum WalletSessionLockTrigger: Sendable, Codable, Equatable {
    case immediately
    case afterIdle(minutes: Int)
    case untilPanelClose
    case untilAppQuit
}

public actor WalletSession {
    public struct Policy: Sendable, Equatable {
        public var trigger: WalletSessionLockTrigger
        public var lockOnSystemSleep: Bool
        public var lockOnScreenLock: Bool

        public static let `default` = Policy(
            trigger: .afterIdle(minutes: 15),
            lockOnSystemSleep: true,
            lockOnScreenLock: true)

        public init(
            trigger: WalletSessionLockTrigger,
            lockOnSystemSleep: Bool,
            lockOnScreenLock: Bool)
        {
            self.trigger = trigger
            self.lockOnSystemSleep = lockOnSystemSleep
            self.lockOnScreenLock = lockOnScreenLock
        }
    }

    private struct Entry {
        var seed: Data
        var unlockedAt: Date
        var lastUsedAt: Date
    }

    private var entries: [UUID: Entry] = [:]
    private var policy: Policy
    private let nowProvider: @Sendable () -> Date
    private let logger = Logger(subsystem: "dev.zods.zodsol", category: "wallet-session")

    public init(
        policy: Policy = .default,
        nowProvider: @Sendable @escaping () -> Date = { Date() })
    {
        self.policy = policy
        self.nowProvider = nowProvider
    }

    // MARK: - Policy

    public func currentPolicy() -> Policy {
        self.policy
    }

    /// Update the policy. Any cached entries that the new policy would have
    /// already invalidated are purged immediately.
    public func setPolicy(_ policy: Policy) {
        self.policy = policy
        if case .immediately = policy.trigger {
            self.lockAllLocked()
            return
        }
        self.purgeExpiredLocked()
    }

    // MARK: - Cache lifecycle

    /// Stash a freshly-read seed. The caller owns the source buffer and is
    /// responsible for zeroizing it after this call returns. We hold an
    /// independent copy in actor memory.
    public func cache(walletId: UUID, seed: Data) {
        guard self.cachingEnabled else {
            self.logger.notice(
                "session unlock skipped (policy=.immediately) wallet=\(walletId.uuidString, privacy: .public)")
            return
        }
        let now = self.nowProvider()
        if var prior = self.entries[walletId] {
            prior.seed.resetBytes(in: 0..<prior.seed.count)
            self.entries[walletId] = nil
            _ = prior
        }
        let copy = Data(seed)
        self.entries[walletId] = Entry(seed: copy, unlockedAt: now, lastUsedAt: now)
        self.logger.notice("session unlocked wallet=\(walletId.uuidString, privacy: .public)")
    }

    /// `true` iff a seed is cached AND the policy still considers it valid.
    /// Always purges stale entries as a side effect.
    public func isUnlocked(walletId: UUID) -> Bool {
        guard let entry = entries[walletId] else { return false }
        if self.isExpired(entry, at: self.nowProvider()) {
            self.zeroize(walletId: walletId)
            return false
        }
        return true
    }

    /// Run `body` against the cached seed if any. Returns `nil` if the entry
    /// is missing or expired; callers fall back to Keychain in that case.
    /// Updates `lastUsedAt` on a hit so the idle window slides forward.
    ///
    /// The closure receives a defensive mutable copy that is zeroized on exit.
    public func withSeed<R: Sendable>(
        walletId: UUID,
        _ body: @Sendable (inout Data) async throws -> R) async throws -> R?
    {
        guard self.isUnlocked(walletId: walletId) else {
            self.logger.notice(
                "session cache MISS wallet=\(walletId.uuidString, privacy: .public) - falling back to Keychain")
            return nil
        }
        guard var entry = entries[walletId] else { return nil }
        entry.lastUsedAt = self.nowProvider()
        self.entries[walletId] = entry

        var working = Data(entry.seed)
        defer { working.resetBytes(in: 0..<working.count) }
        self.logger.notice(
            "session cache HIT wallet=\(walletId.uuidString, privacy: .public) - skipping Keychain")
        return try await body(&working)
    }

    // MARK: - Locking

    public func lock(walletId: UUID) {
        self.zeroize(walletId: walletId)
    }

    public func lockAll() {
        self.lockAllLocked()
    }

    /// Called by the app when the panel disappears. No-op unless the active
    /// policy says to lock on panel close.
    public func handlePanelDidDisappear() {
        if case .untilPanelClose = self.policy.trigger {
            self.lockAllLocked()
        }
    }

    /// Called by the app on `NSWorkspace.willSleepNotification`.
    public func handleSystemSleep() {
        if self.policy.lockOnSystemSleep {
            self.lockAllLocked()
        }
    }

    /// Called by the app when the user actively locks the screen
    /// (`com.apple.screenIsLocked` distributed notification). Distinct from
    /// display sleep, which is intentionally not wired to anything.
    public func handleScreenLock() {
        if self.policy.lockOnScreenLock {
            self.lockAllLocked()
        }
    }

    // MARK: - Introspection (test affordances)

    public func unlockedWalletCount() -> Int {
        self.purgeExpiredLocked()
        return self.entries.count
    }

    // MARK: - Private

    /// Whether the policy allows holding seeds in memory at all.
    private var cachingEnabled: Bool {
        if case .immediately = self.policy.trigger { return false }
        return true
    }

    private func isExpired(_ entry: Entry, at now: Date) -> Bool {
        switch self.policy.trigger {
        case .immediately:
            return true
        case let .afterIdle(minutes):
            let idleSeconds = TimeInterval(max(0, minutes) * 60)
            return now.timeIntervalSince(entry.lastUsedAt) >= idleSeconds
        case .untilPanelClose, .untilAppQuit:
            return false
        }
    }

    private func lockAllLocked() {
        let count = self.entries.count
        for id in self.entries.keys {
            self.zeroize(walletId: id)
        }
        if count > 0 {
            self.logger.notice("session locked - cleared \(count, privacy: .public) wallet(s)")
        }
    }

    private func purgeExpiredLocked() {
        let now = self.nowProvider()
        let expired = self.entries
            .filter { self.isExpired($0.value, at: now) }
            .map(\.key)
        for id in expired {
            self.zeroize(walletId: id)
        }
    }

    private func zeroize(walletId: UUID) {
        guard var entry = entries.removeValue(forKey: walletId) else { return }
        entry.seed.resetBytes(in: 0..<entry.seed.count)
        _ = entry
    }
}

extension WalletSession.Policy: Codable {
    private enum CodingKeys: String, CodingKey {
        case trigger
        case lockOnSystemSleep
        case lockOnScreenLock
        // Pre-rename key. Read-only fallback so any policy persisted under
        // the old name keeps the user's choice on the next launch. New writes
        // use `lockOnScreenLock`.
        case lockOnScreensaver
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let trigger = try container.decode(WalletSessionLockTrigger.self, forKey: .trigger)
        let systemSleep = try container.decode(Bool.self, forKey: .lockOnSystemSleep)
        let screenLock = try container.decodeIfPresent(Bool.self, forKey: .lockOnScreenLock)
            ?? container.decodeIfPresent(Bool.self, forKey: .lockOnScreensaver)
            ?? true
        self.init(
            trigger: trigger,
            lockOnSystemSleep: systemSleep,
            lockOnScreenLock: screenLock)
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(self.trigger, forKey: .trigger)
        try container.encode(self.lockOnSystemSleep, forKey: .lockOnSystemSleep)
        try container.encode(self.lockOnScreenLock, forKey: .lockOnScreenLock)
    }
}
