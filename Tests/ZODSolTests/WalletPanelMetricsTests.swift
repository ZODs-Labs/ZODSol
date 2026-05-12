import AppKit
import WalletOverviewUI
import XCTest
@testable import ZODSol

final class WalletPanelMetricsTests: XCTestCase {
    func testTahoeConstants() {
        XCTAssertEqual(WalletPanelMetrics.width, 360)
        XCTAssertEqual(WalletPanelMetrics.cornerRadius, 12)
        XCTAssertEqual(WalletPanelMetrics.menuBarGap, 6)
    }

    func testWidthAndHeightMirrorSwiftUIDeclaration() {
        // SwiftUI's WalletPanelView is the single source of truth for panel
        // dimensions - AppKit mirrors that declaration.
        XCTAssertEqual(WalletPanelMetrics.width, WalletPanelView.panelWidth)
        XCTAssertEqual(WalletPanelMetrics.height, WalletPanelView.panelHeight)
    }

    func testClampedHeightFallsBackToCanonicalWithoutScreen() {
        let h = WalletPanelMetrics.clampedHeight(screen: nil)
        XCTAssertEqual(h, WalletPanelMetrics.height)
    }
}
