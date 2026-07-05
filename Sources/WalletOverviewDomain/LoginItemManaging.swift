import Foundation

/// The system-level registration state of the app's login item. Mirrors
/// `SMAppService.Status` without leaking the ServiceManagement type across the
/// seam, so the UI layer and its tests stay independent of that framework and
/// can run without a signed `.app` bundle.
public enum LoginItemStatus: Sendable, Equatable {
    /// Registered and will launch at login.
    case enabled
    /// Not registered. Will not launch at login.
    case notRegistered
    /// Registered but the user must approve it in System Settings > General >
    /// Login Items before it launches. Reached when the user turns the item
    /// off there, or when macOS defers a fresh registration for approval.
    case requiresApproval
    /// The system could not resolve the app bundle to register. Seen when
    /// running from a translocated or quarantined path, or from a non-bundle
    /// host such as the test runner.
    case notFound
    /// A future `SMAppService.Status` case not yet modelled here.
    case unknown

    /// Whether the app is registered and will actually launch at login.
    public var isEnabled: Bool {
        self == .enabled
    }
}

/// Abstraction over the app's launch-at-login registration. Keeps the toggle
/// and first-run logic unit-testable without touching the real
/// ServiceManagement daemon, which needs a signed `.app` bundle and mutates
/// real system state. The executable injects `SMAppServiceLoginItem`; tests
/// inject a stub.
public protocol LoginItemManaging: Sendable {
    /// The live registration status. Cheap to call on any thread.
    func currentStatus() -> LoginItemStatus
    /// Registers the main app as a login item. Synchronous. Throws when the
    /// system refuses, for example an unsigned build or an operation the user
    /// is not permitted to perform.
    func enable() throws
    /// Unregisters the login item. Safe to call when already unregistered.
    func disable() throws
    /// Opens System Settings at the Login Items pane so the user can re-approve
    /// an item they previously turned off.
    func openSettings()
}
