import Foundation
import XCTest
@testable import Caching

struct TestInstant: InstantProtocol {
    typealias Duration = Swift.Duration
    let d: Duration

    func advanced(by duration: Duration) -> TestInstant {
        TestInstant(d: self.d + duration)
    }

    func duration(to other: TestInstant) -> Duration {
        other.d - self.d
    }

    static func < (lhs: TestInstant, rhs: TestInstant) -> Bool {
        lhs.d < rhs.d
    }

    static func == (lhs: TestInstant, rhs: TestInstant) -> Bool {
        lhs.d == rhs.d
    }
}

/// @unchecked is intentional: NSLock makes this thread-safe and Swift's Clock protocol prevents a clean actor-based Sendable conformance.
final class TestClockStorage: @unchecked Sendable {
    private let lock = NSLock()
    private var current: Duration = .zero

    var now: TestInstant {
        self.lock.lock()
        defer { lock.unlock() }
        return TestInstant(d: self.current)
    }

    func advance(by delta: Duration) {
        self.lock.lock()
        defer { lock.unlock() }
        self.current += delta
    }
}

struct TestClock: Clock {
    typealias Duration = Swift.Duration
    typealias Instant = TestInstant

    let storage: TestClockStorage

    init() {
        self.storage = TestClockStorage()
    }

    var now: TestInstant {
        self.storage.now
    }

    var minimumResolution: Duration {
        .nanoseconds(1)
    }

    func sleep(until deadline: TestInstant, tolerance: Duration?) async throws {
        throw CancellationError()
    }

    func advance(by delta: Duration) {
        self.storage.advance(by: delta)
    }
}
