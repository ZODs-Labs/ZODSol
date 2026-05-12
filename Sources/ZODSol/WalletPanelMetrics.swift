import AppKit
import SolanaKit
import WalletOverviewDomain
import WalletOverviewUI

/// Tahoe popover dimensions for the wallet menu-bar panel.
///
/// Width, radius and menu-bar gap are constants. Height is **route-driven**
/// (Battery, Wi-Fi and Control Center all size to content, not to a fixed
/// shell) and clamped to the visible screen so the panel never reaches the
/// Dock or pushes the cursor off the display.
enum WalletPanelMetrics {
    static let width: CGFloat = 360
    static let cornerRadius: CGFloat = 12
    static let menuBarGap: CGFloat = 6
    static let horizontalEdgeInset: CGFloat = 8
    static let bottomSafetyMargin: CGFloat = 8
    static let minHeight: CGFloat = 220

    static func idealHeight(
        route: PanelRoute,
        hasAPIKey: Bool,
        walletCount: Int,
        state: LoadState<WalletOverview>) -> CGFloat
    {
        if !hasAPIKey { return 240 }
        if walletCount == 0 { return 340 }
        return self.heightForRoute(route, walletCount: walletCount, state: state)
    }

    private static func heightForRoute(
        _ route: PanelRoute,
        walletCount: Int,
        state: LoadState<WalletOverview>) -> CGFloat
    {
        switch route {
        case .overview:
            self.overviewHeight(state: state)
        case .switcher:
            self.clamp(96 + CGFloat(max(1, walletCount)) * 56 + 48, lo: 280, hi: 480)
        case .manage:
            self.clamp(96 + CGFloat(max(1, walletCount)) * 56 + 56, lo: 280, hi: 520)
        case .rename:
            220
        case .addWallet:
            300
        case .send:
            440
        case .assetPicker:
            480
        case .receive:
            520
        }
    }

    private static func overviewHeight(state: LoadState<WalletOverview>) -> CGFloat {
        switch state {
        case .idle, .loading: 360
        case .failed: 320
        case .loaded, .partial: 520
        }
    }

    static func clampedHeight(ideal: CGFloat, screen: NSScreen?) -> CGFloat {
        let floored = max(ideal, minHeight)
        guard let visible = screen?.visibleFrame else { return floored }
        let maxAvailable = max(minHeight, visible.height - self.menuBarGap - self.bottomSafetyMargin)
        return min(floored, maxAvailable)
    }

    private static func clamp(_ value: CGFloat, lo: CGFloat, hi: CGFloat) -> CGFloat {
        max(lo, min(value, hi))
    }
}
