public struct SWRStream<Value: Sendable>: Sendable {
    public let initial: CacheRead<Value>
    public let revalidated: AsyncStream<Value>
}

public func staleWhileRevalidate<Key: Hashable & Sendable, Value: Sendable>(
    cache: TimedCache<Key, Value>,
    key: Key,
    forceRevalidate: Bool,
    fetch: @Sendable @escaping () async throws -> Value
) async -> SWRStream<Value> {
    let initial = await cache.read(key)
    let shouldRevalidate: Bool = {
        if forceRevalidate { return true }
        switch initial {
        case .fresh: return false
        case .stale, .miss: return true
        }
    }()

    guard shouldRevalidate else {
        return SWRStream(initial: initial, revalidated: AsyncStream { $0.finish() })
    }

    let stream = AsyncStream<Value> { continuation in
        let task = Task {
            do {
                let fresh = try await fetch()
                await cache.write(fresh, for: key)
                continuation.yield(fresh)
                continuation.finish()
            } catch {
                continuation.finish()
            }
        }
        continuation.onTermination = { _ in task.cancel() }
    }
    return SWRStream(initial: initial, revalidated: stream)
}
