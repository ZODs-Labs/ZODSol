import Foundation
import SolanaRPC

actor MockRPCTransport: RPCTransport {
    private var responses: [(Data?, RPCError?)] = []
    private(set) var requestCount = 0
    private(set) var lastMethod: String?

    func enqueue(data: Data) {
        self.responses.append((data, nil))
    }

    func enqueueError(_ error: RPCError) {
        self.responses.append((nil, error))
    }

    func send<R: Decodable & Sendable>(
        _ request: JSONRPCRequest<some Encodable & Sendable>,
        responseType: R.Type) async throws -> R
    {
        self.requestCount += 1
        self.lastMethod = request.method
        guard !self.responses.isEmpty else {
            throw RPCError.transport(.unknown)
        }
        let (data, error) = self.responses.removeFirst()
        if let error { throw error }
        return try JSONDecoder().decode(R.self, from: data!)
    }
}
