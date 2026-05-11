import Foundation
import SolanaRPC

actor MockRPCTransport: RPCTransport {
    private var responses: [(Data?, RPCError?)] = []
    private(set) var requestCount = 0
    private(set) var lastMethod: String?

    func enqueue(data: Data) {
        responses.append((data, nil))
    }

    func enqueueError(_ error: RPCError) {
        responses.append((nil, error))
    }

    func send<P, R>(
        _ request: JSONRPCRequest<P>,
        responseType: R.Type
    ) async throws -> R where P: Encodable & Sendable, R: Decodable & Sendable {
        requestCount += 1
        lastMethod = request.method
        guard !responses.isEmpty else {
            throw RPCError.transport(.unknown)
        }
        let (data, error) = responses.removeFirst()
        if let error { throw error }
        return try JSONDecoder().decode(R.self, from: data!)
    }
}
