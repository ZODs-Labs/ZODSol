import Foundation
import SolanaRPC

/// RPCTransport mock that scripts JSON-RPC responses by method name. Each
/// enqueued step asserts the next call matches the expected method, then
/// returns the canned response.
actor MockSendTransport: RPCTransport {
    enum Outcome {
        case success(Data)
        case failure(RPCError)
    }

    private struct Step {
        let expectedMethod: String
        let outcome: Outcome
    }

    private var script: [Step] = []
    private(set) var observedMethods: [String] = []
    private(set) var observedBodies: [String] = []

    func enqueue(method: String, json: String) {
        self.script.append(Step(expectedMethod: method, outcome: .success(Data(json.utf8))))
    }

    func enqueue(method: String, error: RPCError) {
        self.script.append(Step(expectedMethod: method, outcome: .failure(error)))
    }

    var pendingStepCount: Int {
        self.script.count
    }

    func send<R: Decodable & Sendable>(
        _ request: JSONRPCRequest<some Encodable & Sendable>,
        responseType: R.Type) async throws -> R
    {
        self.observedMethods.append(request.method)
        if let bodyData = try? JSONEncoder().encode(request),
           let bodyString = String(data: bodyData, encoding: .utf8)
        {
            self.observedBodies.append(bodyString)
        }
        guard !self.script.isEmpty else {
            throw RPCError.transport(.unknown)
        }
        let step = self.script.removeFirst()
        precondition(
            request.method == step.expectedMethod,
            "MockSendTransport: expected \(step.expectedMethod), got \(request.method)")
        switch step.outcome {
        case let .success(data):
            return try JSONDecoder().decode(R.self, from: data)
        case let .failure(error):
            throw error
        }
    }
}
