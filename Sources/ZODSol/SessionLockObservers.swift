import AppKit
import WalletOverviewDomain

/// AppKit glue that listens for system-level lock signals and forwards them
/// to the `WalletSession` so the in-memory seed cache is purged.
///
/// Owned by `StatusItemController` for the lifetime of the menu bar
/// installation. Extracted from the controller so that file stays under
/// SwiftLint's length cap.
@MainActor
final class SessionLockObservers {
    private let session: WalletSession
    private var observers: [any NSObjectProtocol] = []

    init(session: WalletSession) {
        self.session = session
    }

    func start() {
        guard self.observers.isEmpty else { return }
        let workspace = NSWorkspace.shared.notificationCenter
        let distributed = DistributedNotificationCenter.default()
        let session = self.session

        // System sleep (lid close, Sleep menu, idle-to-sleep). The whole
        // machine is going down so locking is the obvious posture.
        self.observers.append(workspace.addObserver(
            forName: NSWorkspace.willSleepNotification,
            object: nil,
            queue: .main)
        { _ in
            Task { await session.handleSystemSleep() }
        })
        // Real screen-lock engagement (Lock Screen menu, hot-corner lock,
        // login-window-on-wake). Distributed-only - the workspace center does
        // not forward it.
        //
        // Display sleep (`NSWorkspace.screensDidSleepNotification`) is
        // intentionally NOT observed. Display dimming on idle is a power
        // event, not a security event, and wiring it to `lockAll` forces a
        // re-prompt every couple minutes on battery. Users who want tighter
        // locking can pick `.afterIdle(minutes:)` or `.untilPanelClose`.
        let screensLocked = Notification.Name("com.apple.screenIsLocked")
        self.observers.append(distributed.addObserver(
            forName: screensLocked,
            object: nil,
            queue: .main)
        { _ in
            Task { await session.handleScreenLock() }
        })
    }

    func stop() {
        let workspace = NSWorkspace.shared.notificationCenter
        let distributed = DistributedNotificationCenter.default()
        for observer in self.observers {
            workspace.removeObserver(observer)
            distributed.removeObserver(observer)
        }
        self.observers.removeAll()
    }
}
