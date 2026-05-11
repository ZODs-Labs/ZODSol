// Signature matches the specification. Internally uses a nowProvider closure to
// type-erase Clock.Instant, enabling any Clock<Duration> parameter without
// existential Instant arithmetic. The private makeNowProvider helper is opened
// at call-site via implicit existential opening (SE-0352, Swift 5.7+).
public actor TimedCache<Key: Hashable & Sendable, Value: Sendable> {
    private struct Entry {
        let value: Value
        let expiresAt: Duration
        var lastAccessedAt: Duration
    }

    private var entries: [Key: Entry] = [:]
    private let ttl: Duration
    private let capacity: Int
    private let nowProvider: @Sendable () -> Duration

    public init(ttl: Duration, capacity: Int = 32, clock: any Clock<Duration> = ContinuousClock()) {
        self.ttl = ttl
        self.capacity = capacity
        self.nowProvider = Self.makeNowProvider(clock)
    }

    // Opens the any Clock<Duration> existential to capture a concrete epoch and
    // compute a monotonically increasing Duration offset on each call.
    private static func makeNowProvider<C: Clock>(
        _ clock: C
    ) -> @Sendable () -> Duration where C.Duration == Duration {
        let epoch = clock.now
        return { epoch.duration(to: clock.now) }
    }

    public func read(_ key: Key) -> CacheRead<Value> {
        guard var entry = entries[key] else { return .miss }
        let now = nowProvider()
        entry.lastAccessedAt = now
        entries[key] = entry
        return now <= entry.expiresAt ? .fresh(entry.value) : .stale(entry.value)
    }

    public func write(_ value: Value, for key: Key) {
        let now = nowProvider()
        entries[key] = Entry(value: value, expiresAt: now + ttl, lastAccessedAt: now)
        if entries.count > capacity {
            evictLRU()
        }
    }

    public func invalidate(_ key: Key) {
        entries.removeValue(forKey: key)
    }

    public func invalidateAll() {
        entries.removeAll()
    }

    private func evictLRU() {
        guard let victim = entries.min(by: {
            $0.value.lastAccessedAt < $1.value.lastAccessedAt
        })?.key else { return }
        entries.removeValue(forKey: victim)
    }
}
