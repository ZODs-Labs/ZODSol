public protocol RPCTransport: Sendable {
    func send<R: Decodable & Sendable>(
        _ request: JSONRPCRequest<some Encodable & Sendable>,
        responseType: R.Type) async throws -> R

    /// Send one HTTP attempt, bypassing any client-side retry the transport
    /// implements. The default delegates to `send` and is correct for
    /// transports that don't retry (mocks, simple proxies). Concrete
    /// production transports should override to skip their retry loop —
    /// `sendTransaction` is the canonical caller.
    func sendOnce<R: Decodable & Sendable>(
        _ request: JSONRPCRequest<some Encodable & Sendable>,
        responseType: R.Type) async throws -> R
}

extension RPCTransport {
    public func sendOnce<R: Decodable & Sendable>(
        _ request: JSONRPCRequest<some Encodable & Sendable>,
        responseType: R.Type) async throws -> R
    {
        try await send(request, responseType: responseType)
    }
}
