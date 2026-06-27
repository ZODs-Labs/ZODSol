import Foundation

/// A single price lookup routed to a specific source. The engine builds these
/// from frozen `TickerEntry` values; the provider groups them by `source`.
public struct TickerQuoteRequest: Sendable, Hashable {
    public let source: TickerPriceSource
    public let identifier: String

    public init(source: TickerPriceSource, identifier: String) {
        self.source = source
        self.identifier = identifier
    }
}

/// The result of one ticker fetch cycle. `quotes` is keyed by request
/// `identifier` and may be partial. `retryAfter` carries an upstream
/// `Retry-After` when a source signalled rate limiting; `shouldBackOff` is true
/// whenever any source rate-limited or errored, so the engine can ease its
/// cadence instead of hammering.
public struct TickerFetchOutcome: Sendable, Equatable {
    public let quotes: [String: PriceQuote]
    public let retryAfter: Duration?
    public let shouldBackOff: Bool

    public init(quotes: [String: PriceQuote], retryAfter: Duration?, shouldBackOff: Bool) {
        self.quotes = quotes
        self.retryAfter = retryAfter
        self.shouldBackOff = shouldBackOff
    }

    public static let empty = TickerFetchOutcome(quotes: [:], retryAfter: nil, shouldBackOff: false)
}

/// Fetches USD quotes for a set of source-routed ticker requests, batching per
/// source and tolerating partial failure. Implementations MUST NOT throw: a
/// failed source contributes no quotes and sets `shouldBackOff`.
public protocol TickerQuoteProviding: Sendable {
    func quotes(for requests: [TickerQuoteRequest]) async -> TickerFetchOutcome
}
