import Foundation
import SolanaRPC
import XCTest
@testable import WalletOverviewDomain

final class PendingRetentionClassifierTests: XCTestCase {
    func test_transportError_retainsPending() {
        XCTAssertTrue(DefaultSendAssetsService.shouldRetainPending(after: .transport(.networkConnectionLost)))
        XCTAssertTrue(DefaultSendAssetsService.shouldRetainPending(after: .transport(.timedOut)))
        XCTAssertTrue(DefaultSendAssetsService.shouldRetainPending(after: .transport(.cannotConnectToHost)))
        XCTAssertTrue(DefaultSendAssetsService.shouldRetainPending(after: .transport(.dnsLookupFailed)))
        XCTAssertTrue(DefaultSendAssetsService.shouldRetainPending(after: .transport(.notConnectedToInternet)))
    }

    func test_decodingError_retainsPending() {
        XCTAssertTrue(DefaultSendAssetsService.shouldRetainPending(after: .decoding("partial body")))
    }

    func test_5xxError_retainsPending() {
        XCTAssertTrue(DefaultSendAssetsService.shouldRetainPending(after: .http(status: 500, retryAfter: nil)))
        XCTAssertTrue(DefaultSendAssetsService.shouldRetainPending(after: .http(status: 502, retryAfter: nil)))
        XCTAssertTrue(DefaultSendAssetsService.shouldRetainPending(after: .http(status: 503, retryAfter: nil)))
    }

    func test_jsonRpcRejection_dropsPending() {
        let rpc = JSONRPCError(code: -32_002, message: "Transaction simulation failed", data: nil)
        XCTAssertFalse(DefaultSendAssetsService.shouldRetainPending(after: .rpc(rpc)))
    }

    func test_4xxAuthError_dropsPending() {
        XCTAssertFalse(DefaultSendAssetsService.shouldRetainPending(after: .http(status: 401, retryAfter: nil)))
        XCTAssertFalse(DefaultSendAssetsService.shouldRetainPending(after: .http(status: 403, retryAfter: nil)))
        XCTAssertFalse(DefaultSendAssetsService.shouldRetainPending(after: .http(status: 429, retryAfter: nil)))
    }

    func test_canceled_dropsPending() {
        XCTAssertFalse(DefaultSendAssetsService.shouldRetainPending(after: .canceled))
    }
}
