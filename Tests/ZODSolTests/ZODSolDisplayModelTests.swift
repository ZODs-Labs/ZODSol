import XCTest
@testable import ZODSol

final class ZODSolDisplayModelTests: XCTestCase {
    func testInitialDisplayModelUsesProductDefaults() {
        let model = ZODSolDisplayModel.initial

        XCTAssertEqual(model.appName, "ZODSol")
        XCTAssertEqual(model.statusItemTitle, "ZODs")
        XCTAssertEqual(model.panelLabel, "ZODs")
    }

    func testInitialPanelSizeIsFixedForFirstShell() {
        let model = ZODSolDisplayModel.initial

        XCTAssertEqual(model.panelWidth, 360)
        XCTAssertEqual(model.panelHeight, 600)
    }
}
