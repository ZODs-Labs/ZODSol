import Foundation
import XCTest
@testable import SolanaRPC

final class RPCErrorTests: XCTestCase {
    func test_construct_eachCase() {
        let cases: [RPCError] = [
            .http(status: 500, retryAfter: nil),
            .http(status: 429, retryAfter: .seconds(2)),
            .transport(.notConnectedToInternet),
            .decoding("bad json"),
            .rpc(JSONRPCError(code: -32600, message: "Invalid Request", data: nil)),
            .canceled,
        ]
        XCTAssertEqual(cases.count, 6)
    }

    func test_equatable_sameCasesEqual() {
        XCTAssertEqual(RPCError.canceled, RPCError.canceled)
        XCTAssertEqual(RPCError.decoding("x"), RPCError.decoding("x"))
        XCTAssertEqual(RPCError.transport(.timedOut), RPCError.transport(.timedOut))
        XCTAssertEqual(
            RPCError.http(status: 500, retryAfter: nil),
            RPCError.http(status: 500, retryAfter: nil)
        )
        XCTAssertEqual(
            RPCError.http(status: 429, retryAfter: .seconds(2)),
            RPCError.http(status: 429, retryAfter: .seconds(2))
        )
        let inner = JSONRPCError(code: -1, message: "boom", data: nil)
        XCTAssertEqual(RPCError.rpc(inner), RPCError.rpc(inner))
    }

    func test_equatable_differentCasesNotEqual() {
        XCTAssertNotEqual(RPCError.canceled, RPCError.decoding("x"))
        XCTAssertNotEqual(RPCError.decoding("x"), RPCError.decoding("y"))
        XCTAssertNotEqual(RPCError.transport(.timedOut), RPCError.transport(.cannotFindHost))
        XCTAssertNotEqual(
            RPCError.http(status: 500, retryAfter: nil),
            RPCError.http(status: 502, retryAfter: nil)
        )
    }

    func test_http_withAndWithoutRetryAfter() {
        let withRetry = RPCError.http(status: 429, retryAfter: .seconds(2))
        let withoutRetry = RPCError.http(status: 429, retryAfter: nil)
        XCTAssertNotEqual(withRetry, withoutRetry)

        let withRetryCopy = RPCError.http(status: 429, retryAfter: .seconds(2))
        XCTAssertEqual(withRetry, withRetryCopy)
    }

    func test_decoding_messagesEqualityIsStringSensitive() {
        XCTAssertEqual(RPCError.decoding("msg"), RPCError.decoding("msg"))
        XCTAssertNotEqual(RPCError.decoding("msg"), RPCError.decoding("MSG"))
    }
}
