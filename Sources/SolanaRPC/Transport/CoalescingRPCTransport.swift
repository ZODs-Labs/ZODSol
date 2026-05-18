import Foundation

public actor CoalescingRPCTransport: RPCTransport {
    private static let methodsToCoalesce: Set<String> = [
        "getAssetsByOwner",
        "getBalance",
        "getTokenAccountsByOwner",
        "getAccountInfo",
        "getEpochInfo",
        "getRecentPrioritizationFees",
        "getSignatureStatuses",
        "getLatestBlockhash",
    ]

    private let inner: any RPCTransport
    private let dedupKey: @Sendable (String, Data) -> String?
    private var inflight: [String: Task<Data, any Error>] = [:]

    public init(
        inner: any RPCTransport,
        dedupKey: (@Sendable (String, Data) -> String?)? = nil)
    {
        self.inner = inner
        self.dedupKey = dedupKey ?? CoalescingRPCTransport.defaultDedupKey
    }

    public func send<R: Decodable & Sendable>(
        _ request: JSONRPCRequest<some Encodable & Sendable>,
        responseType: R.Type) async throws -> R
    {
        guard Self.methodsToCoalesce.contains(request.method) else {
            return try await self.inner.send(request, responseType: responseType)
        }
        let bodyData = try request.encodedBodyData()
        let requestKey = try request.deduplicationKey() ?? self.dedupKey(request.method, bodyData)
        guard let key = requestKey else {
            return try await self.inner.send(request, responseType: responseType)
        }
        let task = self.acquireTask(forKey: key, request: request)
        let raw = try await task.value
        do {
            return try JSONDecoder().decode(R.self, from: raw)
        } catch {
            throw RPCError.decoding(String(describing: error))
        }
    }

    public func sendOnce<R: Decodable & Sendable>(
        _ request: JSONRPCRequest<some Encodable & Sendable>,
        responseType: R.Type) async throws -> R
    {
        try await self.inner.sendOnce(request, responseType: responseType)
    }

    private func acquireTask(
        forKey key: String,
        request: JSONRPCRequest<some Encodable & Sendable>) -> Task<Data, any Error>
    {
        if let existing = inflight[key] { return existing }
        let inner = self.inner
        let task = Task<Data, any Error> {
            let envelope = try await inner.send(request, responseType: JSONRPCEnvelope.self)
            return try JSONEncoder().encode(envelope)
        }
        self.inflight[key] = task
        Task { [weak self] in
            _ = await task.result
            await self?.evict(key: key)
        }
        return task
    }

    private func evict(key: String) {
        self.inflight.removeValue(forKey: key)
    }

    public static let defaultDedupKey: @Sendable (String, Data) -> String? = { method, body in
        guard methodsToCoalesce.contains(method) else { return nil }
        return "\(method):\(body.hashValue)"
    }
}

private struct JSONRPCEnvelope: Codable {
    let jsonrpc: String
    let id: String
    let result: AnyJSON?
    let error: AnyJSON?
}
