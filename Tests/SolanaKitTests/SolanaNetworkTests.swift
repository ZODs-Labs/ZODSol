import XCTest
@testable import SolanaKit

final class SolanaNetworkTests: XCTestCase {
    func testRawValues() {
        XCTAssertEqual(SolanaNetwork.mainnet.rawValue, "mainnet")
        XCTAssertEqual(SolanaNetwork.devnet.rawValue, "devnet")
        XCTAssertEqual(SolanaNetwork.testnet.rawValue, "testnet")
    }
}
