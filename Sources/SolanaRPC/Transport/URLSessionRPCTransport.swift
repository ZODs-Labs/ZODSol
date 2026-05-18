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
        session: URLSession,
        retryPolicy: RetryPolicy = .default,
        logger: Logger = Logger(subsystem: "dev.zods.zodsol", category: "rpc"))
    {
        var components = URLComponents(url: endpoint, resolvingAgainstBaseURL: true) ?? URLComponents()
        let existing = components.queryItems ?? []
        let combined = existing + queryItems
        components.queryItems = combined.isEmpty ? nil : combined
        self.endpoint = components.url ?? endpoint
        self.headers = headers
        self.session = session
        self.retryPolicy = retryPolicy
        self.logger = logger
    }

    public init(
        endpoint: URL,
        headers: [String: String] = [:],
        queryItems: [URLQueryItem] = [],
        configuration: URLSessionConfiguration = .makeDefault(),
        retryPolicy: RetryPolicy = .default,
        logger: Logger = Logger(subsystem: "dev.zods.zodsol", category: "rpc"))
    {
        self.init(
            endpoint: endpoint,
            headers: headers,
            queryItems: queryItems,
            session: URLSession(configuration: configuration),
            retryPolicy: retryPolicy,
            logger: logger)
    }

    public func send<R: Decodable & Sendable>(
        _ request: JSONRPCRequest<some Encodable & Sendable>,
        responseType: R.Type) async throws -> R
    {
        try await self.sendUsing(
            retryPolicy: self.retryPolicy,
            request: request,
            responseType: responseType)
    }

    public func sendOnce<R: Decodable & Sendable>(
        _ request: JSONRPCRequest<some Encodable & Sendable>,
        responseType: R.Type) async throws -> R
    {
        try await self.sendUsing(
            retryPolicy: .none,
            request: request,
            responseType: responseType)
    }

    private func sendUsing<R: Decodable & Sendable>(
        retryPolicy: RetryPolicy,
        request: JSONRPCRequest<some Encodable & Sendable>,
        responseType: R.Type) async throws -> R
    {
        let urlRequest = try self.buildURLRequest(request: request)
        var lastError: RPCError = .transport(.unknown)
        for attempt in 1...retryPolicy.maxAttempts {
            do {
                try Task.checkCancellation()
                let (data, http) = try await self.performHTTPExchange(
                    urlRequest: urlRequest,
                    method: request.method,
                    attempt: attempt)
                switch try Self.classifyStatus(http) {
                case .ok:
                    return try Self.decodeOrThrow(data: data, as: R.self)
                case let .retryable(error, retryAfter):
                    lastError = error
                    if attempt == retryPolicy.maxAttempts { throw lastError }
                    try await Task.sleep(for: retryPolicy.delay(for: attempt, retryAfter: retryAfter))
                }
            } catch is CancellationError {
                throw RPCError.canceled
            } catch let e as RPCError where Self.isTerminal(e) {
                throw e
            } catch let e as RPCError {
                lastError = e
                if attempt == retryPolicy.maxAttempts { throw lastError }
                try await Task.sleep(for: retryPolicy.delay(for: attempt, retryAfter: nil))
            } catch {
                throw error
            }
        }
        throw lastError
    }

    private func buildURLRequest(
        request: JSONRPCRequest<some Encodable & Sendable>) throws -> URLRequest
    {
        var urlRequest = URLRequest(url: self.endpoint)
        urlRequest.httpMethod = "POST"
        for (key, value) in self.headers {
            urlRequest.setValue(value, forHTTPHeaderField: key)
        }
        urlRequest.httpBody = try request.encodedBodyData()
        return urlRequest
    }

    private enum StatusClass {
        case ok
        case retryable(RPCError, retryAfter: Duration?)
    }

    private static func classifyStatus(_ http: HTTPURLResponse) throws -> StatusClass {
        switch http.statusCode {
        case 200..<300:
            return .ok
        case 401, 403:
            throw RPCError.http(status: http.statusCode, retryAfter: nil)
        case 429:
            let retryAfter = self.parseRetryAfter(http)
            return .retryable(.http(status: 429, retryAfter: retryAfter), retryAfter: retryAfter)
        case 500..<600:
            return .retryable(.http(status: http.statusCode, retryAfter: nil), retryAfter: nil)
        default:
            throw RPCError.http(status: http.statusCode, retryAfter: nil)
        }
    }

    private static func decodeOrThrow<R: Decodable>(data: Data, as: R.Type) throws -> R {
        do {
            return try JSONDecoder().decode(R.self, from: data)
        } catch {
            throw RPCError.decoding(String(describing: error))
        }
    }

    private static func isTerminal(_ error: RPCError) -> Bool {
        if error == .canceled { return true }
        if error == .http(status: 401, retryAfter: nil) { return true }
        if error == .http(status: 403, retryAfter: nil) { return true }
        return false
    }

    private func performHTTPExchange(
        urlRequest: URLRequest,
        method: String,
        attempt: Int) async throws -> (Data, HTTPURLResponse)
    {
        var didRetryStaleConnection = false
        while true {
            do {
                let (data, response) = try await self.session.data(for: urlRequest)
                guard let http = response as? HTTPURLResponse else {
                    throw RPCError.transport(.badServerResponse)
                }
                self.logger.debug("rpc \(method, privacy: .public) attempt=\(attempt) status=\(http.statusCode)")
                return (data, http)
            } catch let urlErr as URLError where urlErr.code == .cancelled {
                throw RPCError.canceled
            } catch let urlErr as URLError {
                if Self.isTransientConnectionLoss(urlErr.code), !didRetryStaleConnection {
                    didRetryStaleConnection = true
                    try await Task.sleep(for: .milliseconds(200))
                    continue
                }
                throw RPCError.transport(urlErr.code)
            }
        }
    }

    private static func isTransientConnectionLoss(_ code: URLError.Code) -> Bool {
        switch code {
        case .networkConnectionLost, .cannotConnectToHost, .dnsLookupFailed:
            true
        default:
            false
        }
    }

    private static func parseRetryAfter(_ http: HTTPURLResponse) -> Duration? {
        guard let raw = http.value(forHTTPHeaderField: "Retry-After") else { return nil }
        guard let seconds = Int(raw.trimmingCharacters(in: .whitespaces)) else { return nil }
        return .seconds(seconds)
    }
}
