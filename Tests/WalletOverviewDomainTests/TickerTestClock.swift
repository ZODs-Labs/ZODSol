import Foundation

struct TickerTestInstant: InstantProtocol {
    typealias Duration = Swift.Duration
    let offset: Duration

    func advanced(by duration: Duration) -> TickerTestInstant {
        TickerTestInstant(offset: self.offset + duration)
    }

    func duration(to other: TickerTestInstant) -> Duration {
        other.offset - self.offset
    }

    static func < (lhs: TickerTestInstant, rhs: TickerTestInstant) -> Bool {
        lhs.offset < rhs.offset
    }
}

/// @unchecked is intentional: NSLock makes this thread-safe and Swift's Clock
/// protocol prevents a clean actor-based Sendable conformance.
final class TickerTestClockStorage: @unchecked Sendable {
    private let lock = NSLock()
    private var current: Duration = .zero

    var now: TickerTestInstant {
        self.lock.lock()
        defer { self.lock.unlock() }
        return TickerTestInstant(offset: self.current)
    }

    func advance(by delta: Duration) {
        self.lock.lock()
        defer { self.lock.unlock() }
        self.current += delta
    }
}

struct TickerTestClock: Clock {
    typealias Duration = Swift.Duration
    typealias Instant = TickerTestInstant

    let storage = TickerTestClockStorage()

    var now: TickerTestInstant {
        self.storage.now
    }

    var minimumResolution: Duration {
        .nanoseconds(1)
    }

    func sleep(until deadline: TickerTestInstant, tolerance: Duration?) async throws {
        throw CancellationError()
    }

    func advance(by delta: Duration) {
        self.storage.advance(by: delta)
    }
}
