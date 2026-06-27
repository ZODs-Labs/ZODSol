import Foundation
import SolanaKit

/// One persisted price snapshot, keyed elsewhere by the ticker entry's
/// `sourceIdentifier`. Holds only a public price quote and its capture time,
/// never anything wallet-derived.
public struct LastKnownPrice: Sendable, Codable, Equatable {
    public let quote: PriceQuote
    public let capturedAt: Date

    public init(quote: PriceQuote, capturedAt: Date) {
        self.quote = quote
        self.capturedAt = capturedAt
    }
}

/// UserDefaults-backed cache of the last good prices, so the menu bar can paint
/// a (dimmed) snapshot the instant the app launches, before the first network
/// fetch returns. Capped and age-pruned so it never grows unbounded. Stores
/// public prices only.
public actor LastKnownPricesStore {
    public static let defaultsKey = "dev.zods.zodsol.lastKnownPrices"
    public static let maxEntries = 50
    public static let maxAge: TimeInterval = 7 * 24 * 60 * 60

    private let defaults: UserDefaults
    private let key: String

    public init(defaults: UserDefaults = .standard, key: String = LastKnownPricesStore.defaultsKey) {
        self.defaults = defaults
        self.key = key
    }

    /// Returns the cached prices keyed by `sourceIdentifier`, dropping any entry
    /// older than `maxAge` so a stale snapshot never seeds the bar.
    public func load(now: Date = Date()) -> [String: LastKnownPrice] {
        let cutoff = now.addingTimeInterval(-Self.maxAge)
        return self.readAll().filter { $0.value.capturedAt >= cutoff }
    }

    /// Persists the given prices, keeping at most `maxEntries` newest by capture
    /// time so the blob stays bounded.
    public func save(_ prices: [String: LastKnownPrice]) {
        guard prices.count > Self.maxEntries else {
            self.writeAll(prices)
            return
        }
        let newest = prices.sorted { $0.value.capturedAt > $1.value.capturedAt }
            .prefix(Self.maxEntries)
        self.writeAll(Dictionary(uniqueKeysWithValues: newest.map { ($0.key, $0.value) }))
    }

    // MARK: - Storage

    private func readAll() -> [String: LastKnownPrice] {
        guard let data = defaults.data(forKey: key) else { return [:] }
        return (try? JSONDecoder().decode([String: LastKnownPrice].self, from: data)) ?? [:]
    }

    private func writeAll(_ prices: [String: LastKnownPrice]) {
        if prices.isEmpty {
            self.defaults.removeObject(forKey: self.key)
            return
        }
        guard let data = try? JSONEncoder().encode(prices) else { return }
        self.defaults.set(data, forKey: self.key)
    }
}
