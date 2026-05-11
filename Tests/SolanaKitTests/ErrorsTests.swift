import XCTest
@testable import SolanaKit

final class ErrorsTests: XCTestCase {
    func testNetworkUnavailable() {
        let error = SolanaProviderError.networkUnavailable
        XCTAssertEqual(error, SolanaProviderError.networkUnavailable)
    }

    func testRateLimitedWithRetryAfter() {
        let error = SolanaProviderError.rateLimited(retryAfter: .seconds(30))
        XCTAssertEqual(error, SolanaProviderError.rateLimited(retryAfter: .seconds(30)))
    }

    func testRateLimitedWithNilRetryAfter() {
        let error = SolanaProviderError.rateLimited(retryAfter: nil)
        XCTAssertEqual(error, SolanaProviderError.rateLimited(retryAfter: nil))
    }

    func testRateLimitedDifferentValues() {
        let a = SolanaProviderError.rateLimited(retryAfter: .seconds(10))
        let b = SolanaProviderError.rateLimited(retryAfter: .seconds(20))
        XCTAssertNotEqual(a, b)
    }

    func testUnauthorized() {
        let error = SolanaProviderError.unauthorized
        XCTAssertEqual(error, SolanaProviderError.unauthorized)
    }

    func testProviderUnavailable() {
        let error = SolanaProviderError.providerUnavailable(message: "down for maintenance")
        XCTAssertEqual(error, SolanaProviderError.providerUnavailable(message: "down for maintenance"))
    }

    func testMalformedResponse() {
        let error = SolanaProviderError.malformedResponse("unexpected JSON structure")
        XCTAssertEqual(error, SolanaProviderError.malformedResponse("unexpected JSON structure"))
    }

    func testInvalidInput() {
        let error = SolanaProviderError.invalidInput("bad address")
        XCTAssertEqual(error, SolanaProviderError.invalidInput("bad address"))
    }

    func testCanceled() {
        let error = SolanaProviderError.canceled
        XCTAssertEqual(error, SolanaProviderError.canceled)
    }

    func testDifferentCasesNotEqual() {
        XCTAssertNotEqual(SolanaProviderError.networkUnavailable, SolanaProviderError.unauthorized)
        XCTAssertNotEqual(SolanaProviderError.canceled, SolanaProviderError.networkUnavailable)
    }

    func testIsError() {
        let error: any Error = SolanaProviderError.networkUnavailable
        XCTAssertTrue(error is SolanaProviderError)
    }

    func testSendableConformance() {
        let error = SolanaProviderError.networkUnavailable
        let fn: @Sendable () -> SolanaProviderError = { error }
        XCTAssertEqual(fn(), error)
    }
}
