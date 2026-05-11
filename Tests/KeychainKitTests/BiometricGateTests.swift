import XCTest
@testable import KeychainKit

final class BiometricGateTests: XCTestCase {
    func testNoneHasNoRequirement() {
        XCTAssertFalse(BiometricGate.none.requiresUserPresence)
        XCTAssertEqual(BiometricGate.none.localizedPrompt, "")
    }

    func testUserPresenceCarriesPrompt() {
        let gate = BiometricGate.userPresence(prompt: "Authenticate")
        XCTAssertTrue(gate.requiresUserPresence)
        XCTAssertEqual(gate.localizedPrompt, "Authenticate")
    }

    func testInitDirectly() {
        let gate = BiometricGate(requiresUserPresence: true, localizedPrompt: "test")
        XCTAssertTrue(gate.requiresUserPresence)
        XCTAssertEqual(gate.localizedPrompt, "test")
    }

    func testSendableConformance() {
        let gate = BiometricGate.none
        let _: any Sendable = gate
    }
}
