import Foundation
import OSLog

actor JupiterClient {
    private let session: URLSession
    private let logger = Logger(subsystem: "dev.zods.zodsol", category: "helius")

    init(session: URLSession = .shared) {
        self.session = session
    }

    func fetchPrices(mints: [String]) async -> JupiterPriceResponse? {
        guard !mints.isEmpty else { return nil }
        var c = URLComponents(url: JupiterEndpoint.priceV3, resolvingAgainstBaseURL: false)
        c?.queryItems = [URLQueryItem(name: "ids", value: mints.joined(separator: ","))]
        guard let url = c?.url else { return nil }
        do {
            let (data, response) = try await session.data(from: url)
            guard let http = response as? HTTPURLResponse,
                  (200 ..< 300).contains(http.statusCode) else {
                logger.debug("jupiter price non-2xx")
                return nil
            }
            return try JSONDecoder().decode(JupiterPriceResponse.self, from: data)
        } catch {
            logger.debug("jupiter price fetch failed")
            return nil
        }
    }
}
