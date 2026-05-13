import Formatters
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
        try SendViewModel(
            intent: self.makeIntent(asset: asset),
            cluster: .devnet,
            service: AlwaysFailService(),
            onDismiss: {})
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
        vm.amountText = "1.1234567" // 7 fraction digits, USDC allows 6
        await vm.requestQuote()
        XCTAssertNotNil(vm.validationError)
        XCTAssertTrue(vm.validationError?.contains("decimal") ?? false)
    }

    func testExactDecimalsForSolAccepted() async throws {
        // SOL has 9 decimals; this should parse cleanly. The downstream
        // service then rejects (no RPC enqueued), but the parse should pass.
        let vm = try makeViewModel(asset: .sol)
        vm.recipientText = "5sCJg3eAUaW8MgJrAJzQfYDgvT2gQg65Q5UEEa8sb1Le"
        vm.amountText = "0.123456789" // 9 decimals = SOL precision
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
        store: RecentRecipientsStore? = nil) throws -> SendViewModel
    {
        try SendViewModel(
            intent: self.makeIntent(asset: asset),
            cluster: .devnet,
            service: service,
            onDismiss: {},
            recentRecipientsStore: store)
    }

    func test_toggleFiatMode_flipsBetweenTokenAndFiat() throws {
        let vm = try makeViewModel(asset: .sol, service: MockSendAssetsService())
        vm.assetPriceUSD = Decimal(string: "100")
        XCTAssertEqual(vm.fiatMode, .token)
        vm.toggleFiatMode()
        XCTAssertEqual(vm.fiatMode, .fiat)
        vm.toggleFiatMode()
        XCTAssertEqual(vm.fiatMode, .token)
    }

    func test_toggleFiatMode_isNoOpWhenPriceUSDNil() throws {
        let vm = try makeViewModel(asset: .sol, service: MockSendAssetsService())
        vm.assetPriceUSD = nil
        XCTAssertEqual(vm.fiatMode, .token)
        vm.toggleFiatMode()
        XCTAssertEqual(vm.fiatMode, .token)
    }

    func test_selectChip_50_withBootstrap_producesFlooredHalf() throws {
        let vm = try makeViewModel(asset: .sol, service: MockSendAssetsService())
        vm.assetBalanceBaseUnits = 1_000_000_000
        vm.feeReserveLamports = Lamports(rawValue: 5200)
        vm.rentReserveLamports = Lamports(rawValue: 890_880)
        vm.selectChip(0.5)

        let calc = SendAmountCalculator()
        let input = SendAmountInput(
            balanceBaseUnits: 1_000_000_000,
            decimals: 9,
            priceUSD: nil,
            feeReserveLamports: Lamports(rawValue: 5200),
            rentReserveLamports: Lamports(rawValue: 890_880),
            isNativeSOL: true)
        let expected = calc.compute(.percentage(0.5), input: input).inputTokenText
        XCTAssertEqual(vm.amountText, expected)
    }

    func test_selectChip_setsParserSafeDotDecimalText() throws {
        let usdc = try Mint(base58: "EPjFWdd5AufqSSqeM2qN1xzybapC8G4wEGGkZwyTDt1v")
        let vm = try makeViewModel(
            asset: .splToken(mint: usdc, decimals: 6, symbol: "USDC", name: nil),
            service: MockSendAssetsService())
        vm.assetBalanceBaseUnits = 2_469_135_780_000
        vm.assetPriceUSD = Decimal(string: "1")
        vm.toggleFiatMode()

        vm.selectChip(0.5)

        XCTAssertEqual(vm.fiatMode, .token)
        XCTAssertEqual(vm.amountText, "1234567.89")
        XCTAssertFalse(vm.amountText.contains(","))
    }

    func test_selectChip_max_withInsufficientSOL_produces0() throws {
        let vm = try makeViewModel(asset: .sol, service: MockSendAssetsService())
        vm.assetBalanceBaseUnits = 100
        vm.feeReserveLamports = Lamports(rawValue: 5200)
        vm.rentReserveLamports = Lamports(rawValue: 890_880)
        vm.selectChip(1.0)
        XCTAssertEqual(vm.amountText, "0")
    }

    func test_typingDoesNotTriggerNetworkQuote() async throws {
        // Typing into the recipient/amount fields, tapping chips, and pasting
        // Solana Pay URIs must never reach the SendAssetsService.quote(_) RPC.
        // The user must explicitly tap Review to opt into the network round
        // trip.
        let counter = CountingSendService()
        let vm = try makeViewModel(asset: .sol, service: counter)
        vm.assetBalanceBaseUnits = 1_000_000_000
        vm.consumeRecipientText("5sCJg3eAUaW8MgJrAJzQfYDgvT2gQg65Q5UEEa8sb1Le")
        vm.amountText = "0.1"
        vm.consumeAmountChange()
        vm.selectChip(0.25)
        try? await Task.sleep(for: .milliseconds(500))
        let count = await counter.quoteCallCount
        XCTAssertEqual(count, 0)
    }

    func test_consumeRecipientText_solanaPayURI_populatesAddressAndAmount() throws {
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

    func test_validateRecipientLocally_emptyText() throws {
        let vm = try makeViewModel(asset: .sol, service: MockSendAssetsService())
        vm.consumeRecipientText("")
        XCTAssertFalse(vm.canReview)
    }

    func test_validateRecipientLocally_invalidBase58() throws {
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

    func test_validateRecipientLocally_sendingToSelf() throws {
        let vm = try makeViewModel(asset: .sol, service: MockSendAssetsService())
        vm.consumeRecipientText(vm.intent.from.base58)
        XCTAssertEqual(vm.inputValidation, .sendingToSelf)
        XCTAssertFalse(vm.canReview)
    }

    func test_priorityTier_change_onInputState_doesNotTriggerQuote() async throws {
        // Priority tier change while on the input screen must not run a
        // network quote. The user hasn't tapped Review yet.
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
        XCTAssertEqual(count, 0)
        defaults.removeObject(forKey: "send.priorityTier")
    }

    func test_priorityTier_change_onReadyToConfirm_triggersReQuote() async throws {
        // Once on Review, changing the priority tier rebuilds the quote so
        // the user sees the fee for the tier they just picked.
        let defaults = UserDefaults.standard
        defaults.removeObject(forKey: "send.priorityTier")
        let counter = CountingSendServiceWithQuote()
        let vm = try makeViewModel(asset: .sol, service: counter)
        vm.recipientText = "5sCJg3eAUaW8MgJrAJzQfYDgvT2gQg65Q5UEEa8sb1Le"
        vm.amountText = "0.1"
        vm.assetBalanceBaseUnits = 1_000_000_000

        await vm.requestQuote()
        guard case .readyToConfirm = vm.state else {
            XCTFail("Expected readyToConfirm, got \(vm.state)")
            return
        }
        let baseline = await counter.quoteCallCount
        XCTAssertEqual(baseline, 1)

        vm.selectPriorityTier(.turbo)
        try? await Task.sleep(for: .milliseconds(150))
        let count = await counter.quoteCallCount
        XCTAssertEqual(count, 2)
        let lastTier = await counter.lastTier
        XCTAssertEqual(lastTier, .turbo)
        // State stays on readyToConfirm so the user never leaves Review.
        guard case .readyToConfirm = vm.state else {
            XCTFail("Expected readyToConfirm after re-quote, got \(vm.state)")
            return
        }
        defaults.removeObject(forKey: "send.priorityTier")
    }

    func test_preloadConfirming_setsStateToConfirming() throws {
        let vm = try makeViewModel(asset: .sol, service: MockSendAssetsService())
        let bytes = Data(repeating: 0xAB, count: 64)
        let signature = try Signature(bytes: bytes)
        vm.preloadConfirming(signature: signature)
        XCTAssertEqual(vm.state, .confirming(signature))
    }

    func test_consumeSolanaPayURI_withDifferentSplToken_switchesEffectiveAsset() throws {
        let usdc = try Mint(base58: "EPjFWdd5AufqSSqeM2qN1xzybapC8G4wEGGkZwyTDt1v")
        let other = try Mint(base58: "So11111111111111111111111111111111111111112")
        let from = try WalletAddress(base58: "5sCJg3eAUaW8MgJrAJzQfYDgvT2gQg65Q5UEEa8sb1Le")
        let intent = SendIntent(
            walletId: UUID(),
            from: from,
            asset: .splToken(mint: usdc, decimals: 6, symbol: "USDC", name: "USD Coin"))
        let lookup: @MainActor (Mint) -> (decimals: UInt8, symbol: String, name: String)? = { mint in
            if mint == other { return (decimals: 9, symbol: "WSOL", name: "Wrapped SOL") }
            return nil
        }
        let vm = SendViewModel(
            intent: intent,
            cluster: .devnet,
            service: MockSendAssetsService(),
            onDismiss: {},
            recentRecipientsStore: nil,
            splTokenLookup: lookup)

        let recipient = "5sCJg3eAUaW8MgJrAJzQfYDgvT2gQg65Q5UEEa8sb1Le"
        vm.consumeRecipientText("solana:\(recipient)?spl-token=\(other.base58)")

        guard case let .splToken(mint, decimals, symbol, name) = vm.effectiveAsset else {
            return XCTFail("Expected effectiveAsset to switch to SPL token, got \(vm.effectiveAsset)")
        }
        XCTAssertEqual(mint, other)
        XCTAssertEqual(decimals, 9)
        XCTAssertEqual(symbol, "WSOL")
        XCTAssertEqual(name, "Wrapped SOL")
        XCTAssertEqual(vm.assetSymbol, "WSOL")
        XCTAssertEqual(vm.assetDecimals, 9)
    }

    func test_consumeSolanaPayURI_carriesMemoAndReferencesIntoRequest() throws {
        let vm = try makeViewModel(asset: .sol)
        vm.assetBalanceBaseUnits = 2_000_000_000
        let recipient = "5sCJg3eAUaW8MgJrAJzQfYDgvT2gQg65Q5UEEa8sb1Le"
        let reference = "So11111111111111111111111111111111111111112"

        vm.consumeRecipientText("solana:\(recipient)?amount=0.5&reference=\(reference)&label=Shop&message=Order&memo=abc123")
        let request = try vm.parseRequest()

        XCTAssertEqual(request.recipient.base58, recipient)
        XCTAssertEqual(request.solanaPay?.label, "Shop")
        XCTAssertEqual(request.solanaPay?.message, "Order")
        XCTAssertEqual(request.solanaPay?.memo, "abc123")
        XCTAssertEqual(request.solanaPay?.references.map(\.base58), [reference])
    }

    func test_consumeSolanaPayURI_withUnknownSplTokenBlocksReview() throws {
        let usdc = try Mint(base58: "EPjFWdd5AufqSSqeM2qN1xzybapC8G4wEGGkZwyTDt1v")
        let unknown = try Mint(base58: "So11111111111111111111111111111111111111112")
        let from = try WalletAddress(base58: "5sCJg3eAUaW8MgJrAJzQfYDgvT2gQg65Q5UEEa8sb1Le")
        let intent = SendIntent(
            walletId: UUID(),
            from: from,
            asset: .splToken(mint: usdc, decimals: 6, symbol: "USDC", name: "USD Coin"))
        let vm = SendViewModel(
            intent: intent,
            cluster: .devnet,
            service: MockSendAssetsService(),
            onDismiss: {},
            recentRecipientsStore: nil,
            splTokenLookup: { _ in nil })

        vm.consumeRecipientText("solana:\(from.base58)?amount=1&spl-token=\(unknown.base58)")

        XCTAssertFalse(vm.canReview)
        XCTAssertEqual(vm.inputValidation, .quoteError("This payment requests a token that is not in this wallet."))
        XCTAssertThrowsError(try vm.parseRequest())
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
            recentRecipientsStore: store)
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

    func resync(walletId _: UUID) async -> [PendingSendResolution] {
        []
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

    func resync(walletId _: UUID) async -> [PendingSendResolution] {
        []
    }
}

/// Returns a synthesized `SendQuote` so the view model can reach
/// `.readyToConfirm` and exercise the re-quote path.
private actor CountingSendServiceWithQuote: SendAssetsService {
    private(set) var quoteCallCount: Int = 0
    private(set) var lastTier: PriorityTier?

    func quote(_ request: SendRequest, tier: PriorityTier) async throws -> SendQuote {
        self.quoteCallCount += 1
        self.lastTier = tier
        let recipientReceives: SendAsset = switch request.asset {
        case let .sol(amount): .sol(amount: amount)
        case let .splToken(mint, amount, decimals):
            .splToken(mint: mint, amount: amount, decimals: decimals)
        }
        let details = TransactionReviewDetails(
            feePayer: request.from,
            cluster: .devnet,
            recipient: request.recipient,
            tokenMint: nil,
            tokenProgram: nil,
            instructions: [],
            computeUnitLimit: 5000,
            priorityFeeMicroLamports: 0,
            priorityFeeCapMicroLamports: 250_000,
            priorityFeeWasCapped: false,
            priorityFeeLamports: Lamports(rawValue: 0),
            baseFeeLamports: Lamports(rawValue: 5000),
            lastValidBlockHeight: 0,
            simulationStatus: "Simulation passed",
            sanitizedLogs: [],
            solanaPay: request.solanaPay)
        return SendQuote(
            request: request,
            networkFeeLamports: Lamports(rawValue: 5000),
            priorityFeeMicroLamports: 0,
            computeUnitLimit: 5000,
            recipientAtaWillBeCreated: false,
            rentForRecipientAta: Lamports(rawValue: 0),
            token2022Notice: nil,
            recipientReceives: recipientReceives,
            cluster: .devnet,
            simulationLogs: [],
            priorityTier: tier,
            reviewDetails: details,
            shapeDigest: QuoteShapeDigest(
                recipient: request.recipient,
                asset: request.asset,
                solanaPayMemo: request.solanaPay?.memo,
                solanaPayReferences: request.solanaPay?.references ?? [],
                tokenProgram: nil,
                recipientAtaWillBeCreated: false,
                rentForRecipientAta: Lamports(rawValue: 0),
                recipientReceives: recipientReceives,
                instructions: []))
    }

    func send(quote _: SendQuote) async throws -> SendOutcome {
        throw SendError.canceled
    }

    func resync(walletId _: UUID) async -> [PendingSendResolution] {
        []
    }
}
