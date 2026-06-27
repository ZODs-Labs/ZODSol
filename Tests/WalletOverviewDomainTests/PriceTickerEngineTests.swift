import Foundation
import SolanaKit
import XCTest
@testable import WalletOverviewDomain

private final class MockTickerQuoteProvider: TickerQuoteProviding, @unchecked Sendable {
    private let lock = NSLock()
    private var outcome: TickerFetchOutcome
    private var calls = 0

    init(_ outcome: TickerFetchOutcome) {
        self.outcome = outcome
    }

    var callCount: Int {
        self.lock.lock()
        defer { self.lock.unlock() }
        return self.calls
    }

    func set(_ outcome: TickerFetchOutcome) {
        self.lock.lock()
        defer { self.lock.unlock() }
        self.outcome = outcome
    }

    func quotes(for requests: [TickerQuoteRequest]) async -> TickerFetchOutcome {
        self.lock.withLock {
            self.calls += 1
            return self.outcome
        }
    }
}

private let btcPair = "XXBTZUSD"

private func btcEntry() -> TickerEntry {
    TickerCatalog.blueChipEntry(symbol: "BTC")!
}

private func success(_ price: String, change: Double = 1.0, id: String = btcPair) -> TickerFetchOutcome {
    TickerFetchOutcome(
        quotes: [id: PriceQuote(usdPrice: Decimal(string: price), change24h: change)],
        retryAfter: nil,
        shouldBackOff: false)
}

private let failure = TickerFetchOutcome(quotes: [:], retryAfter: nil, shouldBackOff: true)

private func makeEngine(
    _ provider: any TickerQuoteProviding,
    clock: any Clock<Duration> = ContinuousClock(),
    configuration: PriceTickerEngine.Configuration = .init(),
    store: LastKnownPricesStore? = nil) -> PriceTickerEngine
{
    PriceTickerEngine(provider: provider, lastKnownStore: store, configuration: configuration, clock: clock)
}

// Synchronous so the non-Sendable UserDefaults never crosses an async boundary.
private func makePricesStore(_ suiteName: String) -> LastKnownPricesStore {
    let defaults = UserDefaults(suiteName: suiteName)!
    defaults.removePersistentDomain(forName: suiteName)
    return LastKnownPricesStore(defaults: defaults, key: "test.lastKnownPrices")
}

final class PriceTickerEngineTests: XCTestCase {
    // MARK: - Staleness

    func test_tickOnce_success_yieldsFreshSegment() async {
        let engine = makeEngine(MockTickerQuoteProvider(success("64000", change: 2.5)))
        await engine.configure(entries: [btcEntry()])
        let snapshot = await engine.tickOnce()

        let segment = snapshot.segments.first
        XCTAssertEqual(segment?.staleness, .fresh)
        XCTAssertEqual(segment?.price, Decimal(string: "64000"))
        XCTAssertEqual(segment?.change24h, 2.5)
    }

    func test_tickOnce_failuresBelowThreshold_keepFreshAndLastPrice() async {
        let mock = MockTickerQuoteProvider(success("64000"))
        let engine = makeEngine(mock)
        await engine.configure(entries: [btcEntry()])
        _ = await engine.tickOnce()
        mock.set(failure)
        _ = await engine.tickOnce()
        let snapshot = await engine.tickOnce()

        let segment = snapshot.segments.first
        XCTAssertEqual(segment?.staleness, .fresh)
        XCTAssertEqual(segment?.price, Decimal(string: "64000"))
    }

    func test_tickOnce_thresholdFailures_markStaleButKeepPrice() async {
        let mock = MockTickerQuoteProvider(success("64000"))
        let engine = makeEngine(mock)
        await engine.configure(entries: [btcEntry()])
        _ = await engine.tickOnce()
        mock.set(failure)
        for _ in 0..<3 { _ = await engine.tickOnce() }
        let snapshot = await engine.tickOnce()

        let segment = snapshot.segments.first
        XCTAssertEqual(segment?.staleness, .stale)
        XCTAssertEqual(segment?.price, Decimal(string: "64000"))
    }

    func test_tickOnce_coldFailure_isUnavailable() async {
        let engine = makeEngine(MockTickerQuoteProvider(failure))
        await engine.configure(entries: [btcEntry()])
        let snapshot = await engine.tickOnce()

        let segment = snapshot.segments.first
        XCTAssertEqual(segment?.staleness, .unavailable)
        XCTAssertNil(segment?.price)
    }

    func test_staleValueExpiresToUnavailableAfterExpiry() async {
        let clock = TickerTestClock()
        let mock = MockTickerQuoteProvider(success("64000"))
        let engine = makeEngine(mock, clock: clock)
        await engine.configure(entries: [btcEntry()])
        _ = await engine.tickOnce()

        clock.advance(by: .seconds(700))
        mock.set(failure)
        for _ in 0..<3 { _ = await engine.tickOnce() }
        let snapshot = await engine.tickOnce()

        let segment = snapshot.segments.first
        XCTAssertEqual(segment?.staleness, .unavailable)
        XCTAssertNil(segment?.price)
    }

    // MARK: - Cadence

    func test_currentInterval_panelOpenIs10s() async {
        let engine = makeEngine(MockTickerQuoteProvider(success("1")))
        await engine.setPanelOpen(true)
        let interval = await engine.currentInterval()
        XCTAssertEqual(interval, .seconds(10))
    }

    func test_currentInterval_ambientIs30s() async {
        let engine = makeEngine(MockTickerQuoteProvider(success("1")))
        let interval = await engine.currentInterval()
        XCTAssertEqual(interval, .seconds(30))
    }

    func test_currentInterval_lowPowerOverridesPanelOpen() async {
        let engine = makeEngine(MockTickerQuoteProvider(success("1")))
        await engine.setPanelOpen(true)
        await engine.setLowPower(true)
        let interval = await engine.currentInterval()
        XCTAssertEqual(interval, .seconds(60))
    }

    func test_currentInterval_backsOffExponentiallyThenResetsOnSuccess() async {
        let mock = MockTickerQuoteProvider(failure)
        let engine = makeEngine(mock)
        await engine.configure(entries: [btcEntry()])

        _ = await engine.tickOnce()
        let afterOne = await engine.currentInterval()
        XCTAssertEqual(afterOne, .seconds(60)) // 30s ambient * 2

        _ = await engine.tickOnce()
        let afterTwo = await engine.currentInterval()
        XCTAssertEqual(afterTwo, .seconds(120)) // 30s * 4, capped at maxBackoff

        mock.set(success("1"))
        _ = await engine.tickOnce()
        let afterSuccess = await engine.currentInterval()
        XCTAssertEqual(afterSuccess, .seconds(30))
    }

    func test_currentInterval_honorsRetryAfterWhenLargerThanBase() async {
        let mock = MockTickerQuoteProvider(
            TickerFetchOutcome(quotes: [:], retryAfter: .seconds(45), shouldBackOff: true))
        let engine = makeEngine(mock)
        await engine.configure(entries: [btcEntry()])
        _ = await engine.tickOnce()

        let interval = await engine.currentInterval()
        XCTAssertEqual(interval, .seconds(45))
    }

    // MARK: - Gating

    func test_isPollable_requiresAllGates() async {
        let engine = makeEngine(MockTickerQuoteProvider(success("1")))
        var pollable = await engine.runtime.isPollable
        XCTAssertFalse(pollable) // widget disabled by default

        await engine.setWidgetEnabled(true)
        pollable = await engine.runtime.isPollable
        XCTAssertTrue(pollable)

        await engine.setOnline(false)
        pollable = await engine.runtime.isPollable
        XCTAssertFalse(pollable)

        await engine.setOnline(true)
        await engine.setScreenAwake(false)
        pollable = await engine.runtime.isPollable
        XCTAssertFalse(pollable)

        await engine.setScreenAwake(true)
        await engine.setSessionLocked(true)
        pollable = await engine.runtime.isPollable
        XCTAssertFalse(pollable)
    }

    // MARK: - Configure

    func test_configure_dropsCacheForRemovedEntries() async {
        let engine = makeEngine(MockTickerQuoteProvider(success("64000")))
        await engine.configure(entries: [btcEntry()])
        _ = await engine.tickOnce()

        await engine.configure(entries: [])
        let empty = await engine.buildSnapshot()
        XCTAssertTrue(empty.segments.isEmpty)

        await engine.configure(entries: [btcEntry()])
        let reAdded = await engine.buildSnapshot()
        XCTAssertEqual(reAdded.segments.first?.staleness, .unavailable)
    }

    // MARK: - Cold start

    func test_seedFromStore_rendersSeededPriceAsStale() async {
        let suiteName = "PriceTickerEngineTests-\(UUID().uuidString)"
        let store = makePricesStore(suiteName)
        defer { UserDefaults(suiteName: suiteName)?.removePersistentDomain(forName: suiteName) }

        await store.save([btcPair: LastKnownPrice(
            quote: PriceQuote(usdPrice: Decimal(string: "60000"), change24h: -1.0),
            capturedAt: Date())])

        let engine = makeEngine(MockTickerQuoteProvider(success("64000")), store: store)
        await engine.seedFromStore()
        await engine.configure(entries: [btcEntry()])
        let snapshot = await engine.buildSnapshot()

        let segment = snapshot.segments.first
        XCTAssertEqual(segment?.staleness, .stale)
        XCTAssertEqual(segment?.price, Decimal(string: "60000"))
    }
}
