import Foundation
import Observation
import WalletOverviewDomain

/// Drives the "Launch at login" control. Owns the live `LoginItemStatus`,
/// performs the one-time default-on registration, toggles the login item and
/// deep-links to System Settings when the user has to re-approve it.
///
/// The status is always read back from the system after any mutation so the
/// toggle reflects the true registration rather than an assumed value, which is
/// what keeps it in sync when the user flips the item in System Settings.
@MainActor
@Observable
public final class LaunchAtLoginViewModel {
    public private(set) var status: LoginItemStatus
    public private(set) var lastErrorMessage: String?

    private let item: any LoginItemManaging
    private let defaults: UserDefaults
    private let didAutoEnableKey: String

    public static let defaultDidAutoEnableKey = "dev.zods.zodsol.launchAtLogin.didAutoEnable"

    public init(
        item: any LoginItemManaging,
        defaults: UserDefaults = .standard,
        didAutoEnableKey: String = LaunchAtLoginViewModel.defaultDidAutoEnableKey)
    {
        self.item = item
        self.defaults = defaults
        self.didAutoEnableKey = didAutoEnableKey
        self.status = item.currentStatus()
    }

    /// True when the app is registered and will actually launch at login.
    public var isEnabled: Bool {
        self.status.isEnabled
    }

    /// The item is registered but switched off in System Settings; the app can
    /// only launch again once the user re-approves it there.
    public var needsApproval: Bool {
        self.status == .requiresApproval
    }

    /// Re-reads the live system status. Call whenever the settings screen
    /// appears so a change the user made in System Settings is reflected in the
    /// toggle without an app relaunch.
    public func refresh() {
        self.status = self.item.currentStatus()
    }

    /// One-time default-on. Registers the login item on the first ever launch,
    /// then records a flag so this never runs again. A user who later turns the
    /// item off here or in System Settings is therefore never overridden on the
    /// next launch. No-ops if the item is already registered or awaiting the
    /// user's approval, so we never fight an existing choice.
    public func activateDefaultOnFirstRun() {
        guard !self.defaults.bool(forKey: self.didAutoEnableKey) else {
            self.refresh()
            return
        }
        // Burn the one-shot flag before the attempt, unconditionally, so a
        // failed registration is never retried on a later launch.
        self.defaults.set(true, forKey: self.didAutoEnableKey)
        // Register unless the user already has a standing choice: `.enabled`
        // (leave it on) or `.requiresApproval` (they turned it off, do not
        // re-assert). A fresh install reports `.notRegistered` on most systems
        // but can report `.notFound` before it has ever registered, so both
        // must fall through to registration for default-on to hold. The live
        // status cross-check also defends against a spurious UserDefaults read.
        let current = self.item.currentStatus()
        guard current != .enabled, current != .requiresApproval else {
            self.status = current
            return
        }
        do {
            try self.item.enable()
        } catch {
            // Ad-hoc-signed builds can be refused by ServiceManagement; the
            // Developer ID release registers cleanly. Never let a login-item
            // failure block launch. The status read below is the truth.
        }
        self.refresh()
        if !self.status.isEnabled, self.status != .requiresApproval {
            self.lastErrorMessage = Self.failureMessage
        }
    }

    /// Registers or unregisters the login item in response to the user's
    /// toggle. Optimistically reflects intent for an instant, jitter-free
    /// switch, then reconciles with the true system status once the
    /// ServiceManagement call returns.
    public func setEnabled(_ enabled: Bool) async {
        self.lastErrorMessage = nil
        self.status = enabled ? .enabled : .notRegistered
        let item = self.item
        let didThrow: Bool = await Task.detached {
            do {
                if enabled {
                    try item.enable()
                } else {
                    try item.disable()
                }
                return false
            } catch {
                return true
            }
        }.value
        let resolved = item.currentStatus()
        self.status = resolved
        // Trust the live status over the thrown error. Several benign cases
        // (already registered, no job found on a stale unregister) throw yet
        // leave the system in the intended state, so only surface a message
        // when the system did not end up where the user asked.
        if didThrow, !Self.reachedGoal(enabled: enabled, status: resolved) {
            self.lastErrorMessage = Self.failureMessage
        }
    }

    /// Opens System Settings at the Login Items pane so the user can re-approve
    /// a login item they previously turned off.
    public func openLoginItemsSettings() {
        self.item.openSettings()
    }

    private static func reachedGoal(enabled: Bool, status: LoginItemStatus) -> Bool {
        if enabled {
            status == .enabled || status == .requiresApproval
        } else {
            status == .notRegistered || status == .notFound
        }
    }

    private static let failureMessage =
        "Could not update the login item. You can manage it in System Settings > General > Login Items."
}
