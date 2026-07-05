import Foundation
import OSLog
import SolanaKit

/// Keyless cross-chain spot prices for blue-chip assets (SOL, BTC, ETH and
/// other major CEX-listed coins) that Jupiter can only price as bridged-Solana
/// proxies. Kraken is primary (keyless, batched, no monthly cap); Coinbase
/// Exchange is the per-symbol fallback when a Kraken tick fails.
///
/// The injected `URLSession` must be credential-free: this client must never
/// share the session that carries the Helius `?api-key=` query item, so no key
/// can leak to a third-party market-data host.
actor BlueChipPriceClient {
    private let session: URLSession
    private let logger = Logger(subsystem: "dev.zods.zodsol", category: "bluechip")

    init(session: URLSession) {
        self.session = session
    }

    /// One batched Kraken call, returning an outcome whose `quotes` are keyed by
    /// the pair codes passed in (== the returned legacy keys, by construction).
    /// Pairs absent from the response are simply missing. `shouldBackOff` is set
    /// on 429 / 5xx / network error / a rate-limit `error` entry so the engine
    /// eases its cadence; a non-rate-limit `error` array leaves the pairs
    /// unpriced without forcing a backoff.
    func fetchKraken(pairs: [String]) async -> TickerFetchOutcome {
        guard !pairs.isEmpty else { return .empty }
        var components = URLComponents(url: KrakenEndpoint.ticker, resolvingAgainstBaseURL: false)
        components?.queryItems = [URLQueryItem(name: "pair", value: pairs.joined(separator: ","))]
        guard let url = components?.url else { return .empty }
        do {
            let (data, response) = try await self.session.data(from: url)
            guard let http = response as? HTTPURLResponse else { return Self.failed() }
            guard (200..<300).contains(http.statusCode) else {
                self.logger.debug("kraken non-2xx")
                return Self.failed(retryAfter: Self.retryAfter(from: http, status: http.statusCode))
            }
            let decoded = try JSONDecoder().decode(KrakenTickerResponse.self, from: data)
            guard decoded.error.isEmpty else {
                self.logger.debug("kraken error array non-empty")
                return TickerFetchOutcome(quotes: [:], retryAfter: nil, shouldBackOff: Self.isRateLimit(decoded.error))
            }
            var quotes: [String: PriceQuote] = [:]
            for pair in pairs {
                guard let entry = decoded.result[pair] else { continue }
                quotes[pair] = Self.quote(last: entry.c.first, open: entry.o)
            }
            return TickerFetchOutcome(quotes: quotes, retryAfter: nil, shouldBackOff: false)
        } catch {
            self.logger.debug("kraken fetch failed")
            return Self.failed()
        }
    }

    /// Coinbase fallback: one GET per product, invoked only for the blue-chip
    /// subset when a Kraken tick failed. `quotes` are keyed by the same pair code
    /// used in `fetchKraken`; products that fail are omitted, and a 429 on any
    /// product sets `shouldBackOff`.
    func fetchCoinbase(products: [String: String]) async -> TickerFetchOutcome {
        var quotes: [String: PriceQuote] = [:]
        var retryAfter: Duration?
        var backOff = false
        for (pairCode, product) in products {
            do {
                let (data, response) = try await self.session.data(from: CoinbaseEndpoint.stats(product: product))
                guard let http = response as? HTTPURLResponse else { backOff = true; continue }
                guard (200..<300).contains(http.statusCode) else {
                    backOff = true
                    retryAfter = retryAfter ?? Self.retryAfter(from: http, status: http.statusCode)
                    continue
                }
                let stats = try JSONDecoder().decode(CoinbaseStats.self, from: data)
                quotes[pairCode] = Self.quote(last: stats.last, open: stats.open)
            } catch {
                backOff = true
            }
        }
        return TickerFetchOutcome(quotes: quotes, retryAfter: retryAfter, shouldBackOff: backOff)
    }

    private static func failed(retryAfter: Duration? = nil) -> TickerFetchOutcome {
        TickerFetchOutcome(quotes: [:], retryAfter: retryAfter, shouldBackOff: true)
    }

    private static func isRateLimit(_ errors: [String]) -> Bool {
        errors.contains { error in
            let lower = error.lowercased()
            return lower.contains("rate limit") || lower.contains("too many")
        }
    }

    /// Honors `Retry-After` only on 429 (a 5xx Retry-After is not load-shedding
    /// guidance). Parses the integer-seconds form; the HTTP-date form is ignored.
    private static func retryAfter(from response: HTTPURLResponse, status: Int) -> Duration? {
        guard status == 429,
              let header = response.value(forHTTPHeaderField: "Retry-After"),
              let seconds = Double(header.trimmingCharacters(in: .whitespaces)),
              seconds > 0
        else {
            return nil
        }
        return .seconds(seconds)
    }

    /// Both Kraken (`o`) and Coinbase (`open`) give a 24h-open price, not a
    /// percentage, so the change is computed `(last - open) / open * 100`,
    /// matching what the exchanges' own tickers display. Price stays `Decimal`
    /// (parsed locale-independently on "."); only the change is `Double`.
    private static func quote(last: String?, open: String?) -> PriceQuote {
        let price = last.flatMap { Decimal(string: $0) }
        var change: Double?
        if let last, let open, let lastValue = Double(last), let openValue = Double(open), openValue != 0 {
            change = (lastValue - openValue) / openValue * 100
        }
        return PriceQuote(usdPrice: price, change24h: change)
    }
}
