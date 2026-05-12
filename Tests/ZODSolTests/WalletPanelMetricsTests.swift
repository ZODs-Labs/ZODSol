import SolanaKit
import WalletOverviewDomain
import WalletOverviewUI
import XCTest
@testable import ZODSol

final class WalletPanelMetricsTests: XCTestCase {
    func testTahoeConstants() {
        XCTAssertEqual(WalletPanelMetrics.width, 360)
        XCTAssertEqual(WalletPanelMetrics.cornerRadius, 12)
        XCTAssertEqual(WalletPanelMetrics.menuBarGap, 6)
    }

    func testOnboardingHeightsBeforeAPIKey() {
        let h = WalletPanelMetrics.idealHeight(
            route: .overview,
            hasAPIKey: false,
            walletCount: 0,
            state: .idle)
        XCTAssertEqual(h, 240)
    }

    func testOnboardingHeightsBeforeFirstWallet() {
        let h = WalletPanelMetrics.idealHeight(
            route: .overview,
            hasAPIKey: true,
            walletCount: 0,
            state: .idle)
        XCTAssertEqual(h, 340)
    }

    func testOverviewHeightsByState() throws {
        let common: (LoadState<WalletOverview>) -> CGFloat = { state in
            WalletPanelMetrics.idealHeight(
                route: .overview, hasAPIKey: true, walletCount: 1, state: state)
        }
        let overview = try WalletOverview(
            walletId: UUID(),
            address: WalletAddress(base58: "So11111111111111111111111111111111111111112"),
            solBalance: Lamports(rawValue: 0),
            solPriceUSD: nil,
            solChange24h: nil,
            tokens: [],
            nfts: NFTSummary(count: 0, collectionPreviews: []),
            totalUSD: nil,
            totalChange24h: nil,
            asOf: Date(timeIntervalSince1970: 0),
            isPartial: false)
        XCTAssertEqual(common(.idle), 360)
        XCTAssertEqual(common(.loading), 360)
        XCTAssertEqual(common(.failed(.needsSetup)), 320)
        XCTAssertEqual(common(.loaded(overview, lastRefreshed: Date(timeIntervalSince1970: 0))), 520)
        XCTAssertEqual(common(.partial(overview, error: .needsSetup)), 520)
    }

    func testRenameAndAddWalletAreShort() {
        let renameH = WalletPanelMetrics.idealHeight(
            route: .rename(walletId: UUID()), hasAPIKey: true, walletCount: 2, state: .loading)
        let addH = WalletPanelMetrics.idealHeight(
            route: .addWallet, hasAPIKey: true, walletCount: 2, state: .loading)
        XCTAssertEqual(renameH, 220)
        XCTAssertEqual(addH, 300)
    }

    func testSwitcherClampsToList() {
        let single = WalletPanelMetrics.idealHeight(
            route: .switcher, hasAPIKey: true, walletCount: 1, state: .loading)
        let many = WalletPanelMetrics.idealHeight(
            route: .switcher, hasAPIKey: true, walletCount: 20, state: .loading)
        XCTAssertEqual(single, 280, "single-row switcher snaps to the floor")
        XCTAssertEqual(many, 480, "long switcher caps at the popover ceiling")
    }

    func testManageClampsToList() {
        let single = WalletPanelMetrics.idealHeight(
            route: .manage, hasAPIKey: true, walletCount: 1, state: .loading)
        let many = WalletPanelMetrics.idealHeight(
            route: .manage, hasAPIKey: true, walletCount: 20, state: .loading)
        XCTAssertEqual(single, 280)
        XCTAssertEqual(many, 520)
    }

    func testClampedHeightRespectsScreen() {
        let unbounded = WalletPanelMetrics.clampedHeight(ideal: 2000, screen: nil)
        XCTAssertEqual(unbounded, 2000, "no screen means no cap, ideal exceeds floor")

        let belowFloor = WalletPanelMetrics.clampedHeight(ideal: 100, screen: nil)
        XCTAssertEqual(belowFloor, WalletPanelMetrics.minHeight, "ideal under floor snaps to floor")
    }
}
