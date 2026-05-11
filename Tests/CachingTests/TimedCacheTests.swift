import XCTest
@testable import Caching

final class TimedCacheTests: XCTestCase {

    // MARK: - Freshness

    func testFreshRead() async {
        let clock = TestClock()
        let cache = TimedCache<String, Int>(ttl: .seconds(10), capacity: 32, clock: clock)
        await cache.write(42, for: "key")
        let result = await cache.read("key")
        XCTAssertEqual(result, .fresh(42))
    }

    func testAtBoundaryIsFresh() async {
        let clock = TestClock()
        let cache = TimedCache<String, Int>(ttl: .seconds(10), capacity: 32, clock: clock)
        await cache.write(42, for: "key")
        clock.advance(by: .seconds(9) + .nanoseconds(999_999_999))
        let result = await cache.read("key")
        XCTAssertEqual(result, .fresh(42))
    }

    func testJustPastBoundaryIsStale() async {
        let clock = TestClock()
        let cache = TimedCache<String, Int>(ttl: .seconds(10), capacity: 32, clock: clock)
        await cache.write(42, for: "key")
        clock.advance(by: .seconds(10) + .nanoseconds(1))
        let result = await cache.read("key")
        XCTAssertEqual(result, .stale(42))
    }

    func testMiss() async {
        let clock = TestClock()
        let cache = TimedCache<String, Int>(ttl: .seconds(10), capacity: 32, clock: clock)
        let result = await cache.read("missing")
        XCTAssertEqual(result, .miss)
    }

    // MARK: - LRU eviction

    func testLRUEviction() async {
        let clock = TestClock()
        let cache = TimedCache<String, Int>(ttl: .seconds(60), capacity: 3, clock: clock)

        // t=0: write k1
        await cache.write(1, for: "k1")

        clock.advance(by: .milliseconds(1))
        // t=1ms: write k2
        await cache.write(2, for: "k2")

        clock.advance(by: .milliseconds(1))
        // t=2ms: write k3
        await cache.write(3, for: "k3")

        clock.advance(by: .milliseconds(1))
        // t=3ms: read k1 -> bumps lastAccessedAt of k1 to 3ms
        let readK1 = await cache.read("k1")
        XCTAssertEqual(readK1, .fresh(1))

        clock.advance(by: .milliseconds(1))
        // t=4ms: write k4 -> count goes to 4 -> evict LRU which is now k2 (lastAccessedAt=1ms)
        await cache.write(4, for: "k4")

        let r2 = await cache.read("k2")
        let r1 = await cache.read("k1")
        let r3 = await cache.read("k3")
        let r4 = await cache.read("k4")

        XCTAssertEqual(r2, .miss)
        XCTAssertEqual(r1, .fresh(1))
        XCTAssertEqual(r3, .fresh(3))
        XCTAssertEqual(r4, .fresh(4))
    }

    // MARK: - Invalidation

    func testInvalidate() async {
        let clock = TestClock()
        let cache = TimedCache<String, Int>(ttl: .seconds(10), capacity: 32, clock: clock)
        await cache.write(42, for: "key")
        await cache.invalidate("key")
        let result = await cache.read("key")
        XCTAssertEqual(result, .miss)
    }

    func testInvalidateAll() async {
        let clock = TestClock()
        let cache = TimedCache<String, Int>(ttl: .seconds(10), capacity: 32, clock: clock)
        await cache.write(1, for: "a")
        await cache.write(2, for: "b")
        await cache.invalidateAll()
        let ra = await cache.read("a")
        let rb = await cache.read("b")
        XCTAssertEqual(ra, .miss)
        XCTAssertEqual(rb, .miss)
    }
}
