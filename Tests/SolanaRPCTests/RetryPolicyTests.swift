import Foundation
import XCTest
@testable import SolanaRPC

final class RetryPolicyTests: XCTestCase {
    // Default policy used in most assertions
    private let policy = RetryPolicy(
        maxAttempts: 5,
        initialDelay: .seconds(1),
        maxDelay: .seconds(30),
        jitter: 0.25
    )

    private func durationSeconds(_ d: Duration) -> Double {
        let c = d.components
        return Double(c.seconds) + Double(c.attoseconds) / 1e18
    }

    // MARK: - Exponential delay with jitter

    func test_delay_attempt1_inJitterBandAround1s() {
        // Run many trials — each must fall inside ±25% of 1s.
        for _ in 0 ..< 200 {
            let delay = policy.delay(for: 1, retryAfter: nil)
            let seconds = durationSeconds(delay)
            XCTAssertGreaterThanOrEqual(seconds, 0.75, "delay below jitter floor")
            XCTAssertLessThanOrEqual(seconds, 1.25, "delay above jitter ceiling")
        }
    }

    func test_delay_attempt2_inJitterBandAround2s() {
        for _ in 0 ..< 200 {
            let delay = policy.delay(for: 2, retryAfter: nil)
            let seconds = durationSeconds(delay)
            XCTAssertGreaterThanOrEqual(seconds, 1.5)
            XCTAssertLessThanOrEqual(seconds, 2.5)
        }
    }

    func test_delay_attempt3_inJitterBandAround4s() {
        for _ in 0 ..< 200 {
            let delay = policy.delay(for: 3, retryAfter: nil)
            let seconds = durationSeconds(delay)
            XCTAssertGreaterThanOrEqual(seconds, 3.0)
            XCTAssertLessThanOrEqual(seconds, 5.0)
        }
    }

    // MARK: - retryAfter honoring

    func test_retryAfter_nonNil_returnsRetryAfter() {
        let delay = policy.delay(for: 1, retryAfter: .seconds(7))
        XCTAssertEqual(durationSeconds(delay), 7.0, accuracy: 0.0001)
    }

    func test_retryAfter_largerThanMaxDelay_isCapped() {
        let delay = policy.delay(for: 1, retryAfter: .seconds(120))
        XCTAssertEqual(durationSeconds(delay), 30.0, accuracy: 0.0001)
    }

    func test_retryAfter_atExactMaxDelay_isReturnedUnchanged() {
        let delay = policy.delay(for: 1, retryAfter: .seconds(30))
        XCTAssertEqual(durationSeconds(delay), 30.0, accuracy: 0.0001)
    }

    // MARK: - max-delay cap on exponential growth

    func test_largeAttempt_isCappedAtMaxDelay_evenWithJitter() {
        // attempt 20 — nominal would be 2^19 seconds. Must cap before jitter is applied.
        // After ±25% jitter on a maxDelay of 30s, never exceed 30 * 1.25 = 37.5s.
        for _ in 0 ..< 200 {
            let delay = policy.delay(for: 20, retryAfter: nil)
            let seconds = durationSeconds(delay)
            XCTAssertLessThanOrEqual(seconds, 30.0 * 1.25 + 0.001)
            XCTAssertGreaterThanOrEqual(seconds, 30.0 * 0.75 - 0.001)
        }
    }

    // MARK: - Defaults

    func test_defaultPolicy_hasSpecValues() {
        let d = RetryPolicy.default
        XCTAssertEqual(d.maxAttempts, 3)
        XCTAssertEqual(durationSeconds(d.initialDelay), 1.0, accuracy: 0.0001)
        XCTAssertEqual(durationSeconds(d.maxDelay), 30.0, accuracy: 0.0001)
        XCTAssertEqual(d.jitter, 0.25, accuracy: 0.0001)
    }
}
