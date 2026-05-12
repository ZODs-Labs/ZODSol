import Foundation
import XCTest
@testable import SolanaRPC

final class JSONRPCResponseTests: XCTestCase {
    private let decoder = JSONDecoder()

    func test_decode_successBodyHasResultAndNoError() throws {
        let body = #"{"jsonrpc":"2.0","id":"abc","result":42}"#.data(using: .utf8)!
        let response = try decoder.decode(JSONRPCResponse<Int>.self, from: body)
        XCTAssertEqual(response.jsonrpc, "2.0")
        XCTAssertEqual(response.id, "abc")
        XCTAssertEqual(response.result, 42)
        XCTAssertNil(response.error)
    }

    func test_decode_errorBodyHasErrorAndNoResult() throws {
        let body = #"""
        {"jsonrpc":"2.0","id":"abc","error":{"code":-32600,"message":"Invalid Request"}}
        """#.data(using: .utf8)!
        let response = try decoder.decode(JSONRPCResponse<Int>.self, from: body)
        XCTAssertNil(response.result)
        let error = try XCTUnwrap(response.error)
        XCTAssertEqual(error.code, -32600)
        XCTAssertEqual(error.message, "Invalid Request")
        XCTAssertNil(error.data)
    }

    func test_decode_errorBodyWithDataPayload() throws {
        let body = #"""
        {"jsonrpc":"2.0","id":"abc","error":{"code":-32000,"message":"server","data":"rate-limited"}}
        """#.data(using: .utf8)!
        let response = try decoder.decode(JSONRPCResponse<Int>.self, from: body)
        let error = try XCTUnwrap(response.error)
        XCTAssertEqual(error.data, .string("rate-limited"))
    }

    func test_unwrap_returnsResultOnSuccess() throws {
        let body = #"{"jsonrpc":"2.0","id":"abc","result":7}"#.data(using: .utf8)!
        let response = try decoder.decode(JSONRPCResponse<Int>.self, from: body)
        XCTAssertEqual(try response.unwrap(), 7)
    }

    func test_unwrap_throwsRPCErrorRPC_OnErrorBody() throws {
        let body = #"{"jsonrpc":"2.0","id":"abc","error":{"code":-1,"message":"boom"}}"#.data(using: .utf8)!
        let response = try decoder.decode(JSONRPCResponse<Int>.self, from: body)

        XCTAssertThrowsError(try response.unwrap()) { error in
            guard let rpc = error as? RPCError else {
                XCTFail("expected RPCError, got \(error)")
                return
            }
            switch rpc {
            case let .rpc(body):
                XCTAssertEqual(body.code, -1)
                XCTAssertEqual(body.message, "boom")
            default:
                XCTFail("expected .rpc, got \(rpc)")
            }
        }
    }

    func test_unwrap_throwsRPCErrorDecoding_OnMissingResultAndError() throws {
        let body = #"{"jsonrpc":"2.0","id":"abc"}"#.data(using: .utf8)!
        let response = try decoder.decode(JSONRPCResponse<Int>.self, from: body)
        XCTAssertThrowsError(try response.unwrap()) { error in
            guard let rpc = error as? RPCError else {
                XCTFail("expected RPCError, got \(error)")
                return
            }
            switch rpc {
            case let .decoding(message):
                XCTAssertTrue(message.contains("missing result"))
            default:
                XCTFail("expected .decoding, got \(rpc)")
            }
        }
    }
}
