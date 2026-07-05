import Foundation
import OSLog

/// Low-level keyless DexScreener access shared by the resolver (cross-chain
/// search) and the price client (chain-scoped batch). The injected `URLSession`
/// must be credential-free so no key can leak to a third-party market-data host.
actor DexScreenerClient {
    private let session: URLSession
    private let logger = Logger(subsystem: "dev.zods.zodsol", category: "dexscreener")

    init(session: URLSession) {
        self.session = session
    }

    enum SearchOutcome {
        case pairs([DexScreenerPair])
        case failed
    }

    /// Cross-chain search by token address. Chain-agnostic: the response carries
    /// a `chainId` per pair, which is how we detect which chain hosts the token.
    func search(address: String) async -> SearchOutcome {
        var components = URLComponents(url: DexScreenerEndpoint.search, resolvingAgainstBaseURL: false)
        components?.queryItems = [URLQueryItem(name: "q", value: address)]
        guard let url = components?.url else { return .failed }
        do {
            let (data, response) = try await self.session.data(from: url)
            guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
                self.logger.debug("dexscreener search non-2xx")
                return .failed
            }
            let decoded = try JSONDecoder().decode(DexScreenerSearchResponse.self, from: data)
            return .pairs(decoded.pairs ?? [])
        } catch {
            self.logger.debug("dexscreener search failed")
            return .failed
        }
    }

    struct BatchOutcome {
        let pairs: [DexScreenerPair]
        let shouldBackOff: Bool
        let retryAfter: Duration?

        static let empty = BatchOutcome(pairs: [], shouldBackOff: false, retryAfter: nil)
        static func failed(retryAfter: Duration? = nil) -> BatchOutcome {
            BatchOutcome(pairs: [], shouldBackOff: true, retryAfter: retryAfter)
        }
    }

    /// Chain-scoped batch for the refresh loop: one call prices every tracked
    /// token on a chain. Sets `shouldBackOff` on 429 / 5xx / network error.
    func tokenPairs(chainId: String, addresses: [String]) async -> BatchOutcome {
        guard !addresses.isEmpty else { return .empty }
        let url = DexScreenerEndpoint.tokens(chainId: chainId, addresses: addresses)
        do {
            let (data, response) = try await self.session.data(from: url)
            guard let http = response as? HTTPURLResponse else { return .failed() }
            guard (200..<300).contains(http.statusCode) else {
                self.logger.debug("dexscreener tokens non-2xx")
                return .failed(retryAfter: Self.retryAfter(from: http))
            }
            let pairs = try JSONDecoder().decode([DexScreenerPair].self, from: data)
            return BatchOutcome(pairs: pairs, shouldBackOff: false, retryAfter: nil)
        } catch {
            self.logger.debug("dexscreener tokens failed")
            return .failed()
        }
    }

    /// Honors integer-seconds `Retry-After` on 429 only, matching BlueChipPriceClient.
    private static func retryAfter(from response: HTTPURLResponse) -> Duration? {
        guard response.statusCode == 429,
              let header = response.value(forHTTPHeaderField: "Retry-After"),
              let seconds = Double(header.trimmingCharacters(in: .whitespaces)),
              seconds > 0
        else {
            return nil
        }
        return .seconds(seconds)
    }
}
