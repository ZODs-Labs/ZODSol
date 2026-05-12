import AppKit
import SolanaKit
import WalletOverviewDomain
import WalletOverviewUI

/// Tahoe popover dimensions for the wallet menu-bar panel.
///
/// **Width and height are owned by SwiftUI**, not by AppKit. The root
/// `WalletPanelView` declares `.frame(width:height:)`; `VibrantHostingView`'s
/// `sizingOptions = .preferredContentSize` reports that size to AppKit; the
/// panel follows. This is the same pattern `NSPopover` + `NSHostingController`
/// use, so the panel is a consistent size across every route - onboarding,
/// overview, send, receive, manage, settings - matching how Apple's menu-bar
/// utilities (Battery, Control Center) keep a stable shell.
///
/// This file owns only the AppKit-side knobs the panel-window construction
/// still needs (corner radius, gap from the menu bar, screen clamp).
enum WalletPanelMetrics {
    // Mirrors WalletPanelView.panelWidth / panelHeight. Kept as plain
    // constants here because this enum is referenced from a non-isolated
    // context (initial-window construction) and the SwiftUI declaration is
    // @MainActor-isolated. The cross-check lives in WalletPanelMetricsTests.
    static let width: CGFloat = 360
    static let height: CGFloat = 440
    static let cornerRadius: CGFloat = 12
    static let menuBarGap: CGFloat = 6
    static let horizontalEdgeInset: CGFloat = 8
    static let bottomSafetyMargin: CGFloat = 8

    /// Cap the panel against the visible screen height so it never reaches
    /// the Dock on shallow displays. Returns the SwiftUI-declared height
    /// otherwise.
    static func clampedHeight(screen: NSScreen?) -> CGFloat {
        guard let visible = screen?.visibleFrame else { return self.height }
        let maxAvailable = max(120, visible.height - self.menuBarGap - self.bottomSafetyMargin)
        return min(self.height, maxAvailable)
    }
}
