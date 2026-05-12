import Foundation
import SolanaKit
import WalletOverviewDomain
import XCTest
@testable import WalletOverviewUI

/// Input-validation tests for `SendViewModel`. Asserts the parser rejects
/// inputs the user can mistype (extra decimals, non-numeric, etc.) before
/// any RPC call.
@MainActor
final class SendViewModelTests: XCTestCase {

    private func makeIntent(asset: SendAssetKind) throws -> SendIntent {
        let from = try WalletAddress(base58: "EPjFWdd5AufqSSqeM2qN1xzybapC8G4wEGGkZwyTDt1v")
        return SendIntent(walletId: UUID(), from: from, asset: asset)
    }

    private func makeViewModel(asset: SendAssetKind) throws -> SendViewModel {
        SendViewModel(
            intent: try makeIntent(asset: asset),
            cluster: .devnet,
            service: AlwaysFailService(),
            onDismiss: {}
        )
    }

    // MARK: - Empty / whitespace

    func testEmptyRecipientShowsValidationError() async throws {
        let vm = try makeViewModel(asset: .sol)
        vm.recipientText = ""
        vm.amountText = "1.0"
        await vm.requestQuote()
        XCTAssertNotNil(vm.validationError)
        XCTAssertEqual(vm.state, .input)
    }

    func testEmptyAmountShowsValidationError() async throws {
        let vm = try makeViewModel(asset: .sol)
        vm.recipientText = "EPjFWdd5AufqSSqeM2qN1xzybapC8G4wEGGkZwyTDt1v"
        vm.amountText = "   "
        await vm.requestQuote()
        XCTAssertNotNil(vm.validationError)
        XCTAssertEqual(vm.state, .input)
    }

    func testInvalidRecipientBase58Reported() async throws {
        let vm = try makeViewModel(asset: .sol)
        vm.recipientText = "not-a-real-address"
        vm.amountText = "0.1"
        await vm.requestQuote()
        XCTAssertNotNil(vm.validationError)
    }

    // MARK: - Decimals precision

    func testTooManyDecimalsForSplTokenIsRejected() async throws {
        let usdc = try Mint(base58: "EPjFWdd5AufqSSqeM2qN1xzybapC8G4wEGGkZwyTDt1v")
        let vm = try makeViewModel(asset: .splToken(mint: usdc, decimals: 6, symbol: "USDC", name: nil))
        vm.recipientText = "So11111111111111111111111111111111111111112"
        vm.amountText = "1.1234567"  // 7 fraction digits, USDC allows 6
        await vm.requestQuote()
        XCTAssertNotNil(vm.validationError)
        XCTAssertTrue(vm.validationError?.contains("decimal") ?? false)
    }

    func testExactDecimalsForSolAccepted() async throws {
        // SOL has 9 decimals; this should parse cleanly. The downstream
        // service then rejects (no RPC enqueued), but the parse should pass.
        let vm = try makeViewModel(asset: .sol)
        vm.recipientText = "5sCJg3eAUaW8MgJrAJzQfYDgvT2gQg65Q5UEEa8sb1Le"
        vm.amountText = "0.123456789"  // 9 decimals = SOL precision
        await vm.requestQuote()
        // After parse, the state moves into .quoting and the AlwaysFailService
        // throws .canceled, which we map to .failed(.broadcastFailed) per
        // SendViewModel.requestQuote semantics. The point: NOT a parse error.
        XCTAssertNil(vm.validationError)
    }

    func testNonNumericAmountReported() async throws {
        let vm = try makeViewModel(asset: .sol)
        vm.recipientText = "5sCJg3eAUaW8MgJrAJzQfYDgvT2gQg65Q5UEEa8sb1Le"
        vm.amountText = "abc"
        await vm.requestQuote()
        XCTAssertNotNil(vm.validationError)
    }

    func testZeroAmountReported() async throws {
        let vm = try makeViewModel(asset: .sol)
        vm.recipientText = "5sCJg3eAUaW8MgJrAJzQfYDgvT2gQg65Q5UEEa8sb1Le"
        vm.amountText = "0"
        await vm.requestQuote()
        XCTAssertNotNil(vm.validationError)
        XCTAssertTrue(vm.validationError?.lowercased().contains("greater than zero") ?? false)
    }

    func testCommaThousandsSeparatorAccepted() async throws {
        // "1,000.5" should parse as 1000.5 SOL (1_000_500_000_000 lamports).
        let vm = try makeViewModel(asset: .sol)
        vm.recipientText = "5sCJg3eAUaW8MgJrAJzQfYDgvT2gQg65Q5UEEa8sb1Le"
        vm.amountText = "1,000.5"
        await vm.requestQuote()
        XCTAssertNil(vm.validationError)
    }
}

private actor AlwaysFailService: SendAssetsService {
    func quote(_: SendRequest, tier _: PriorityTier) async throws -> SendQuote {
        throw SendError.canceled
    }

    func send(quote _: SendQuote) async throws -> SendOutcome {
        throw SendError.canceled
    }

    func resync(walletId _: UUID) async -> [Signature: SendOutcome] {
        [:]
    }
}
