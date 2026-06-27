import Foundation
import SolanaKit

/// The menu-bar ticker's polling brain. An actor that, while pollable, fetches
/// quotes for the selected tokens on an adaptive cadence, keeps the last good
/// value through transient failures (stale-while-revalidate), backs its cadence
/// off on rate limiting, and emits an immutable `TickerSnapshot` the presenter
/// renders. Gating (widget enabled, online, screen awake, session unlocked) and
/// power state are pushed in from the executable's OS observers.
///
/// All wall-clock timing goes through the injected `Clock` so the cadence and
/// staleness aging are testable; the run loop's sleep is the only untested part.
public actor PriceTickerEngine {
    public struct Configuration: Sendable {
        public var panelOpenInterval: Duration = .seconds(10)
        public var ambientInterval: Duration = .seconds(30)
        public var lowPowerInterval: Duration = .seconds(60)
        public var maxBackoffInterval: Duration = .seconds(120)
        public var idleInterval: Duration = .seconds(60)
        public var staleThreshold: Int = 3
        public var expiry: Duration = .seconds(600)

        public init() {}
    }

    struct RuntimeState: Equatable {
        var isWidgetEnabled = false
        var isOnline = true
        var isScreenAwake = true
        var isSessionUnlocked = true
        var isPanelOpen = false
        var isLowPower = false

        var isPollable: Bool {
            self.isWidgetEnabled && self.isOnline && self.isScreenAwake && self.isSessionUnlocked
        }
    }

    private let provider: any TickerQuoteProviding
    private let lastKnownStore: LastKnownPricesStore?
    private let configuration: Configuration
    private let nowProvider: @Sendable () -> Duration
    private let sleepProvider: @Sendable (Duration) async -> Void

    private var entries: [TickerEntry] = []
    private var lastQuotes: [String: PriceQuote] = [:]
    private var lastFreshAt: [String: Duration] = [:]
    private var staleCounts: [String: Int] = [:]
    private var consecutiveBackoffs = 0
    private var pendingRetryAfter: Duration?
    var runtime = RuntimeState()

    private var loopTask: Task<Void, Never>?
    private var sleeper: Task<Void, Never>?
    private var continuations: [UUID: AsyncStream<TickerSnapshot>.Continuation] = [:]

    public init(
        provider: any TickerQuoteProviding,
        lastKnownStore: LastKnownPricesStore? = nil,
        configuration: Configuration = Configuration(),
        clock: any Clock<Duration> = ContinuousClock())
    {
        self.provider = provider
        self.lastKnownStore = lastKnownStore
        self.configuration = configuration
        self.nowProvider = Self.makeNowProvider(clock)
        self.sleepProvider = Self.makeSleepProvider(clock)
    }

    // MARK: - Subscription

    public func snapshots() -> AsyncStream<TickerSnapshot> {
        let id = UUID()
        let (stream, continuation) = AsyncStream<TickerSnapshot>.makeStream()
        self.continuations[id] = continuation
        continuation.onTermination = { [weak self] _ in
            Task { await self?.removeContinuation(id) }
        }
        return stream
    }

    private func removeContinuation(_ id: UUID) {
        self.continuations[id] = nil
    }

    // MARK: - Configuration and gating

    public func configure(entries: [TickerEntry]) {
        self.entries = entries.filter(\.isEnabled)
        let active = Set(self.entries.map(\.sourceIdentifier))
        self.lastQuotes = self.lastQuotes.filter { active.contains($0.key) }
        self.lastFreshAt = self.lastFreshAt.filter { active.contains($0.key) }
        self.staleCounts = self.staleCounts.filter { active.contains($0.key) }
        self.wake()
    }

    public func setWidgetEnabled(_ enabled: Bool) {
        self.runtime.isWidgetEnabled = enabled
        self.wake()
    }

    public func setPanelOpen(_ open: Bool) {
        self.runtime.isPanelOpen = open
        self.wake()
    }

    public func setOnline(_ online: Bool) {
        self.runtime.isOnline = online
        self.wake()
    }

    public func setScreenAwake(_ awake: Bool) {
        self.runtime.isScreenAwake = awake
        self.wake()
    }

    public func setSessionLocked(_ locked: Bool) {
        self.runtime.isSessionUnlocked = !locked
        self.wake()
    }

    public func setLowPower(_ lowPower: Bool) {
        self.runtime.isLowPower = lowPower
        self.wake()
    }

    // MARK: - Loop

    public func start() {
        guard self.loopTask == nil else { return }
        self.loopTask = Task { await self.runLoop() }
    }

    public func stop() {
        self.loopTask?.cancel()
        self.loopTask = nil
        self.sleeper?.cancel()
        self.sleeper = nil
        for continuation in self.continuations.values { continuation.finish() }
        self.continuations.removeAll()
    }

    private func runLoop() async {
        await self.seedFromStore()
        self.emit(self.buildSnapshot())
        while !Task.isCancelled {
            if self.runtime.isPollable, !self.entries.isEmpty {
                let snapshot = await self.tickOnce()
                self.emit(snapshot)
                await self.sleep(Self.jittered(self.currentInterval()))
            } else {
                await self.sleep(self.configuration.idleInterval)
            }
        }
    }

    private func wake() {
        self.sleeper?.cancel()
    }

    private func sleep(_ duration: Duration) async {
        let sleeper = Task { [sleepProvider] in await sleepProvider(duration) }
        self.sleeper = sleeper
        await sleeper.value
        self.sleeper = nil
    }

    private func emit(_ snapshot: TickerSnapshot) {
        for continuation in self.continuations.values {
            continuation.yield(snapshot)
        }
    }

    // MARK: - Tick

    func tickOnce() async -> TickerSnapshot {
        let requests = self.entries.map {
            TickerQuoteRequest(source: $0.source, identifier: $0.sourceIdentifier)
        }
        let outcome = await self.provider.quotes(for: requests)
        let now = self.nowProvider()
        for entry in self.entries {
            let identifier = entry.sourceIdentifier
            if let quote = outcome.quotes[identifier] {
                self.lastQuotes[identifier] = quote
                self.lastFreshAt[identifier] = now
                self.staleCounts[identifier] = 0
            } else {
                self.staleCounts[identifier, default: 0] += 1
            }
        }
        self.applyBackoff(outcome)
        await self.persist()
        return self.buildSnapshot(now: now)
    }

    private func applyBackoff(_ outcome: TickerFetchOutcome) {
        if outcome.shouldBackOff {
            self.consecutiveBackoffs += 1
            self.pendingRetryAfter = outcome.retryAfter
        } else {
            self.consecutiveBackoffs = 0
            self.pendingRetryAfter = nil
        }
    }

    func currentInterval() -> Duration {
        let base = self.baseInterval()
        guard self.consecutiveBackoffs > 0 else { return base }
        if let retryAfter = self.pendingRetryAfter {
            return min(Swift.max(base, retryAfter), self.configuration.maxBackoffInterval)
        }
        let multiplier = 1 << min(self.consecutiveBackoffs, 5)
        return min(base * multiplier, self.configuration.maxBackoffInterval)
    }

    private func baseInterval() -> Duration {
        if self.runtime.isLowPower { return self.configuration.lowPowerInterval }
        if self.runtime.isPanelOpen { return self.configuration.panelOpenInterval }
        return self.configuration.ambientInterval
    }

    // MARK: - Snapshot

    func buildSnapshot(now: Duration? = nil) -> TickerSnapshot {
        let timestamp = now ?? self.nowProvider()
        let segments = self.entries.map { entry -> TickerSegment in
            let identifier = entry.sourceIdentifier
            let quote = self.lastQuotes[identifier]
            let staleness = self.staleness(for: identifier, quote: quote, now: timestamp)
            let visible = staleness == .unavailable ? nil : quote
            return TickerSegment(
                id: entry.id,
                symbol: entry.symbol,
                displayName: entry.displayName,
                iconURL: entry.iconURL,
                price: visible?.usdPrice,
                change24h: visible?.change24h,
                staleness: staleness)
        }
        return TickerSnapshot(segments: segments)
    }

    private func staleness(for identifier: String, quote: PriceQuote?, now: Duration) -> TickerStaleness {
        guard quote != nil else { return .unavailable }
        let misses = self.staleCounts[identifier, default: 0]
        if misses < self.configuration.staleThreshold { return .fresh }
        if let freshAt = self.lastFreshAt[identifier], now - freshAt > self.configuration.expiry {
            return .unavailable
        }
        return .stale
    }

    // MARK: - Cold-start persistence

    func seedFromStore() async {
        guard let store = self.lastKnownStore else { return }
        let cached = await store.load()
        let now = self.nowProvider()
        for (identifier, last) in cached {
            self.lastQuotes[identifier] = last.quote
            self.lastFreshAt[identifier] = now
            self.staleCounts[identifier] = self.configuration.staleThreshold
        }
    }

    private func persist() async {
        guard let store = self.lastKnownStore else { return }
        let capturedAt = Date()
        var snapshot: [String: LastKnownPrice] = [:]
        for entry in self.entries {
            if let quote = self.lastQuotes[entry.sourceIdentifier] {
                snapshot[entry.sourceIdentifier] = LastKnownPrice(quote: quote, capturedAt: capturedAt)
            }
        }
        await store.save(snapshot)
    }

    // MARK: - Clock plumbing

    private static func makeNowProvider<C: Clock>(
        _ clock: C) -> @Sendable () -> Duration where C.Duration == Duration
    {
        let epoch = clock.now
        return { epoch.duration(to: clock.now) }
    }

    private static func makeSleepProvider<C: Clock>(
        _ clock: C) -> @Sendable (Duration) async -> Void where C.Duration == Duration
    {
        { duration in
            try? await clock.sleep(until: clock.now.advanced(by: duration), tolerance: nil)
        }
    }

    private static func jittered(_ duration: Duration) -> Duration {
        duration * Double.random(in: 0.85...1.15)
    }
}
