import Foundation
import XCTest
@testable import SolanaRPC

final class JSONRPCRequestTests: XCTestCase {
    private struct SampleParams: Encodable, Equatable {
        let owner: String
        let limit: Int
    }

    func test_encode_producesCanonicalJSONRPCEnvelope() throws {
        let request = JSONRPCRequest(
            method: "getAssetsByOwner",
            params: SampleParams(owner: "wallet", limit: 10),
            id: "fixed-id")

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        let data = try encoder.encode(request)
        let json = try XCTUnwrap(String(data: data, encoding: .utf8))

        // Sorted-keys produces a deterministic shape
        XCTAssertEqual(
            json,
            "{\"id\":\"fixed-id\",\"jsonrpc\":\"2.0\",\"method\":\"getAssetsByOwner\",\"params\":{\"limit\":10,\"owner\":\"wallet\"}}")

        let object = try XCTUnwrap(try JSONSerialization.jsonObject(with: data) as? [String: Any])
        XCTAssertEqual(object["jsonrpc"] as? String, "2.0")
        XCTAssertEqual(object["id"] as? String, "fixed-id")
        XCTAssertEqual(object["method"] as? String, "getAssetsByOwner")
        let params = try XCTUnwrap(object["params"] as? [String: Any])
        XCTAssertEqual(params["owner"] as? String, "wallet")
        XCTAssertEqual(params["limit"] as? Int, 10)
    }

    func test_init_customIDIsPreserved() {
        let request = JSONRPCRequest(method: "ping", params: [String](), id: "request-42")
        XCTAssertEqual(request.id, "request-42")
        XCTAssertEqual(request.jsonrpc, "2.0")
        XCTAssertEqual(request.method, "ping")
    }

    func test_init_defaultIDIsNonEmptyUUIDString() {
        let request = JSONRPCRequest(method: "ping", params: [String]())
        XCTAssertFalse(request.id.isEmpty)
        XCTAssertNotNil(UUID(uuidString: request.id), "default id should be a UUID string")
    }

    func test_init_defaultIDsAreUnique() {
        let a = JSONRPCRequest(method: "ping", params: [String]())
        let b = JSONRPCRequest(method: "ping", params: [String]())
        XCTAssertNotEqual(a.id, b.id)
    }
}
