public protocol RPCTransport: Sendable {
    func send<P: Encodable & Sendable, R: Decodable & Sendable>(
        _ request: JSONRPCRequest<P>,
        responseType: R.Type
    ) async throws -> R
}
