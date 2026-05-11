import Foundation
import OSLog

public actor URLSessionRPCTransport: RPCTransport {
    private let endpoint: URL
    private let headers: [String: String]
    private let session: URLSession
    private let retryPolicy: RetryPolicy
    private let logger: Logger

    public init(
        endpoint: URL,
        headers: [String: String] = [:],
        queryItems: [URLQueryItem] = [],
        configuration: URLSessionConfiguration = .makeDefault(),
        retryPolicy: RetryPolicy = .default,
        logger: Logger = Logger(subsystem: "dev.zods.zodsol", category: "rpc")
    ) {
        var components = URLComponents(url: endpoint, resolvingAgainstBaseURL: true) ?? URLComponents()
        let existing = components.queryItems ?? []
        let combined = existing + queryItems
        components.queryItems = combined.isEmpty ? nil : combined
        self.endpoint = components.url ?? endpoint
        self.headers = headers
        self.session = URLSession(configuration: configuration)
        self.retryPolicy = retryPolicy
        self.logger = logger
    }

    public func send<P, R>(
        _ request: JSONRPCRequest<P>,
        responseType: R.Type
    ) async throws -> R where P: Encodable & Sendable, R: Decodable & Sendable {
        var urlRequest = URLRequest(url: endpoint)
        urlRequest.httpMethod = "POST"
        for (k, v) in headers { urlRequest.setValue(v, forHTTPHeaderField: k) }
        urlRequest.httpBody = try JSONEncoder().encode(request)

        var lastError: RPCError = .transport(.unknown)
        for attempt in 1 ... retryPolicy.maxAttempts {
            do {
                try Task.checkCancellation()
                let (data, response) = try await session.data(for: urlRequest)
                guard let http = response as? HTTPURLResponse else {
                    throw RPCError.transport(.badServerResponse)
                }
                logger.debug("rpc \(request.method, privacy: .public) attempt=\(attempt) status=\(http.statusCode)")
                switch http.statusCode {
                case 200 ..< 300:
                    do {
                        return try JSONDecoder().decode(R.self, from: data)
                    } catch {
                        throw RPCError.decoding(String(describing: error))
                    }
                case 401, 403:
                    throw RPCError.http(status: http.statusCode, retryAfter: nil)
                case 429:
                    let ra = Self.parseRetryAfter(http)
                    lastError = .http(status: 429, retryAfter: ra)
                    if attempt == retryPolicy.maxAttempts { throw lastError }
                    try await Task.sleep(for: retryPolicy.delay(for: attempt, retryAfter: ra))
                case 500 ..< 600:
                    lastError = .http(status: http.statusCode, retryAfter: nil)
                    if attempt == retryPolicy.maxAttempts { throw lastError }
                    try await Task.sleep(for: retryPolicy.delay(for: attempt, retryAfter: nil))
                default:
                    throw RPCError.http(status: http.statusCode, retryAfter: nil)
                }
            } catch is CancellationError {
                throw RPCError.canceled
            } catch let e as RPCError
                where e == .canceled
                    || e == .http(status: 401, retryAfter: nil)
                    || e == .http(status: 403, retryAfter: nil) {
                throw e
            } catch let urlErr as URLError where urlErr.code == .cancelled {
                throw RPCError.canceled
            } catch let urlErr as URLError {
                lastError = .transport(urlErr.code)
                if attempt == retryPolicy.maxAttempts { throw lastError }
                try await Task.sleep(for: retryPolicy.delay(for: attempt, retryAfter: nil))
            } catch {
                throw error
            }
        }
        throw lastError
    }

    private static func parseRetryAfter(_ http: HTTPURLResponse) -> Duration? {
        guard let raw = http.value(forHTTPHeaderField: "Retry-After") else { return nil }
        guard let seconds = Int(raw.trimmingCharacters(in: .whitespaces)) else { return nil }
        return .seconds(seconds)
    }
}
