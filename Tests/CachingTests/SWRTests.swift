import XCTest
@testable import Caching

final class SWRTests: XCTestCase {
    // MARK: - Helpers

    private actor FetchCounter {
        private(set) var count: Int = 0
        func increment() {
            self.count += 1
        }
    }

    private actor CancelFlag {
        private(set) var wasCancelled: Bool = false
        func markCancelled() {
            self.wasCancelled = true
        }
    }

    private func collect<Value>(_ stream: AsyncStream<Value>) async -> [Value] {
        var collected: [Value] = []
        for await v in stream {
            collected.append(v)
        }
        return collected
    }

    // MARK: - Behavior

    func testMissTriggersRevalidation() async {
        let clock = TestClock()
        let cache = TimedCache<String, Int>(ttl: .seconds(10), capacity: 32, clock: clock)
        let counter = FetchCounter()

        let swr = await staleWhileRevalidate(
            cache: cache,
            key: "k",
            forceRevalidate: false,
            fetch: {
                await counter.increment()
                return 99
            })

        XCTAssertEqual(swr.initial, .miss)
        let values = await collect(swr.revalidated)
        XCTAssertEqual(values, [99])
        let fetchCount = await counter.count
        XCTAssertEqual(fetchCount, 1)
    }

    func testFreshSkipsRevalidation() async {
        let clock = TestClock()
        let cache = TimedCache<String, Int>(ttl: .seconds(10), capacity: 32, clock: clock)
        let counter = FetchCounter()
        await cache.write(7, for: "k")

        let swr = await staleWhileRevalidate(
            cache: cache,
            key: "k",
            forceRevalidate: false,
            fetch: {
                await counter.increment()
                return 99
            })

        XCTAssertEqual(swr.initial, .fresh(7))
        let values = await collect(swr.revalidated)
        XCTAssertEqual(values, [])
        let fetchCount = await counter.count
        XCTAssertEqual(fetchCount, 0)
    }

    func testStaleTriggersRevalidation() async {
        let clock = TestClock()
        let cache = TimedCache<String, Int>(ttl: .seconds(10), capacity: 32, clock: clock)
        let counter = FetchCounter()
        await cache.write(7, for: "k")
        // Advance past TTL to make value stale.
        clock.advance(by: .seconds(10) + .nanoseconds(1))

        let swr = await staleWhileRevalidate(
            cache: cache,
            key: "k",
            forceRevalidate: false,
            fetch: {
                await counter.increment()
                return 99
            })

        XCTAssertEqual(swr.initial, .stale(7))
        let values = await collect(swr.revalidated)
        XCTAssertEqual(values, [99])
        let fetchCount = await counter.count
        XCTAssertEqual(fetchCount, 1)
    }

    func testForceRevalidatesWhenFresh() async {
        let clock = TestClock()
        let cache = TimedCache<String, Int>(ttl: .seconds(10), capacity: 32, clock: clock)
        let counter = FetchCounter()
        await cache.write(7, for: "k")

        let swr = await staleWhileRevalidate(
            cache: cache,
            key: "k",
            forceRevalidate: true,
            fetch: {
                await counter.increment()
                return 99
            })

        XCTAssertEqual(swr.initial, .fresh(7))
        let values = await collect(swr.revalidated)
        XCTAssertEqual(values, [99])
        let fetchCount = await counter.count
        XCTAssertEqual(fetchCount, 1)
    }

    func testFetchErrorClosesStream() async {
        struct FetchError: Error {}
        let clock = TestClock()
        let cache = TimedCache<String, Int>(ttl: .seconds(10), capacity: 32, clock: clock)

        let swr = await staleWhileRevalidate(
            cache: cache,
            key: "k",
            forceRevalidate: false,
            fetch: {
                throw FetchError()
            })

        XCTAssertEqual(swr.initial, .miss)
        let values = await collect(swr.revalidated)
        XCTAssertEqual(values, [])
        // Cache must be unchanged (still a miss).
        let after = await cache.read("k")
        XCTAssertEqual(after, .miss)
    }

    func testCancellationStopsFetch() async throws {
        let clock = TestClock()
        let cache = TimedCache<String, Int>(ttl: .seconds(10), capacity: 32, clock: clock)
        let flag = CancelFlag()

        let task = Task {
            let swr = await staleWhileRevalidate(
                cache: cache,
                key: "k",
                forceRevalidate: false,
                fetch: { @Sendable in
                    try await withTaskCancellationHandler {
                        try await Task.sleep(for: .seconds(60))
                        return 99
                    } onCancel: {
                        Task { await flag.markCancelled() }
                    }
                })
            for await _ in swr.revalidated {}
        }

        // Give the fetch a moment to start.
        try await Task.sleep(for: .milliseconds(50))
        task.cancel()
        // Give the cancellation handler a moment to run.
        try await Task.sleep(for: .milliseconds(100))

        let cancelled = await flag.wasCancelled
        XCTAssertTrue(cancelled)
    }
}
