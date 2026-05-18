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

    @MainActor
    func testWidthAndHeightMirrorSwiftUIDeclaration() {
        let panelWidth = WalletPanelView.panelWidth
        let panelHeight = WalletPanelView.panelHeight

        XCTAssertEqual(WalletPanelMetrics.width, panelWidth)
        XCTAssertEqual(WalletPanelMetrics.height, panelHeight)
    }

    func testClampedHeightFallsBackToCanonicalWithoutScreen() {
        let h = WalletPanelMetrics.clampedHeight(screen: nil)
        XCTAssertEqual(h, WalletPanelMetrics.height)
    }
}
