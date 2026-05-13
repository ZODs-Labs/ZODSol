import Foundation
import XCTest
@testable import SolanaRPC

final class CoalescingRPCTransportTests: XCTestCase {
    func test_concurrentIdenticalRequests_coalesceIntoOneInnerCall() async throws {
        let counter = MutableCounter()
        let body = #"{"jsonrpc":"2.0","id":"x","result":{"value":7}}"#
        let inner = CountingTransport(body: body, counter: counter)
        let coalesced = CoalescingRPCTransport(inner: inner)

        let request = self.makeRequest()
        async let a = coalesced.send(request, responseType: JSONRPCResponse<ValueWrapper>.self)
        async let b = coalesced.send(request, responseType: JSONRPCResponse<ValueWrapper>.self)
        async let c = coalesced.send(request, responseType: JSONRPCResponse<ValueWrapper>.self)
        let (ra, rb, rc) = try await (a, b, c)

        XCTAssertEqual(ra.result?.value, 7)
        XCTAssertEqual(rb.result?.value, 7)
        XCTAssertEqual(rc.result?.value, 7)
        XCTAssertEqual(counter.value, 1, "three concurrent identical requests should hit inner once")
    }

    func test_serialIdenticalRequests_doNotShareCompletedTasks() async throws {
        let counter = MutableCounter()
        let body = #"{"jsonrpc":"2.0","id":"x","result":{"value":7}}"#
        let inner = CountingTransport(body: body, counter: counter)
        let coalesced = CoalescingRPCTransport(inner: inner)

        let request = self.makeRequest()
        _ = try await coalesced.send(request, responseType: JSONRPCResponse<ValueWrapper>.self)
        _ = try await coalesced.send(request, responseType: JSONRPCResponse<ValueWrapper>.self)
        XCTAssertEqual(counter.value, 2, "serial calls should each hit inner; the coalescer only dedupes inflight")
    }

    func test_sendTransaction_isNotCoalesced() async throws {
        let counter = MutableCounter()
        let body = #"{"jsonrpc":"2.0","id":"x","result":"sig"}"#
        let inner = CountingTransport(body: body, counter: counter)
        let coalesced = CoalescingRPCTransport(inner: inner)

        let request = JSONRPCRequest(method: "sendTransaction", params: ["txBytes"], id: "x")
        async let a = coalesced.send(request, responseType: JSONRPCResponse<String>.self)
        async let b = coalesced.send(request, responseType: JSONRPCResponse<String>.self)
        let (ra, rb) = try await (a, b)
        XCTAssertEqual(ra.result, "sig")
        XCTAssertEqual(rb.result, "sig")
        XCTAssertEqual(counter.value, 2, "mutating methods must never be coalesced")
    }

    private func makeRequest() -> JSONRPCRequest<[String]> {
        JSONRPCRequest(method: "getBalance", params: ["address1"], id: "stable-id")
    }
}

private struct ValueWrapper: Decodable {
    let value: Int
}

private actor CountingTransport: RPCTransport {
    private let body: String
    private let counter: MutableCounter

    init(body: String, counter: MutableCounter) {
        self.body = body
        self.counter = counter
    }

    func send<R: Decodable & Sendable>(
        _ request: JSONRPCRequest<some Encodable & Sendable>,
        responseType: R.Type) async throws -> R
    {
        _ = self.counter.incrementAndGet()
        try? await Task.sleep(for: .milliseconds(40))
        guard let data = self.body.data(using: .utf8) else {
            throw RPCError.decoding("invalid utf8")
        }
        return try JSONDecoder().decode(R.self, from: data)
    }
}
