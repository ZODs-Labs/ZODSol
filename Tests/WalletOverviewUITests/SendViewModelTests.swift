import Foundation
import Formatters
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

    // MARK: - Wave 3G additions

    private func makeViewModel(
        asset: SendAssetKind,
        service: any SendAssetsService,
        store: RecentRecipientsStore? = nil
    ) throws -> SendViewModel {
        SendViewModel(
            intent: try makeIntent(asset: asset),
            cluster: .devnet,
            service: service,
            onDismiss: {},
            recentRecipientsStore: store
        )
    }

    func test_toggleFiatMode_flipsBetweenTokenAndFiat() async throws {
        let vm = try makeViewModel(asset: .sol, service: MockSendAssetsService())
        vm.assetPriceUSD = Decimal(string: "100")
        XCTAssertEqual(vm.fiatMode, .token)
        vm.toggleFiatMode()
        XCTAssertEqual(vm.fiatMode, .fiat)
        vm.toggleFiatMode()
        XCTAssertEqual(vm.fiatMode, .token)
    }

    func test_toggleFiatMode_isNoOpWhenPriceUSDNil() async throws {
        let vm = try makeViewModel(asset: .sol, service: MockSendAssetsService())
        vm.assetPriceUSD = nil
        XCTAssertEqual(vm.fiatMode, .token)
        vm.toggleFiatMode()
        XCTAssertEqual(vm.fiatMode, .token)
    }

    func test_selectChip_50_withBootstrap_producesFlooredHalf() async throws {
        let vm = try makeViewModel(asset: .sol, service: MockSendAssetsService())
        vm.assetBalanceBaseUnits = 1_000_000_000
        vm.feeReserveLamports = Lamports(rawValue: 5_200)
        vm.rentReserveLamports = Lamports(rawValue: 890_880)
        vm.selectChip(0.5)

        let calc = SendAmountCalculator()
        let input = SendAmountInput(
            balanceBaseUnits: 1_000_000_000,
            decimals: 9,
            priceUSD: nil,
            feeReserveLamports: Lamports(rawValue: 5_200),
            rentReserveLamports: Lamports(rawValue: 890_880),
            isNativeSOL: true
        )
        let expected = calc.compute(.percentage(0.5), input: input).displayToken
        XCTAssertEqual(vm.amountText, expected)
    }

    func test_selectChip_max_withInsufficientSOL_produces0() async throws {
        let vm = try makeViewModel(asset: .sol, service: MockSendAssetsService())
        vm.assetBalanceBaseUnits = 100
        vm.feeReserveLamports = Lamports(rawValue: 5_200)
        vm.rentReserveLamports = Lamports(rawValue: 890_880)
        vm.selectChip(1.0)
        XCTAssertEqual(vm.amountText, "0")
    }

    func test_scheduleQuote_rapidTyping_firesOnlyOneQuote() async throws {
        let counter = CountingSendService()
        let vm = try makeViewModel(asset: .sol, service: counter)
        vm.recipientText = "5sCJg3eAUaW8MgJrAJzQfYDgvT2gQg65Q5UEEa8sb1Le"
        vm.amountText = "0.1"

        vm.scheduleQuote()
        try? await Task.sleep(for: .milliseconds(50))
        vm.scheduleQuote()
        try? await Task.sleep(for: .milliseconds(50))
        vm.scheduleQuote()
        try? await Task.sleep(for: .milliseconds(500))

        let count = await counter.quoteCallCount
        XCTAssertEqual(count, 1)
    }

    func test_consumeRecipientText_solanaPayURI_populatesAddressAndAmount() async throws {
        let vm = try makeViewModel(asset: .sol, service: MockSendAssetsService())
        let address = "5sCJg3eAUaW8MgJrAJzQfYDgvT2gQg65Q5UEEa8sb1Le"
        let uri = "solana:\(address)?amount=2.5&label=Cafe&message=Latte"
        vm.consumeRecipientText(uri)
        XCTAssertEqual(vm.recipientText, address)
        XCTAssertEqual(vm.amountText, "2.5")
        XCTAssertNotNil(vm.solanaPayPill)
        XCTAssertEqual(vm.solanaPayPill?.label, "Cafe")
        XCTAssertEqual(vm.solanaPayPill?.message, "Latte")
    }

    func test_validateRecipientLocally_emptyText() async throws {
        let vm = try makeViewModel(asset: .sol, service: MockSendAssetsService())
        vm.consumeRecipientText("")
        XCTAssertFalse(vm.canReview)
    }

    func test_validateRecipientLocally_invalidBase58() async throws {
        let vm = try makeViewModel(asset: .sol, service: MockSendAssetsService())
        vm.amountText = "1"
        vm.assetBalanceBaseUnits = 1_000_000_000
        vm.consumeRecipientText("not-a-real-address")
        if case let .quoteError(message) = vm.inputValidation {
            XCTAssertEqual(message, "Invalid address")
        } else {
            XCTFail("Expected .quoteError, got \(vm.inputValidation)")
        }
        XCTAssertFalse(vm.canReview)
    }

    func test_validateRecipientLocally_sendingToSelf() async throws {
        let vm = try makeViewModel(asset: .sol, service: MockSendAssetsService())
        vm.consumeRecipientText(vm.intent.from.base58)
        XCTAssertEqual(vm.inputValidation, .sendingToSelf)
        XCTAssertFalse(vm.canReview)
    }

    func test_priorityTier_change_persistsAndTriggersReQuote() async throws {
        let defaults = UserDefaults.standard
        defaults.removeObject(forKey: "send.priorityTier")
        let counter = CountingSendService()
        let vm = try makeViewModel(asset: .sol, service: counter)
        vm.recipientText = "5sCJg3eAUaW8MgJrAJzQfYDgvT2gQg65Q5UEEa8sb1Le"
        vm.amountText = "0.1"
        vm.assetBalanceBaseUnits = 1_000_000_000

        vm.selectPriorityTier(.turbo)
        XCTAssertEqual(vm.priorityTier, .turbo)
        XCTAssertEqual(defaults.string(forKey: "send.priorityTier"), "turbo")

        try? await Task.sleep(for: .milliseconds(150))
        let count = await counter.quoteCallCount
        XCTAssertGreaterThanOrEqual(count, 1)
        let lastTier = await counter.lastTier
        XCTAssertEqual(lastTier, .turbo)
        defaults.removeObject(forKey: "send.priorityTier")
    }

    func test_preloadConfirming_setsStateToConfirming() async throws {
        let vm = try makeViewModel(asset: .sol, service: MockSendAssetsService())
        let bytes = Data(repeating: 0xAB, count: 64)
        let signature = try Signature(bytes: bytes)
        vm.preloadConfirming(signature: signature)
        XCTAssertEqual(vm.state, .confirming(signature))
    }

    func test_loadRecents_populatesFromStore() async throws {
        let key = "send-viewmodel-tests-recents-\(UUID().uuidString)"
        let store = RecentRecipientsStore(defaults: .standard, key: key)
        defer { UserDefaults.standard.removeObject(forKey: key) }
        let walletId = UUID()
        let address = try WalletAddress(base58: "5sCJg3eAUaW8MgJrAJzQfYDgvT2gQg65Q5UEEa8sb1Le")
        await store.record(address, walletId: walletId)

        let from = try WalletAddress(base58: "EPjFWdd5AufqSSqeM2qN1xzybapC8G4wEGGkZwyTDt1v")
        let vm = SendViewModel(
            intent: SendIntent(walletId: walletId, from: from, asset: .sol),
            cluster: .devnet,
            service: MockSendAssetsService(),
            onDismiss: {},
            recentRecipientsStore: store
        )
        await vm.loadRecents()
        XCTAssertEqual(vm.recents.count, 1)
        XCTAssertEqual(vm.recents.first?.address.base58, address.base58)
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

/// Counting variant used by Wave 3G debounce + re-quote tests. The shared
/// `MockSendAssetsService` is owned by other waves and intentionally not
/// modified here; this local actor wraps the same protocol and adds the
/// counters this suite needs.
private actor CountingSendService: SendAssetsService {
    private(set) var quoteCallCount: Int = 0
    private(set) var lastTier: PriorityTier?

    func quote(_: SendRequest, tier: PriorityTier) async throws -> SendQuote {
        self.quoteCallCount += 1
        self.lastTier = tier
        throw SendError.canceled
    }

    func send(quote _: SendQuote) async throws -> SendOutcome {
        throw SendError.canceled
    }

    func resync(walletId _: UUID) async -> [Signature: SendOutcome] {
        [:]
    }
}
