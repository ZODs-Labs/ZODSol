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

        self.observers.append(workspace.addObserver(
            forName: NSWorkspace.willSleepNotification,
            object: nil,
            queue: .main)
        { _ in
            Task { await session.handleSystemSleep() }
        })
        self.observers.append(workspace.addObserver(
            forName: NSWorkspace.screensDidSleepNotification,
            object: nil,
            queue: .main)
        { _ in
            Task { await session.handleScreensaver() }
        })
        // Lock-screen engagement is delivered via a distributed notification;
        // the workspace center does not forward it.
        let screensLocked = Notification.Name("com.apple.screenIsLocked")
        self.observers.append(distributed.addObserver(
            forName: screensLocked,
            object: nil,
            queue: .main)
        { _ in
            Task { await session.handleScreensaver() }
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
