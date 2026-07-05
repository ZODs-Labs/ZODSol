import Foundation
import OSLog
import SolanaKit

/// Keyless DefiLlama fallback prices for EVM tokens, keyed by `sourceIdentifier`.
/// Best-effort: never throws, and omits any coin that is missing, non-positive or
/// below the confidence threshold. The injected session must be credential-free.
actor DefiLlamaClient {
    private let session: URLSession
    private let logger = Logger(subsystem: "dev.zods.zodsol", category: "defillama")

    private static let minimumConfidence = 0.8

    init(session: URLSession) {
        self.session = session
    }

    func prices(refs: [EVMTokenRef]) async -> [String: PriceQuote] {
        guard !refs.isEmpty else { return [:] }
        var keyToRef: [String: EVMTokenRef] = [:]
        for ref in refs {
            keyToRef["\(ref.chain.defiLlamaId):\(ref.address)"] = ref
        }
        let coins = Array(keyToRef.keys)

        async let currentTask = self.get(DefiLlamaEndpoint.currentPrices(coins), as: DefiLlamaCurrentResponse.self)
        async let percentTask = self.get(DefiLlamaEndpoint.percentage(coins), as: DefiLlamaPercentageResponse.self)
        let (current, percent) = await (currentTask, percentTask)
        guard let current else { return [:] }

        var quotes: [String: PriceQuote] = [:]
        for (key, coin) in current.coins {
            guard let ref = keyToRef[key], let price = coin.price, price > 0 else { continue }
            if let confidence = coin.confidence, confidence < Self.minimumConfidence { continue }
            // /percentage returns a signed fraction (-0.0035); scale to the percent
            // convention that PriceQuote.change24h uses everywhere else.
            let change = percent?.coins[key].flatMap { $0.isFinite ? $0 * 100 : nil }
            quotes[ref.sourceIdentifier] = PriceQuote(usdPrice: price, change24h: change)
        }
        return quotes
    }

    private func get<T: Decodable>(_ url: URL, as type: T.Type) async -> T? {
        do {
            let (data, response) = try await self.session.data(from: url)
            guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
                self.logger.debug("defillama non-2xx")
                return nil
            }
            return try JSONDecoder().decode(T.self, from: data)
        } catch {
            self.logger.debug("defillama fetch failed")
            return nil
        }
    }
}
