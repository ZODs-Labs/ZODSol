import Foundation
import XCTest
@testable import SolanaRPC

final class TransactionConfirmationTests: XCTestCase {
    func test_returnsConfirmed_whenSignatureStatusReachesCommitment() async throws {
        let transport = MockTransport(handlers: [
            "getSignatureStatuses": .json(Self.signatureStatusJSON(status: "confirmed")),
            "getEpochInfo": .json(Self.epochInfoJSON(slot: 100, blockHeight: 100)),
        ])
        let outcome = try await TransactionConfirmation.waitForRecentTransaction(
            signatureBase58: "sig",
            lastValidBlockHeight: 1000,
            transport: transport,
            config: .init(commitment: .confirmed, pollInterval: .milliseconds(50), timeout: .seconds(5)))
        XCTAssertEqual(outcome.status, .confirmed(slot: 42))
    }

    func test_returnsFailed_whenSignatureStatusHasError() async throws {
        let transport = MockTransport(handlers: [
            "getSignatureStatuses": .json(Self.signatureStatusJSON(
                status: "processed",
                error: #""err":{"InstructionError":[0,"Custom"]}"#)),
            "getEpochInfo": .json(Self.epochInfoJSON(slot: 100, blockHeight: 100)),
        ])
        let outcome = try await TransactionConfirmation.waitForRecentTransaction(
            signatureBase58: "sig",
            lastValidBlockHeight: 1000,
            transport: transport,
            config: .init(commitment: .confirmed, pollInterval: .milliseconds(50), timeout: .seconds(5)))
        if case let .failed(error) = outcome.status {
            XCTAssertTrue(error.contains("InstructionError"))
        } else {
            XCTFail("expected .failed, got \(outcome.status)")
        }
    }

    func test_returnsExpired_whenBlockHeightExceededFromFirstCall() async throws {
        let transport = MockTransport(handlers: [
            "getSignatureStatuses": .json(Self.nullSignatureStatusJSON()),
            "getEpochInfo": .json(Self.epochInfoJSON(slot: 1500, blockHeight: 1500)),
        ])
        let outcome = try await TransactionConfirmation.waitForRecentTransaction(
            signatureBase58: "sig",
            lastValidBlockHeight: 1000,
            transport: transport,
            config: .init(commitment: .confirmed, pollInterval: .milliseconds(50), timeout: .seconds(5)))
        XCTAssertEqual(outcome.status, .expired)
    }

    func test_timeoutAloneDoesNotExpireBeforeBlockHeightWindow() async throws {
        let counter = MutableCounter()
        let transport = MockTransport(dynamicHandler: { method in
            switch method {
            case "getSignatureStatuses":
                return .json(Self.nullSignatureStatusJSON())
            case "getEpochInfo":
                let nth = counter.incrementAndGet()
                return .json(Self.epochInfoJSON(
                    slot: nth == 1 ? 100 : 1010,
                    blockHeight: nth == 1 ? 100 : 1010))
            default:
                return .error(RPCError.transport(.unknown))
            }
        })
        let outcome = try await TransactionConfirmation.waitForRecentTransaction(
            signatureBase58: "sig",
            lastValidBlockHeight: 1000,
            transport: transport,
            config: .init(
                commitment: .confirmed,
                pollInterval: .milliseconds(10),
                timeout: .milliseconds(1),
                blockHeightRefreshTicks: 1))
        XCTAssertEqual(outcome.status, .expired)
        XCTAssertGreaterThanOrEqual(counter.value, 2)
    }

    func test_signatureStatusBelowRequestedCommitment_keepsPolling() async throws {
        let counter = MutableCounter()
        let transport = MockTransport(dynamicHandler: { method in
            switch method {
            case "getSignatureStatuses":
                let nth = counter.incrementAndGet()
                let level = nth == 1 ? "processed" : "confirmed"
                return .json(Self.signatureStatusJSON(status: level))
            case "getEpochInfo":
                return .json(Self.epochInfoJSON(slot: 100, blockHeight: 100))
            default:
                return .error(RPCError.transport(.unknown))
            }
        })
        let outcome = try await TransactionConfirmation.waitForRecentTransaction(
            signatureBase58: "sig",
            lastValidBlockHeight: 1_000_000,
            transport: transport,
            config: .init(commitment: .confirmed, pollInterval: .milliseconds(20), timeout: .seconds(5)))
        XCTAssertEqual(outcome.status, .confirmed(slot: 42))
    }

    private static func signatureStatusJSON(status: String, error: String = #""err":null"#) -> String {
        """
        {"jsonrpc":"2.0","id":"x","result":{"context":{"slot":42},\
        "value":[{"slot":42,"confirmations":null,\(error),"confirmationStatus":"\(status)"}]}}
        """
    }

    private static func nullSignatureStatusJSON() -> String {
        #"{"jsonrpc":"2.0","id":"x","result":{"context":{"slot":42},"value":[null]}}"#
    }

    private static func epochInfoJSON(slot: UInt64, blockHeight: UInt64) -> String {
        """
        {"jsonrpc":"2.0","id":"x","result":{"epoch":1,"slotIndex":0,\
        "slotsInEpoch":432000,"absoluteSlot":\(slot),"blockHeight":\(blockHeight)}}
        """
    }
}

final class MutableCounter: @unchecked Sendable {
    private let lock = NSLock()
    private var counter = 0
    var value: Int {
        self.lock.lock()
        defer { lock.unlock() }
        return self.counter
    }

    func incrementAndGet() -> Int {
        self.lock.lock()
        defer { lock.unlock() }
        self.counter += 1
        return self.counter
    }
}

actor MockTransport: RPCTransport {
    enum HandlerResult {
        case json(String)
        case error(RPCError)
    }

    private let staticHandlers: [String: HandlerResult]
    private let dynamicHandler: (@Sendable (String) -> HandlerResult)?

    init(
        handlers: [String: HandlerResult] = [:],
        dynamicHandler: (@Sendable (String) -> HandlerResult)? = nil)
    {
        self.staticHandlers = handlers
        self.dynamicHandler = dynamicHandler
    }

    func send<R: Decodable & Sendable>(
        _ request: JSONRPCRequest<some Encodable & Sendable>,
        responseType: R.Type) async throws -> R
    {
        let result = self.dynamicHandler?(request.method) ?? self.staticHandlers[request.method]
        guard let result else { throw RPCError.transport(.unknown) }
        switch result {
        case let .json(body):
            guard let data = body.data(using: .utf8) else {
                throw RPCError.decoding("invalid utf8")
            }
            return try JSONDecoder().decode(R.self, from: data)
        case let .error(error):
            throw error
        }
    }
}
