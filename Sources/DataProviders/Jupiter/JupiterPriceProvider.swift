import Foundation
import SolanaKit
import SolanaRPC

public struct JupiterPriceProvider: PriceProvider, Sendable {
    private let client: JupiterClient

    public init() {
        self.client = JupiterClient()
    }

    public init(session: URLSession) {
        self.client = JupiterClient(session: session)
    }

    init(client: JupiterClient) {
        self.client = client
    }

    public init(transport: any SolanaRPC.RPCTransport) {
        self.client = JupiterClient()
    }

    public func prices(for mints: [Mint]) async throws -> [Mint: PriceQuote] {
        guard !mints.isEmpty else { return [:] }
        var out: [Mint: PriceQuote] = [:]
        for chunk in mints.chunked(into: 50) {
            let mintStrings = chunk.map(\.base58)
            guard let resp = await client.fetchPrices(mints: mintStrings) else { continue }
            for mint in chunk {
                guard let entry = resp.entries[mint.base58] else { continue }
                guard entry.usdPrice != nil || entry.priceChange24h != nil else { continue }
                out[mint] = PriceQuote(usdPrice: entry.usdPrice, change24h: entry.priceChange24h)
            }
        }
        return out
    }

    public func solChange24h() async throws -> Double? {
        let wsol = "So11111111111111111111111111111111111111112"
        guard let resp = await client.fetchPrices(mints: [wsol]) else { return nil }
        return resp.entries[wsol]?.priceChange24h
    }
}

extension Array {
    fileprivate func chunked(into size: Int) -> [[Element]] {
        stride(from: 0, to: count, by: size).map {
            Array(self[$0..<Swift.min($0 + size, count)])
        }
    }
}
