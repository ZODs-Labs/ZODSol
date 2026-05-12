import Foundation

public struct RetryPolicy: Sendable {
    public var maxAttempts: Int
    public var initialDelay: Duration
    public var maxDelay: Duration
    public var jitter: Double

    public static let `default` = RetryPolicy()
    /// Single-attempt policy: 5xx and 429 propagate immediately without delay.
    /// Used by `RPCTransport.sendOnce` for transactions where the network
    /// dedupes by signature and a client-side retry adds no safety.
    public static let none = RetryPolicy(maxAttempts: 1)

    public init(
        maxAttempts: Int = 3,
        initialDelay: Duration = .seconds(1),
        maxDelay: Duration = .seconds(30),
        jitter: Double = 0.25)
    {
        self.maxAttempts = maxAttempts
        self.initialDelay = initialDelay
        self.maxDelay = maxDelay
        self.jitter = jitter
    }

    public func delay(for attempt: Int, retryAfter: Duration?) -> Duration {
        if let ra = retryAfter { return min(ra, self.maxDelay) }
        let exponent = max(0, attempt - 1)
        let c = self.initialDelay.components
        let initialNanos = Double(c.seconds) * 1_000_000_000.0
            + Double(c.attoseconds) / 1_000_000_000.0
        let nominalNanos = initialNanos * pow(2.0, Double(exponent))
        let mc = self.maxDelay.components
        let maxNanos = Double(mc.seconds) * 1_000_000_000.0
            + Double(mc.attoseconds) / 1_000_000_000.0
        let cappedNanos = min(nominalNanos, maxNanos)
        let multiplier = 1.0 + Double.random(in: -self.jitter...self.jitter)
        return .nanoseconds(Int64(cappedNanos * multiplier))
    }
}
