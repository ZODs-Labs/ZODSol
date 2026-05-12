import AppKit

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItemController: StatusItemController?

    func applicationWillFinishLaunching(_ notification: Notification) {
        #if DEBUG
        DotEnvLoader.applyToProcessEnvironment()
        #endif
        NSApp.setActivationPolicy(.accessory)
        // LSUIElement utility - no document windows, no window tabbing. AppKit
        // otherwise tries to index our NSPanel for system-wide tab grouping
        // and logs "Cannot index window tabs due to missing main bundle
        // identifier" on every panel create.
        NSWindow.allowsAutomaticWindowTabbing = false
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        self.statusItemController = StatusItemController(displayModel: .initial)
    }

    func applicationSupportsSecureRestorableState(_ app: NSApplication) -> Bool {
        true
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }

    func applicationWillTerminate(_ notification: Notification) {
        self.statusItemController?.releaseStatusItem()
        self.statusItemController = nil
    }
}
