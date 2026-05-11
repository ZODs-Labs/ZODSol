import Foundation
import SolanaKit
import SolanaRPC

public struct JupiterPriceProvider: PriceProvider, Sendable {
    private let client: JupiterClient

    public init() {
        self.client = JupiterClient()
    }

    init(client: JupiterClient) {
        self.client = client
    }

    public init(transport: any SolanaRPC.RPCTransport) {
        self.client = JupiterClient()
    }

    public func priceChange24h(for mints: [Mint]) async throws -> [Mint: Double] {
        guard !mints.isEmpty else { return [:] }
        var out: [Mint: Double] = [:]
        for chunk in mints.chunked(into: 50) {
            let mintStrings = chunk.map { $0.base58 }
            guard let resp = await client.fetchPrices(mints: mintStrings) else { continue }
            for mint in chunk {
                if let entry = resp.entries[mint.base58],
                   let change = entry.priceChange24h {
                    out[mint] = change
                }
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

private extension Array {
    func chunked(into size: Int) -> [[Element]] {
        stride(from: 0, to: count, by: size).map {
            Array(self[$0 ..< Swift.min($0 + size, count)])
        }
    }
}
