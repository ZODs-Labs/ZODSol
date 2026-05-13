import Formatters
import Foundation
import Observation
import SolanaKit
import WalletOverviewDomain

/// Discriminator for the asset being sent. Carries display-only fields (symbol,
/// name) so the views never have to look them up from the overview.
public enum SendAssetKind: Sendable, Equatable {
    case sol
    case splToken(mint: Mint, decimals: UInt8, symbol: String?, name: String?)
}

/// User-supplied + context inputs the navigator hands to the send flow.
public struct SendIntent: Sendable, Equatable {
    public let walletId: UUID
    public let from: WalletAddress
    public let asset: SendAssetKind

    public init(walletId: UUID, from: WalletAddress, asset: SendAssetKind) {
        self.walletId = walletId
        self.from = from
        self.asset = asset
    }
}

/// Label and message lifted from a Solana Pay URI for display next to the
/// recipient field. Surfaced as a small pill so the user can confirm the
/// merchant intent before signing.
public struct SolanaPayPill: Sendable, Equatable {
    public let label: String?
    public let message: String?

    public init(label: String?, message: String?) {
        self.label = label
        self.message = message
    }
}

/// State machine driving the send screens.
///
/// Each transition is one-way except `readyToConfirm → input` and
/// `failed → input` (user backs out). Once `broadcasting` fires the
/// signature is already on the cluster; later states either resolve or keep
/// a pending signature for resync.
@MainActor @Observable
public final class SendViewModel {
    public enum State: Sendable, Equatable {
        case input
        case quoting
        case readyToConfirm(SendQuote)
        case signing
        case broadcasting(Signature)
        case confirming(Signature)
        case confirmed(Signature, slot: UInt64)
        case expired(Signature)
        case stillPending(Signature)
        case failed(SendError)
    }

    public private(set) var state: State = .input
    public var recipientText: String = ""
    public var amountText: String = ""
    public private(set) var validationError: String?

    public var fiatMode: FiatMode = .token
    public var priorityTier: PriorityTier = .fast {
        didSet {
            guard oldValue != self.priorityTier else { return }
            UserDefaults.standard.set(self.priorityTier.rawValue, forKey: Self.priorityTierDefaultsKey)
            self.handlePriorityTierChange()
        }
    }

    public var feeReserveLamports: Lamports = .init(rawValue: 5200)
    public var rentReserveLamports: Lamports = .init(rawValue: 890_880)
    public var ataRentReserveLamports: Lamports = .init(rawValue: 2_039_280)
    /// Fee details default to expanded so Mac users see the network fee, rent
    /// and total cost without an extra click. macOS expects transparency for
    /// money-moving actions.
    public var detailsExpanded: Bool = true
    public var inputValidation: InputValidation = .ok
    public var solanaPayPill: SolanaPayPill?
    public private(set) var solanaPayContext: SolanaPayTransferContext?
    public internal(set) var lastQuote: SendQuote?
    public internal(set) var recents: [RecentRecipient] = []

    public var assetBalanceBaseUnits: UInt64 = 0
    public var assetPriceUSD: Decimal?
    /// True while a re-quote is running from the Review screen (priority-tier
    /// change). The confirm view shows a non-blocking indicator and disables
    /// Send so the user never signs against a stale fee.
    public private(set) var isRequoting: Bool = false
    /// All ZODSol wallets, excluding the sender, surfaced inline as recipient
    /// suggestions when the user focuses the address field. Populated by the
    /// navigator from `WalletOverviewViewModel.wallets`.
    public var directoryWallets: [WalletIdentity] = []

    public let intent: SendIntent
    public let cluster: SolanaNetwork
    /// Asset actually being sent. Starts identical to `intent.asset`; mutates
    /// when the user pastes a Solana Pay URI whose `spl-token` parameter
    /// points at a different mint than the one the picker selected.
    public private(set) var effectiveAsset: SendAssetKind
    let service: any SendAssetsService
    let onDismiss: @MainActor () -> Void
    let recentRecipientsStore: RecentRecipientsStore?
    let splTokenLookup: (@MainActor (Mint) -> (decimals: UInt8, symbol: String, name: String)?)?
    var lastChipPercentage: Double?
    private var unsupportedSolanaPayMint: Mint?

    static let priorityTierDefaultsKey = "send.priorityTier"

    public init(
        intent: SendIntent,
        cluster: SolanaNetwork,
        service: any SendAssetsService,
        onDismiss: @MainActor @escaping () -> Void,
        recentRecipientsStore: RecentRecipientsStore? = nil,
        splTokenLookup: (@MainActor (Mint) -> (decimals: UInt8, symbol: String, name: String)?)? = nil)
    {
        self.intent = intent
        self.effectiveAsset = intent.asset
        self.cluster = cluster
        self.service = service
        self.onDismiss = onDismiss
        self.recentRecipientsStore = recentRecipientsStore
        self.splTokenLookup = splTokenLookup

        if let raw = UserDefaults.standard.string(forKey: Self.priorityTierDefaultsKey),
           let tier = PriorityTier(rawValue: raw)
        {
            self.priorityTier = tier
        }
    }
}

// MARK: - State transitions

extension SendViewModel {
    /// Build the quote. Driven by an explicit user action - the Review button
    /// on `SendInputView`, or a tier change on `SendConfirmView`. Never
    /// triggered by typing, pasting, or chip taps; the user must opt into the
    /// network round trip.
    public func requestQuote() async {
        switch self.state {
        case .input, .readyToConfirm, .failed:
            break
        default:
            return
        }
        self.validationError = nil

        let request: SendRequest
        do {
            request = try self.parseRequest()
        } catch let SendInputError.message(message) {
            self.validationError = message
            self.state = .input
            return
        } catch {
            self.validationError = "Could not parse this input."
            self.state = .input
            return
        }

        self.state = .quoting
        do {
            let quote = try await self.service.quote(request, tier: self.priorityTier)
            self.lastQuote = quote
            self.feeReserveLamports = quote.networkFeeLamports
            self.state = .readyToConfirm(quote)
        } catch let error as SendError {
            self.state = .failed(error)
        } catch is CancellationError {
            self.state = .input
        } catch {
            self.state = .failed(.broadcastFailed(reason: String(describing: error)))
        }
    }

    /// Re-quote only when the user is already on the Review screen (or the
    /// quote just failed). On the input screen no quote exists yet, so a
    /// tier change is a no-op until the user taps Review.
    private func handlePriorityTierChange() {
        switch self.state {
        case .readyToConfirm:
            Task { [weak self] in await self?.requote() }
        case .failed:
            Task { [weak self] in await self?.requestQuote() }
        default:
            break
        }
    }

    /// Re-build the quote without leaving the Review screen. Used when the
    /// user changes the priority tier on confirm - we keep `state` on
    /// `.readyToConfirm` and flip `isRequoting` so the view can show a thin
    /// progress indicator without unmounting the form.
    private func requote() async {
        guard case .readyToConfirm = self.state else { return }
        let request: SendRequest
        do {
            request = try self.parseRequest()
        } catch {
            // Inputs that built the original quote should still parse - if
            // they don't, fall back to the full input flow.
            self.state = .input
            return
        }
        self.isRequoting = true
        defer { self.isRequoting = false }
        do {
            let quote = try await self.service.quote(request, tier: self.priorityTier)
            self.lastQuote = quote
            self.feeReserveLamports = quote.networkFeeLamports
            self.state = .readyToConfirm(quote)
        } catch let error as SendError {
            self.state = .failed(error)
        } catch is CancellationError {
            return
        } catch {
            self.state = .failed(.broadcastFailed(reason: String(describing: error)))
        }
    }

    /// Sign + broadcast. Caller is the "Send" button on `SendConfirmView`.
    public func confirmSend() async {
        guard case let .readyToConfirm(quote) = self.state else { return }
        self.state = .signing
        do {
            let outcome = try await self.service.send(quote: quote)
            switch outcome {
            case let .confirmed(sig, slot):
                self.state = .confirmed(sig, slot: slot)
            case let .expired(sig):
                self.state = .expired(sig)
            case let .failed(sig, error):
                self.state = .failed(.simulationFailed(logs: [error], error: error))
                _ = sig
            case let .stillPending(sig):
                self.state = .stillPending(sig)
            }
        } catch let error as SendError {
            self.state = .failed(error)
        } catch is CancellationError {
            self.state = .input
        } catch {
            self.state = .failed(.broadcastFailed(reason: String(describing: error)))
        }
    }

    /// Step back from confirm or failure to the input screen so the user
    /// can edit and re-quote. Terminal states (`confirmed`, `expired`) use
    /// `dismiss()` instead.
    public func back() {
        switch self.state {
        case .readyToConfirm, .failed:
            self.state = .input
        default:
            break
        }
    }

    public func dismiss() {
        self.onDismiss()
    }

    /// Skip the input phase and jump straight to confirmation polling. Used
    /// when reopening the panel mid-broadcast and the signature was carried
    /// over via `PendingSendBanner`.
    public func preloadConfirming(signature: Signature) {
        self.state = .confirming(signature)
    }
}

// MARK: - Input editing

extension SendViewModel {
    public func toggleFiatMode() {
        guard self.assetPriceUSD != nil else { return }
        self.fiatMode = (self.fiatMode == .token) ? .fiat : .token
    }

    public func selectChip(_ percentage: Double) {
        let clamped = max(0.0, min(1.0, percentage))
        self.lastChipPercentage = clamped
        let calc = SendAmountCalculator()
        let input = self.amountInput()
        let result = calc.compute(.percentage(clamped), input: input)
        self.fiatMode = .token
        self.amountText = result.inputTokenText
        self.validateAllLocally()
    }

    public func selectPriorityTier(_ tier: PriorityTier) {
        self.priorityTier = tier
    }

    /// Called when the recipient field's text changes (typing, paste, recents
    /// tap, Solana Pay URI). Local-only - never issues a network quote. The
    /// user must explicitly tap Review to initiate the RPC round trip.
    public func consumeRecipientText(_ text: String) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.hasPrefix("solana:") {
            do {
                try self.consumeSolanaPayURI(trimmed)
                return
            } catch {
                self.recipientText = trimmed
                self.solanaPayPill = nil
                self.solanaPayContext = nil
                self.unsupportedSolanaPayMint = nil
                self.inputValidation = .quoteError("Invalid Solana Pay link")
                return
            }
        }
        self.recipientText = trimmed
        self.solanaPayPill = nil
        self.solanaPayContext = nil
        self.unsupportedSolanaPayMint = nil
        self.validateRecipientLocally()
    }

    /// Apply a parsed Solana Pay URI to the form. Local-only - same network
    /// gate as `consumeRecipientText`.
    public func consumeSolanaPayURI(_ text: String) throws {
        let expectedDecimals = Int(self.assetDecimals)
        let parsed = try SolanaPayURIParser.parse(text, expectedDecimals: expectedDecimals)
        self.recipientText = parsed.recipient.base58
        if let amount = parsed.amount {
            let plain = (amount as NSDecimalNumber).description(withLocale: Locale(identifier: "en_US_POSIX"))
            self.amountText = plain
        }
        if let splTokenMint = parsed.splToken {
            if !self.effectiveAsset.matches(mint: splTokenMint) {
                if let switched = self.resolvedSplAsset(for: splTokenMint) {
                    self.effectiveAsset = switched
                } else {
                    self.unsupportedSolanaPayMint = splTokenMint
                    self.solanaPayPill = SolanaPayPill(label: parsed.label, message: parsed.message)
                    self.solanaPayContext = Self.solanaPayContext(from: parsed)
                    self.inputValidation = .quoteError("This payment requests a token that is not in this wallet.")
                    return
                }
            }
        } else if !self.effectiveAsset.isNativeSOL {
            self.effectiveAsset = .sol
        }
        self.unsupportedSolanaPayMint = nil
        self.solanaPayPill = SolanaPayPill(label: parsed.label, message: parsed.message)
        self.solanaPayContext = Self.solanaPayContext(from: parsed)
        self.validateAllLocally()
    }

    /// Re-validate when the amount field changes. Local-only; pure parse
    /// against the active mint's decimals + balance check.
    public func consumeAmountChange() {
        self.validateAllLocally()
    }

    private func resolvedSplAsset(for mint: Mint) -> SendAssetKind? {
        guard let lookup = self.splTokenLookup else { return nil }
        guard let info = lookup(mint) else { return nil }
        return .splToken(mint: mint, decimals: info.decimals, symbol: info.symbol, name: info.name)
    }
}

// MARK: - Recents

extension SendViewModel {
    public func loadRecents() async {
        guard let store = self.recentRecipientsStore else {
            self.recents = []
            return
        }
        self.recents = await store.list(walletId: self.intent.walletId)
    }

    public func recordRecipientOnConfirm(_ store: RecentRecipientsStore) async {
        guard let address = try? WalletAddress(base58: self.recipientText) else { return }
        await store.record(address, walletId: self.intent.walletId)
    }
}

// MARK: - Derived display values

extension SendViewModel {
    public var assetSymbol: String {
        switch self.effectiveAsset {
        case .sol: "SOL"
        case let .splToken(_, _, symbol, _): symbol ?? "token"
        }
    }

    public var assetName: String {
        switch self.effectiveAsset {
        case .sol: "Solana"
        case let .splToken(_, _, _, name): name ?? self.assetSymbol
        }
    }

    public var assetDecimals: UInt8 {
        switch self.effectiveAsset {
        case .sol: 9
        case let .splToken(_, decimals, _, _): decimals
        }
    }

    public var isNativeAsset: Bool {
        if case .sol = self.effectiveAsset { return true }
        return false
    }

    public var balanceDisplay: String {
        let amount = TokenAmount(amount: self.assetBalanceBaseUnits, decimals: self.assetDecimals)
        return TokenAmountFormatter(locale: Locale(identifier: "en_US"))
            .string(amount, symbol: self.assetSymbol)
    }

    public var balanceUSDDisplay: String? {
        guard let price = self.assetPriceUSD else { return nil }
        let scale = Self.power10(Int(self.assetDecimals))
        let decimalAmount = Decimal(self.assetBalanceBaseUnits) / scale
        let usd = decimalAmount * price
        return CurrencyFormatter(locale: Locale(identifier: "en_US")).string(usd: usd)
    }

    public var echoText: String? {
        guard self.assetPriceUSD != nil else { return nil }
        let calc = SendAmountCalculator()
        let input = self.amountInput()
        let result = calc.compute(.manual(text: self.amountText, mode: self.fiatMode), input: input)
        switch self.fiatMode {
        case .token: return result.displayFiat
        case .fiat: return result.displayToken
        }
    }

    /// Wallets from the user's own ZODSol directory that match the current
    /// recipient text. The sender is filtered out by `directoryWallets` itself
    /// so it never appears as a self-send shortcut. Empty input shows the full
    /// list; non-empty input matches case-insensitive prefixes on the label or
    /// the base58 address. An exact-match recipient is hidden so the dropdown
    /// disappears once the user has committed to a choice.
    public var walletSuggestions: [WalletIdentity] {
        let trimmed = self.recipientText.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            return self.directoryWallets
        }
        let needle = trimmed.lowercased()
        if self.directoryWallets.contains(where: { $0.address.base58 == trimmed }) {
            return []
        }
        return self.directoryWallets.filter { wallet in
            wallet.label.lowercased().contains(needle) ||
                wallet.address.base58.lowercased().hasPrefix(needle)
        }
    }

    public var canReview: Bool {
        guard self.inputValidation == .ok else { return false }
        guard !self.recipientText.isEmpty else { return false }
        let calc = SendAmountCalculator()
        let input = self.amountInput()
        let result = calc.compute(.manual(text: self.amountText, mode: self.fiatMode), input: input)
        return result.baseUnits > 0 && !result.exceedsBalance && !result.decimalsError
    }

    func amountInputForChips() -> SendAmountInput {
        self.amountInput()
    }
}

// MARK: - Local validation + parsing

extension SendViewModel {
    enum SendInputError: Error {
        case message(String)
    }

    func parseRequest() throws -> SendRequest {
        let recipientRaw = self.recipientText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !recipientRaw.isEmpty else {
            throw SendInputError.message("Paste a recipient address.")
        }
        let recipient: WalletAddress
        do {
            recipient = try WalletAddress(base58: recipientRaw)
        } catch {
            throw SendInputError.message("Recipient address is not a valid Solana address.")
        }

        let amountRaw = self.amountText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !amountRaw.isEmpty else {
            throw SendInputError.message("Enter an amount to send.")
        }
        if self.unsupportedSolanaPayMint != nil {
            throw SendInputError.message("This payment requests a token that is not in this wallet.")
        }

        switch self.effectiveAsset {
        case .sol:
            let decimals: UInt8 = 9
            let baseUnits = try Self.parseAmount(amountRaw, decimals: decimals)
            guard baseUnits > 0 else {
                throw SendInputError.message("Amount must be greater than zero.")
            }
            return SendRequest(
                walletId: self.intent.walletId,
                from: self.intent.from,
                recipient: recipient,
                asset: .sol(amount: Lamports(rawValue: baseUnits)),
                solanaPay: self.solanaPayContext)
        case let .splToken(mint, decimals, _, _):
            let baseUnits = try Self.parseAmount(amountRaw, decimals: decimals)
            guard baseUnits > 0 else {
                throw SendInputError.message("Amount must be greater than zero.")
            }
            let mintAddress = try WalletAddress(base58: mint.base58)
            return SendRequest(
                walletId: self.intent.walletId,
                from: self.intent.from,
                recipient: recipient,
                asset: .splToken(mint: mintAddress, amount: baseUnits, decimals: decimals),
                solanaPay: self.solanaPayContext)
        }
    }

    /// Convert a user-typed decimal string into base units, rejecting any
    /// inputs with more fractional digits than `decimals` allows.
    static func parseAmount(_ text: String, decimals: UInt8) throws -> UInt64 {
        let cleaned = text.replacingOccurrences(of: ",", with: "")
        let parts = cleaned.split(separator: ".", maxSplits: 1, omittingEmptySubsequences: false)
        guard !parts.isEmpty else {
            throw SendInputError.message("Amount is not a valid number.")
        }
        let wholeText = String(parts[0])
        let fractionText = parts.count > 1 ? String(parts[1]) : ""

        guard wholeText.isEmpty || wholeText.allSatisfy(\.isNumber) else {
            throw SendInputError.message("Amount contains non-numeric characters.")
        }
        guard fractionText.allSatisfy(\.isNumber) else {
            throw SendInputError.message("Amount contains non-numeric characters.")
        }
        guard fractionText.count <= Int(decimals) else {
            throw SendInputError.message("This token allows at most \(decimals) decimal places.")
        }

        let paddedFraction = fractionText.padding(toLength: Int(decimals), withPad: "0", startingAt: 0)
        let combined = (wholeText.isEmpty ? "0" : wholeText) + paddedFraction
        guard let baseUnits = UInt64(combined) else {
            throw SendInputError.message("Amount is out of range.")
        }
        return baseUnits
    }

    func amountInput() -> SendAmountInput {
        let fee = self.feeReserveLamports
        var rent = self.rentReserveLamports
        if !self.isNativeAsset {
            if let quote = self.lastQuote, quote.recipientAtaWillBeCreated == false {
                // Recipient ATA already exists - no rent surcharge needed.
            } else {
                let combined = rent.rawValue &+ self.ataRentReserveLamports.rawValue
                rent = Lamports(rawValue: combined)
            }
        }
        return SendAmountInput(
            balanceBaseUnits: self.assetBalanceBaseUnits,
            decimals: self.assetDecimals,
            priceUSD: self.assetPriceUSD,
            feeReserveLamports: fee,
            rentReserveLamports: rent,
            isNativeSOL: self.isNativeAsset)
    }

    func validateAllLocally() {
        self.validateRecipientLocally()
        guard self.inputValidation == .ok else { return }
        let calc = SendAmountCalculator()
        let input = self.amountInput()
        let result = calc.compute(.manual(text: self.amountText, mode: self.fiatMode), input: input)
        if result.decimalsError {
            self.inputValidation = .decimalsExceedMint(decimals: self.assetDecimals)
            return
        }
        if result.exceedsBalance {
            self.inputValidation = .amountExceedsBalance
            return
        }
        if !self.amountText.isEmpty, result.baseUnits == 0 {
            self.inputValidation = .amountTooSmall
            return
        }
        self.inputValidation = .ok
    }

    func validateRecipientLocally() {
        let text = self.recipientText
        if text.isEmpty {
            self.inputValidation = .quoteError("")
            return
        }
        if self.unsupportedSolanaPayMint != nil {
            self.inputValidation = .quoteError("This payment requests a token that is not in this wallet.")
            return
        }
        let address: WalletAddress
        do {
            address = try WalletAddress(base58: text)
        } catch {
            self.inputValidation = .quoteError("Invalid address")
            return
        }
        if address == self.intent.from {
            self.inputValidation = .sendingToSelf
            return
        }
        if Self.isKnownProgramAddress(address) {
            self.inputValidation = .knownProgramRecipient
            return
        }
        if self.isNativeAsset, !Ed25519Curve.isOnCurve(address) {
            self.inputValidation = .offCurveForSol
            return
        }
        self.inputValidation = .ok
    }

    static func isKnownProgramAddress(_ address: WalletAddress) -> Bool {
        let known: [WalletAddress] = [
            ProgramAddresses.system,
            ProgramAddresses.token,
            ProgramAddresses.token2022,
            ProgramAddresses.associatedToken,
            ProgramAddresses.computeBudget,
        ]
        return known.contains(address)
    }

    static func power10(_ exponent: Int) -> Decimal {
        var result = Decimal(1)
        var base = Decimal(10)
        var remaining = exponent
        while remaining > 0 {
            if remaining & 1 == 1 { result *= base }
            remaining >>= 1
            if remaining > 0 { base *= base }
        }
        return result
    }

    static func solanaPayContext(from uri: SolanaPayURI) -> SolanaPayTransferContext {
        SolanaPayTransferContext(
            label: uri.label,
            message: uri.message,
            memo: uri.memo,
            references: uri.references)
    }
}

extension SendAssetKind {
    fileprivate var isNativeSOL: Bool {
        if case .sol = self { return true }
        return false
    }

    fileprivate func matches(mint: Mint) -> Bool {
        if case let .splToken(m, _, _, _) = self {
            return m == mint
        }
        return false
    }
}
