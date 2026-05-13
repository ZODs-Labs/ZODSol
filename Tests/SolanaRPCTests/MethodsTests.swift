import XCTest
@testable import SolanaRPC

/// Tests for the typed RPC bindings: each method's params must serialize to
/// the canonical JSON-RPC shape Solana validators expect, and each result
/// must decode from a realistic RPC response payload.
final class MethodsTests: XCTestCase {
    // MARK: - LatestBlockhash

    func testLatestBlockhashParamsEncoding() throws {
        let request = LatestBlockhashRPC.request(commitment: "finalized")
        let json = try jsonString(of: request.params)
        XCTAssertEqual(json, #"[{"commitment":"finalized"}]"#)
    }

    func testLatestBlockhashResultDecoding() throws {
        let payload = """
        {
          "jsonrpc": "2.0",
          "id": "x",
          "result": {
            "context": {"slot": 100},
            "value": {"blockhash": "EkSnNWid2cvwEVnVx9aBqawnmiCNiDgp3gUdkDPTKN1N",
                      "lastValidBlockHeight": 12345}
          }
        }
        """.data(using: .utf8)!
        let resp = try JSONDecoder().decode(JSONRPCResponse<LatestBlockhashRPC.Result>.self, from: payload)
        let result = try resp.unwrap()
        XCTAssertEqual(result.value.blockhash, "EkSnNWid2cvwEVnVx9aBqawnmiCNiDgp3gUdkDPTKN1N")
        XCTAssertEqual(result.value.lastValidBlockHeight, 12345)
    }

    // MARK: - SendTransaction

    func testSendTransactionParamsEncoding_defaultsMatchBestPractice() throws {
        let request = SendTransactionRPC.request(base64Transaction: "AQID")
        let json = try jsonString(of: request.params)
        XCTAssertTrue(json.hasPrefix(#"["AQID",{"#))
        XCTAssertTrue(json.contains(#""encoding":"base64""#))
        XCTAssertTrue(json.contains(#""skipPreflight":false"#))
        XCTAssertTrue(json.contains(#""preflightCommitment":"confirmed""#))
        // maxRetries is omitted (nil) so the RPC node uses its default rebroadcast budget.
        XCTAssertFalse(json.contains(#""maxRetries""#))
        XCTAssertFalse(json.contains(#""maxSupportedTransactionVersion""#))
    }

    func testSendTransactionParamsEncoding_explicitMaxRetriesIsEmitted() throws {
        let request = SendTransactionRPC.request(base64Transaction: "AQID", maxRetries: 0, minContextSlot: 42)
        let json = try jsonString(of: request.params)
        XCTAssertTrue(json.contains(#""maxRetries":0"#))
        XCTAssertTrue(json.contains(#""minContextSlot":42"#))
    }

    func testSendTransactionResultDecoding() throws {
        let payload = """
        {"jsonrpc":"2.0","id":"x","result":"5w3X..."}
        """.data(using: .utf8)!
        let resp = try JSONDecoder().decode(JSONRPCResponse<String>.self, from: payload)
        XCTAssertEqual(try resp.unwrap(), "5w3X...")
    }

    // MARK: - SimulateTransaction

    func testSimulateTransactionParamsEncoding() throws {
        let request = SimulateTransactionRPC.request(base64Transaction: "ZZZ")
        let json = try jsonString(of: request.params)
        XCTAssertTrue(json.hasPrefix(#"["ZZZ",{"#))
        XCTAssertTrue(json.contains(#""encoding":"base64""#))
        XCTAssertTrue(json.contains(#""sigVerify":false"#))
        XCTAssertTrue(json.contains(#""replaceRecentBlockhash":true"#))
        XCTAssertTrue(json.contains(#""commitment":"processed""#))
    }

    func testSimulateTransactionParamsEncoding_minContextSlot() throws {
        let request = SimulateTransactionRPC.request(base64Transaction: "ZZZ", minContextSlot: 42)
        let json = try jsonString(of: request.params)
        XCTAssertTrue(json.contains(#""minContextSlot":42"#))
    }

    func testSimulateTransactionResultDecoding_success() throws {
        let payload = """
        {
          "jsonrpc": "2.0",
          "id": "x",
          "result": {
            "context": {"slot": 1},
            "value": {
              "err": null,
              "logs": ["Program log: hello"],
              "unitsConsumed": 150
            }
          }
        }
        """.data(using: .utf8)!
        let resp = try JSONDecoder().decode(JSONRPCResponse<SimulateTransactionRPC.Result>.self, from: payload)
        let result = try resp.unwrap()
        XCTAssertEqual(result.value.unitsConsumed, 150)
        XCTAssertEqual(result.value.logs, ["Program log: hello"])
        XCTAssertNil(result.value.err)
    }

    func testSimulateTransactionResultDecoding_errorVariant() throws {
        let payload = """
        {
          "jsonrpc": "2.0",
          "id": "x",
          "result": {
            "context": {"slot": 1},
            "value": {
              "err": {"InstructionError": [0, {"Custom": 6000}]},
              "logs": ["Program err"],
              "unitsConsumed": null
            }
          }
        }
        """.data(using: .utf8)!
        let resp = try JSONDecoder().decode(JSONRPCResponse<SimulateTransactionRPC.Result>.self, from: payload)
        let result = try resp.unwrap()
        XCTAssertNotNil(result.value.err)
        XCTAssertNil(result.value.unitsConsumed)
    }

    // MARK: - SignatureStatuses

    func testSignatureStatusesParamsEncoding() throws {
        let request = SignatureStatusesRPC.request(signatures: ["a", "b"], searchTransactionHistory: true)
        let json = try jsonString(of: request.params)
        XCTAssertTrue(json.contains(#"["a","b"]"#))
        XCTAssertTrue(json.contains(#""searchTransactionHistory":true"#))
    }

    func testSignatureStatusesResultDecoding_mixed() throws {
        let payload = """
        {
          "jsonrpc": "2.0",
          "id": "x",
          "result": {
            "context": {"slot": 10},
            "value": [
              null,
              {"slot": 9, "confirmations": 3, "err": null, "confirmationStatus": "confirmed"}
            ]
          }
        }
        """.data(using: .utf8)!
        let resp = try JSONDecoder().decode(JSONRPCResponse<SignatureStatusesRPC.Result>.self, from: payload)
        let result = try resp.unwrap()
        XCTAssertEqual(result.value.count, 2)
        XCTAssertNil(result.value[0])
        XCTAssertEqual(result.value[1]?.slot, 9)
        XCTAssertEqual(result.value[1]?.confirmationStatus, "confirmed")
        XCTAssertNil(result.value[1]?.err)
    }

    // MARK: - EpochInfo

    func testEpochInfoParamsEncoding() throws {
        let request = EpochInfoRPC.request()
        let json = try jsonString(of: request.params)
        XCTAssertEqual(json, #"[{"commitment":"confirmed"}]"#)
    }

    func testEpochInfoResultDecoding() throws {
        let payload = """
        {
          "jsonrpc": "2.0",
          "id": "x",
          "result": {
            "absoluteSlot": 200,
            "blockHeight": 180,
            "epoch": 5,
            "slotIndex": 50,
            "slotsInEpoch": 432000,
            "transactionCount": 999
          }
        }
        """.data(using: .utf8)!
        let resp = try JSONDecoder().decode(JSONRPCResponse<EpochInfoRPC.Result>.self, from: payload)
        let result = try resp.unwrap()
        XCTAssertEqual(result.epoch, 5)
        XCTAssertEqual(result.blockHeight, 180)
        XCTAssertEqual(result.slotsInEpoch, 432_000)
    }

    // MARK: - AccountInfo

    func testAccountInfoParamsEncoding() throws {
        let request = AccountInfoRPC.request(address: "11111111111111111111111111111111", minContextSlot: 42)
        let json = try jsonString(of: request.params)
        XCTAssertTrue(json.hasPrefix(#"["11111111111111111111111111111111",{"#))
        XCTAssertTrue(json.contains(#""encoding":"base64""#))
        XCTAssertTrue(json.contains(#""commitment":"confirmed""#))
        XCTAssertTrue(json.contains(#""minContextSlot":42"#))
    }

    func testAccountInfoResultDecoding_present() throws {
        let payload = """
        {
          "jsonrpc": "2.0",
          "id": "x",
          "result": {
            "context": {"slot": 1},
            "value": {
              "lamports": 1000000,
              "owner": "TokenkegQfeZyiNwAJbNbGKPFXCWuBvf9Ss623VQ5DA",
              "executable": false,
              "rentEpoch": 18446744073709551615,
              "data": ["AAA=", "base64"]
            }
          }
        }
        """.data(using: .utf8)!
        let resp = try JSONDecoder().decode(JSONRPCResponse<AccountInfoRPC.Result>.self, from: payload)
        let result = try resp.unwrap()
        XCTAssertEqual(result.value?.lamports, 1_000_000)
        XCTAssertEqual(result.value?.owner, "TokenkegQfeZyiNwAJbNbGKPFXCWuBvf9Ss623VQ5DA")
        XCTAssertEqual(result.value?.base64Data, "AAA=")
        XCTAssertEqual(
            try result.value?.validatedBase64Bytes(
                expectedOwner: "TokenkegQfeZyiNwAJbNbGKPFXCWuBvf9Ss623VQ5DA",
                minimumLength: 1),
            Data([0, 0]))
    }

    func testAccountInfoResultDecoding_unsupportedEncodingFailsValidation() throws {
        let payload = """
        {
          "jsonrpc": "2.0",
          "id": "x",
          "result": {
            "context": {"slot": 1},
            "value": {
              "lamports": 1,
              "owner": "11111111111111111111111111111111",
              "executable": false,
              "rentEpoch": 0,
              "data": ["{}", "jsonParsed"]
            }
          }
        }
        """.data(using: .utf8)!
        let resp = try JSONDecoder().decode(JSONRPCResponse<AccountInfoRPC.Result>.self, from: payload)
        let result = try resp.unwrap()
        XCTAssertNil(result.value?.base64Data)
        XCTAssertThrowsError(try result.value?.validatedBase64Bytes())
    }

    func testAccountInfoResultDecoding_missing() throws {
        let payload = """
        {"jsonrpc":"2.0","id":"x","result":{"context":{"slot":1},"value":null}}
        """.data(using: .utf8)!
        let resp = try JSONDecoder().decode(JSONRPCResponse<AccountInfoRPC.Result>.self, from: payload)
        let result = try resp.unwrap()
        XCTAssertNil(result.value)
    }

    // MARK: - RecentPrioritizationFees

    func testRecentPrioritizationFeesParamsEncoding() throws {
        let request = RecentPrioritizationFeesRPC.request(accountAddresses: ["a", "b"])
        let json = try jsonString(of: request.params)
        XCTAssertEqual(json, #"[["a","b"]]"#)
    }

    func testRecentPrioritizationFeesResultDecoding() throws {
        let payload = """
        {
          "jsonrpc":"2.0","id":"x",
          "result":[
            {"slot": 100, "prioritizationFee": 5000},
            {"slot": 101, "prioritizationFee": 0}
          ]
        }
        """.data(using: .utf8)!
        let resp = try JSONDecoder().decode(JSONRPCResponse<RecentPrioritizationFeesRPC.Result>.self, from: payload)
        let result = try resp.unwrap()
        XCTAssertEqual(result.count, 2)
        XCTAssertEqual(result[0].slot, 100)
        XCTAssertEqual(result[0].prioritizationFee, 5000)
        XCTAssertEqual(result[1].prioritizationFee, 0)
    }

    // MARK: - Helpers

    private func jsonString(of value: some Encodable) throws -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        let data = try encoder.encode(value)
        return String(decoding: data, as: UTF8.self)
    }
}
