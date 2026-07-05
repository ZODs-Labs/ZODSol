import ServiceManagement
import WalletOverviewDomain

/// `LoginItemManaging` backed by `SMAppService.mainApp` (macOS 13+). Holds no
/// state: `SMAppService.mainApp` is resolved fresh on every call, so the type
/// is trivially `Sendable` and always reflects the live system registration
/// rather than a cached snapshot.
///
/// `SMAppService.mainApp` registers the app itself as the login item, which is
/// the correct choice for an `LSUIElement` menu-bar app. It supersedes the
/// deprecated `SMLoginItemSetEnabled` plus embedded-helper approach and keeps
/// the toggle in lockstep with System Settings > General > Login Items.
struct SMAppServiceLoginItem: LoginItemManaging {
    func currentStatus() -> LoginItemStatus {
        LoginItemStatus(SMAppService.mainApp.status)
    }

    func enable() throws {
        try SMAppService.mainApp.register()
    }

    func disable() throws {
        try SMAppService.mainApp.unregister()
    }

    func openSettings() {
        // The framework method is preferred over an `x-apple.systempreferences:`
        // URL because it survives the pane being renamed to "Login Items &
        // Extensions" on macOS 15+ and never depends on an undocumented anchor.
        SMAppService.openSystemSettingsLoginItems()
    }
}

extension LoginItemStatus {
    init(_ status: SMAppService.Status) {
        switch status {
        case .enabled: self = .enabled
        case .notRegistered: self = .notRegistered
        case .requiresApproval: self = .requiresApproval
        case .notFound: self = .notFound
        @unknown default: self = .unknown
        }
    }
}
