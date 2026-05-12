import XCTest
@testable import WalletOverviewDomain

final class WalletOverviewErrorTests: XCTestCase {
    func testNeedsSetupEquatable() {
        XCTAssertEqual(WalletOverviewError.needsSetup, WalletOverviewError.needsSetup)
        XCTAssertNotEqual(WalletOverviewError.needsSetup, WalletOverviewError.unauthorized)
    }

    func testNetworkUnavailableEquatable() {
        XCTAssertEqual(WalletOverviewError.networkUnavailable, WalletOverviewError.networkUnavailable)
    }

    func testRateLimitedEqualWithSameDuration() {
        XCTAssertEqual(
            WalletOverviewError.rateLimited(retryAfter: .seconds(5)),
            WalletOverviewError.rateLimited(retryAfter: .seconds(5)))
    }

    func testRateLimitedNotEqualWithDifferentDuration() {
        XCTAssertNotEqual(
            WalletOverviewError.rateLimited(retryAfter: .seconds(5)),
            WalletOverviewError.rateLimited(retryAfter: .seconds(10)))
    }

    func testRateLimitedNotEqualWhenNilVsValue() {
        XCTAssertNotEqual(
            WalletOverviewError.rateLimited(retryAfter: nil),
            WalletOverviewError.rateLimited(retryAfter: .seconds(5)))
    }

    func testRateLimitedNilEqualsNil() {
        XCTAssertEqual(
            WalletOverviewError.rateLimited(retryAfter: nil),
            WalletOverviewError.rateLimited(retryAfter: nil))
    }

    func testUnauthorizedEquatable() {
        XCTAssertEqual(WalletOverviewError.unauthorized, WalletOverviewError.unauthorized)
    }

    func testProviderUnavailableEquatable() {
        XCTAssertEqual(
            WalletOverviewError.providerUnavailable("helius"),
            WalletOverviewError.providerUnavailable("helius"))
        XCTAssertNotEqual(
            WalletOverviewError.providerUnavailable("helius"),
            WalletOverviewError.providerUnavailable("jupiter"))
    }

    func testMalformedResponseEquatable() {
        XCTAssertEqual(
            WalletOverviewError.malformedResponse("bad"),
            WalletOverviewError.malformedResponse("bad"))
        XCTAssertNotEqual(
            WalletOverviewError.malformedResponse("bad"),
            WalletOverviewError.malformedResponse("worse"))
    }

    func testBiometricInvalidatedEquatable() {
        XCTAssertEqual(WalletOverviewError.biometricInvalidated, WalletOverviewError.biometricInvalidated)
    }

    func testCanceledEquatable() {
        XCTAssertEqual(WalletOverviewError.canceled, WalletOverviewError.canceled)
    }

    func testUnknownEquatable() {
        XCTAssertEqual(
            WalletOverviewError.unknown("oops"),
            WalletOverviewError.unknown("oops"))
        XCTAssertNotEqual(
            WalletOverviewError.unknown("oops"),
            WalletOverviewError.unknown("bang"))
    }

    func testDifferentCasesNotEqual() {
        XCTAssertNotEqual(WalletOverviewError.needsSetup, WalletOverviewError.canceled)
        XCTAssertNotEqual(WalletOverviewError.unauthorized, WalletOverviewError.networkUnavailable)
    }
}
