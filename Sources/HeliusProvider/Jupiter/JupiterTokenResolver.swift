import Foundation
import OSLog
import SolanaKit

/// Resolves a pasted Solana mint to ticker display metadata via the keyless
/// Jupiter `tokens/v2/search` endpoint. Uses the same credential-free session as
/// the price clients so a paste never touches the Helius key.
public struct JupiterTokenResolver: TickerTokenResolving {
    private let client: JupiterTokenSearchClient

    public init(session: URLSession) {
        self.client = JupiterTokenSearchClient(session: session)
    }

    public func resolve(mint: String) async -> ResolvedTickerToken? {
        await self.client.resolve(mint: mint)
    }
}

actor JupiterTokenSearchClient {
    private let session: URLSession
    private let logger = Logger(subsystem: "dev.zods.zodsol", category: "helius")

    init(session: URLSession) {
        self.session = session
    }

    func resolve(mint: String) async -> ResolvedTickerToken? {
        var components = URLComponents(url: JupiterEndpoint.tokensSearch, resolvingAgainstBaseURL: false)
        components?.queryItems = [URLQueryItem(name: "query", value: mint)]
        guard let url = components?.url else { return nil }
        do {
            let (data, response) = try await self.session.data(from: url)
            guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
                self.logger.debug("jupiter token search non-2xx")
                return nil
            }
            let results = try JSONDecoder().decode([JupiterTokenSearchResult].self, from: data)
            // Require an exact mint match so a fuzzy symbol hit never gets
            // mistaken for the pasted address.
            guard let match = results.first(where: { $0.id == mint }) else { return nil }
            return ResolvedTickerToken(
                mint: match.id,
                symbol: match.symbol ?? Self.shortMint(mint),
                name: match.name ?? match.symbol ?? Self.shortMint(mint),
                decimals: match.decimals ?? 0,
                iconURL: match.icon.flatMap(URL.init(string:)))
        } catch {
            self.logger.debug("jupiter token search failed")
            return nil
        }
    }

    private static func shortMint(_ mint: String) -> String {
        mint.count > 8 ? "\(mint.prefix(4))…\(mint.suffix(4))" : mint
    }
}
