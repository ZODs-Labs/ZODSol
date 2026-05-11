import XCTest
@testable import KeychainKit

final class KeychainErrorTests: XCTestCase {
    func testAllCasesConstruct() {
        let cases: [KeychainError] = [
            .unhandledStatus(0),
            .itemNotFound,
            .duplicateItem,
            .interactionRequired,
            .biometricFailed,
            .userCanceled,
            .biometryNotAvailable,
            .biometryLockout,
            .biometryNotEnrolled,
            .dataDecodingFailed,
        ]
        XCTAssertEqual(cases.count, 10)
    }

    func testEquatableOnSimpleCases() {
        XCTAssertEqual(KeychainError.itemNotFound, .itemNotFound)
        XCTAssertNotEqual(KeychainError.itemNotFound, .duplicateItem)
    }

    func testUnhandledStatusEquality() {
        XCTAssertEqual(KeychainError.unhandledStatus(-9999), .unhandledStatus(-9999))
        XCTAssertNotEqual(KeychainError.unhandledStatus(-1), .unhandledStatus(-2))
    }

    func testIsError() {
        let e: any Error = KeychainError.itemNotFound
        XCTAssertNotNil(e)
    }

    func testSendableConformance() {
        let e = KeychainError.biometricFailed
        let _: any Sendable = e
    }
}
