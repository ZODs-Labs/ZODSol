public enum CacheRead<Value: Sendable>: Sendable {
    case fresh(Value)
    case stale(Value)
    case miss
}

extension CacheRead: Equatable where Value: Equatable {}
