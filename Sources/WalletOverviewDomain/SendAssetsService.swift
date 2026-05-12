import Foundation
import OSLog
import SolanaKit
import SolanaRPC

// MARK: - Protocol

public protocol SendAssetsService: Sendable {
    /// Validate, simulate and price the request without signing or
    /// broadcasting. Returns a `SendQuote` the UI presents on the confirm
    /// screen. `tier` selects the percentile used for priority-fee bidding.
    func quote(_ request: SendRequest, tier: PriorityTier) async throws -> SendQuote

    /// Sign the quote's `signableMessage`, broadcast (in a task that
    /// survives parent cancellation), then poll for confirmation. The seed
    /// never leaves `signer.signMessage`.
    func send(quote: SendQuote) async throws -> SendOutcome

    /// Refresh status of previously-persisted signatures. Used on panel
    /// reopen when a prior `send` was cancelled mid-poll.
    func resync(walletId: UUID) async -> [Signature: SendOutcome]
}

extension SendAssetsService {
    /// Convenience overload preserving the historical default behavior
    /// (75th percentile priority fee).
    public func quote(_ request: SendRequest) async throws -> SendQuote {
        try await self.quote(request, tier: .fast)
    }
}

// MARK: - Configuration

public struct SendAssetsServiceConfig: Sendable {
    /// Hardcoded ATA rent. Mainnet's current rent-exempt minimum for a
    /// 165-byte SPL token account. Production wallets should fetch
    /// `getMinimumBalanceForRentExemption(165)` but the value has been
    /// stable for years and pre-computing avoids an extra RPC roundtrip.
    public let ataRentLamports: Lamports

    /// Confirmation poll deadline; after this elapses without a status, we
    /// return `.expired`.
    public let confirmationTimeoutSeconds: Int

    /// How long between `getSignatureStatuses` polls.
    public let pollInterval: Duration

    /// Floor for priority-fee selection (microLamports / CU). Devnet
    /// returns mostly zeros from `getRecentPrioritizationFees`; without a
    /// floor we'd never compete during congestion spikes.
    public let priorityFeeFloorMicroLamports: UInt64

    public static let `default` = SendAssetsServiceConfig(
        ataRentLamports: Lamports(rawValue: 2_039_280),
        confirmationTimeoutSeconds: 90,
        pollInterval: .milliseconds(1500),
        priorityFeeFloorMicroLamports: 1000)

    public init(
        ataRentLamports: Lamports,
        confirmationTimeoutSeconds: Int,
        pollInterval: Duration,
        priorityFeeFloorMicroLamports: UInt64)
    {
        self.ataRentLamports = ataRentLamports
        self.confirmationTimeoutSeconds = confirmationTimeoutSeconds
        self.pollInterval = pollInterval
        self.priorityFeeFloorMicroLamports = priorityFeeFloorMicroLamports
    }
}

// MARK: - Default implementation

public actor DefaultSendAssetsService: SendAssetsService {
    private let transport: any RPCTransport
    private let walletLookup: any SendWalletLookup
    private let signer: any SendSignerAccess
    private let pendingStore: PendingSendStore
    private let network: SolanaNetwork
    private let config: SendAssetsServiceConfig
    private let clock: any Clock<Duration>
    private let logger = Logger(subsystem: "dev.zods.zodsol", category: "send-assets")

    /// One in-flight send per wallet. Subsequent calls error rather than
    /// silently queueing, so the UI sees the conflict.
    private var inFlight: Set<UUID> = []

    public init(
        transport: any RPCTransport,
        walletLookup: any SendWalletLookup,
        signer: any SendSignerAccess,
        pendingStore: PendingSendStore,
        network: SolanaNetwork,
        config: SendAssetsServiceConfig = .default,
        clock: any Clock<Duration> = ContinuousClock())
    {
        self.transport = transport
        self.walletLookup = walletLookup
        self.signer = signer
        self.pendingStore = pendingStore
        self.network = network
        self.config = config
        self.clock = clock
    }

    // MARK: - quote

    public func quote(_ request: SendRequest, tier: PriorityTier) async throws -> SendQuote {
        // 1. Validate the wallet -> from address pairing.
        let expectedFrom: WalletAddress
        do {
            expectedFrom = try await self.walletLookup.address(for: request.walletId)
        } catch {
            throw SendError.walletAddressMismatch
        }
        guard expectedFrom == request.from else {
            throw SendError.walletAddressMismatch
        }

        // 2. Reject obviously-bad recipients before any RPC call.
        try Self.validateRecipient(request.recipient, asset: request.asset)

        // 3. For SPL: resolve token program from the mint, parse extensions,
        // decide compatibility.
        let tokenContext: TokenSendContext? = switch request.asset {
        case .sol:
            nil
        case let .splToken(mint, amount, decimals):
            try await resolveTokenContext(
                mint: mint, amount: amount, decimals: decimals,
                sender: request.from, recipient: request.recipient)
        }

        // 4. Fetch latest blockhash.
        let (blockhash, lastValidBlockHeight) = try await fetchLatestBlockhash()
        let lifetime = Lifetime.blockhash(blockhash, lastValidBlockHeight: lastValidBlockHeight)

        // 5. Pick priority fee from recent percentile, with floor.
        let writableAccounts = computeWritableAccounts(request: request, tokenContext: tokenContext)
        let priorityFee = try await fetchPriorityFee(writableAccounts: writableAccounts, tier: tier)

        // 6. Build probe message with max CU, simulate to estimate.
        let probeMessage = try buildMessage(
            request: request,
            tokenContext: tokenContext,
            computeUnitLimit: 1_400_000,
            computeUnitPrice: priorityFee,
            lifetime: lifetime)
        let probeCompiled = try MessageCompiler.compile(probeMessage)
        let unitsConsumed = try await simulateForCompute(probeCompiled)

        // 7. Apply 1.1× margin, floor at 5_000.
        let estimatedLimit = max(5000, UInt32(min(UInt64(UInt32.max), unitsConsumed * 11 / 10 + 1)))

        // 8. Rebuild with real CU, re-simulate as a safety check.
        let finalMessage = try buildMessage(
            request: request,
            tokenContext: tokenContext,
            computeUnitLimit: estimatedLimit,
            computeUnitPrice: priorityFee,
            lifetime: lifetime)
        let finalCompiled = try MessageCompiler.compile(finalMessage)
        let finalSim = try await simulateForSafety(finalCompiled)
        if let errString = finalSim.errorString {
            throw SendError.simulationFailed(logs: finalSim.logs, error: errString)
        }

        // 9. Fee math.
        let networkFee = computeNetworkFee(
            numSignatures: finalCompiled.signerAddresses.count,
            computeUnitLimit: estimatedLimit,
            computeUnitPriceMicroLamports: priorityFee)

        // 10. Sender SOL balance must cover (network fee + ATA rent if creating
        //     + amount in lamports if sending SOL).
        let senderLamports = try await fetchLamports(address: request.from)
        try assertSolSufficient(
            request: request,
            senderLamports: senderLamports,
            networkFee: networkFee,
            ataRentNeeded: tokenContext?.recipientAtaWillBeCreated == true ? self.config.ataRentLamports : nil)

        // 11. Compute "recipient receives" (only differs for Token-2022 fees).
        let recipientReceives = computeRecipientReceives(asset: request.asset, context: tokenContext)

        // 12. Size guard (defense in depth — compile would already reject).
        let placeholder = try MessageCompiler.placeholderTransaction(for: finalCompiled)
        guard !placeholder.exceedsPacketLimit else {
            throw SendError.transactionTooLarge(bytes: placeholder.wireBytes.count)
        }

        return SendQuote(
            request: request,
            networkFeeLamports: networkFee,
            priorityFeeMicroLamports: priorityFee,
            computeUnitLimit: estimatedLimit,
            recipientAtaWillBeCreated: tokenContext?.recipientAtaWillBeCreated ?? false,
            rentForRecipientAta: tokenContext?.recipientAtaWillBeCreated == true ? self.config
                .ataRentLamports : Lamports(rawValue: 0),
            token2022Notice: tokenContext?.notice,
            recipientReceives: recipientReceives,
            cluster: self.network,
            simulationLogs: finalSim.logs,
            signableMessage: finalCompiled.messageBytes,
            lifetime: lifetime)
    }

    // MARK: - send

    public func send(quote: SendQuote) async throws -> SendOutcome {
        let walletId = quote.request.walletId
        guard !self.inFlight.contains(walletId) else {
            throw SendError.sendAlreadyInFlight
        }
        self.inFlight.insert(walletId)
        defer { inFlight.remove(walletId) }

        // 1. Sign — seed never leaves the closure.
        let signature: Signature
        do {
            signature = try await self.signer.signMessage(
                walletId: walletId,
                message: quote.signableMessage,
                prompt: "Sign Solana transfer")
        } catch is CancellationError {
            throw SendError.canceled
        }

        // 2. Build wire transaction.
        let recompiled = CompiledMessage(
            messageBytes: quote.signableMessage,
            signerAddresses: [quote.request.from],
            accountKeys: [])
        let signed = try CompiledTransaction(message: recompiled, signatures: [signature])
        let base64Wire = signed.wireBytes.base64EncodedString()

        // 3. Persist the signature BEFORE broadcasting so a crash mid-broadcast
        //    leaves a recoverable record.
        let (blockhash, lastValidBlockHeight) = unwrap(lifetime: quote.lifetime)
        _ = blockhash
        await self.pendingStore.add(PendingSend(
            walletId: walletId,
            signatureBase58: signature.base58,
            lastValidBlockHeight: lastValidBlockHeight,
            network: self.network,
            createdAt: Date()))

        // 4. Broadcast in a detached task so panel-close mid-broadcast doesn't
        //    cancel it. We still await the result so we can surface immediate
        //    transport-level failures to the user.
        let transport = self.transport
        let broadcastTask: Task<Void, any Error> = Task.detached(priority: .userInitiated) {
            let req = SendTransactionRPC.request(base64Transaction: base64Wire)
            let resp: JSONRPCResponse<String> = try await transport.sendOnce(
                req, responseType: JSONRPCResponse<String>.self)
            _ = try resp.unwrap()
        }

        do {
            try await broadcastTask.value
        } catch let rpcError as RPCError {
            // The broadcast itself failed (network drop, RPC -32xxx). The
            // signature was persisted but the cluster never saw it; drop it.
            await pendingStore.remove(signatureBase58: signature.base58)
            throw SendError.rpc(Self.mapRPCError(rpcError))
        } catch {
            await self.pendingStore.remove(signatureBase58: signature.base58)
            throw SendError.broadcastFailed(reason: String(describing: error))
        }

        // If the parent task was cancelled mid-broadcast, surface that now —
        // the detached task already completed so the signature is on its way
        // to the cluster regardless.
        if Task.isCancelled {
            throw SendError.canceled
        }

        // 5. Poll for confirmation.
        return try await pollForConfirmation(
            signature: signature,
            lastValidBlockHeight: lastValidBlockHeight,
            walletId: walletId)
    }

    // MARK: - resync

    public func resync(walletId: UUID) async -> [Signature: SendOutcome] {
        await self.pendingStore.prune(olderThan: 600)
        let pending = await pendingStore.list(for: walletId)
        var outcomes: [Signature: SendOutcome] = [:]

        for entry in pending {
            guard let signature = try? Signature(base58: entry.signatureBase58) else {
                await self.pendingStore.remove(signatureBase58: entry.signatureBase58)
                continue
            }

            // First check if it has rolled out of the recent-status window.
            let now = Date()
            let age = now.timeIntervalSince(entry.createdAt)
            if age > Double(self.config.confirmationTimeoutSeconds) + 60 {
                await self.pendingStore.remove(signatureBase58: entry.signatureBase58)
                outcomes[signature] = .expired(signature)
                continue
            }

            do {
                let req = SignatureStatusesRPC.request(
                    signatures: [entry.signatureBase58], searchTransactionHistory: true)
                let resp: JSONRPCResponse<SignatureStatusesRPC.Result> = try await transport.send(
                    req, responseType: JSONRPCResponse<SignatureStatusesRPC.Result>.self)
                let result = try resp.unwrap()
                if let status = result.value.first ?? nil {
                    if status.err != nil {
                        await self.pendingStore.remove(signatureBase58: entry.signatureBase58)
                        outcomes[signature] = .failed(signature, error: Self.stringify(status.err))
                    } else if Self.isFinalEnough(status.confirmationStatus) {
                        await self.pendingStore.remove(signatureBase58: entry.signatureBase58)
                        outcomes[signature] = .confirmed(signature, slot: status.slot)
                    }
                    // else: still in-flight; leave in store, no outcome yet
                }
            } catch {
                // Transient error during resync — leave entry for next try.
                self.logger
                    .debug("resync failed for \(entry.signatureBase58, privacy: .public): \(String(describing: error))")
            }
        }
        return outcomes
    }

    // MARK: - Private: SPL token context (definitions used by extension)

    struct TokenSendContext {
        let mint: WalletAddress
        let amount: UInt64
        let decimals: UInt8
        let tokenProgram: WalletAddress
        let senderAta: WalletAddress
        let recipientAta: WalletAddress
        let recipientAtaWillBeCreated: Bool
        let transferFee: Token2022MintProfile.TransferFeeForEpoch?
        let notice: Token2022Notice?
    }

    struct SimulationOutcome {
        let logs: [String]
        let unitsConsumed: UInt64?
        let errorString: String?
    }
}

// MARK: - Helpers (split out so the main actor body fits the type-body lint cap)

extension DefaultSendAssetsService {
    static func validateRecipient(_ recipient: WalletAddress, asset: SendAsset) throws {
        let knownPrograms: [WalletAddress] = [
            ProgramAddresses.system,
            ProgramAddresses.token,
            ProgramAddresses.token2022,
            ProgramAddresses.associatedToken,
            ProgramAddresses.computeBudget,
        ]
        if knownPrograms.contains(recipient) {
            throw SendError.invalidRecipient(.knownProgramAddress)
        }
        if case .sol = asset, !Ed25519Curve.isOnCurve(recipient) {
            throw SendError.invalidRecipient(.offCurveForSol)
        }
    }

    func resolveTokenContext(
        mint: WalletAddress,
        amount: UInt64,
        decimals: UInt8,
        sender: WalletAddress,
        recipient: WalletAddress) async throws -> TokenSendContext
    {
        // 1. Read mint to learn its owning program + extensions.
        guard let mintAccount = try await fetchAccount(address: mint) else {
            throw SendError.mintNotFound
        }
        let tokenProgram: WalletAddress
        let mintProfile: Token2022MintProfile

        switch mintAccount.owner {
        case ProgramAddresses.token.base58:
            tokenProgram = ProgramAddresses.token
            // Legacy mint: no extension data to parse; build a minimal profile.
            mintProfile = Token2022MintProfile(
                compatibility: .ok,
                decimals: decimals,
                transferFee: nil,
                permanentDelegate: false)
        case ProgramAddresses.token2022.base58:
            tokenProgram = ProgramAddresses.token2022
            guard let data = mintAccount.base64Data, let raw = Data(base64Encoded: data) else {
                throw SendError.mintNotFound
            }
            let currentEpoch = try await fetchCurrentEpoch()
            mintProfile = try Token2022Mint.parse(raw, currentEpoch: currentEpoch)
        default:
            throw SendError.mintOwnedByUnknownProgram(owner: mintAccount.owner)
        }

        if case let .refused(reason) = mintProfile.compatibility {
            throw SendError.unsupportedToken2022Extension(reason: reason)
        }

        // 2. Derive sender + recipient ATA against the discovered token program.
        let senderAta = try AssociatedTokenProgram.findAssociatedTokenAddress(
            owner: sender, mint: mint, tokenProgram: tokenProgram)
        let recipientAta = try AssociatedTokenProgram.findAssociatedTokenAddress(
            owner: recipient, mint: mint, tokenProgram: tokenProgram)

        // 3. Check recipient ATA existence (sender ATA must exist; if not we
        //    can't hold this token and the simulate would fail loudly).
        let recipientAtaExists = try await (fetchAccount(address: recipientAta)) != nil

        // 4. UI notice for Token-2022 quirks.
        let notice: Token2022Notice?
        if tokenProgram == ProgramAddresses.token2022 {
            let feeAmount = mintProfile.transferFee?.fee(for: amount)
            notice = Token2022Notice(
                transferFeeAmount: feeAmount,
                transferFeeBasisPoints: mintProfile.transferFee?.basisPoints,
                permanentDelegate: mintProfile.permanentDelegate)
        } else {
            notice = nil
        }

        return TokenSendContext(
            mint: mint,
            amount: amount,
            decimals: decimals,
            tokenProgram: tokenProgram,
            senderAta: senderAta,
            recipientAta: recipientAta,
            recipientAtaWillBeCreated: !recipientAtaExists,
            transferFee: mintProfile.transferFee,
            notice: notice)
    }

    // MARK: - Private: message building

    private func buildMessage(
        request: SendRequest,
        tokenContext: TokenSendContext?,
        computeUnitLimit: UInt32,
        computeUnitPrice: UInt64,
        lifetime: Lifetime) throws -> TransactionMessage
    {
        var instructions: [Instruction] = [
            ComputeBudgetProgram.setComputeUnitLimit(units: computeUnitLimit),
            ComputeBudgetProgram.setComputeUnitPrice(microLamports: computeUnitPrice),
        ]
        switch request.asset {
        case let .sol(amount):
            instructions.append(SystemProgram.transferSol(
                from: request.from, to: request.recipient, lamports: amount))
        case .splToken:
            guard let ctx = tokenContext else {
                throw SendError.simulationFailed(logs: [], error: "missing token context")
            }
            if ctx.recipientAtaWillBeCreated {
                instructions.append(AssociatedTokenProgram.createAssociatedTokenIdempotent(
                    payer: request.from,
                    owner: request.recipient,
                    mint: ctx.mint,
                    associatedToken: ctx.recipientAta,
                    tokenProgram: ctx.tokenProgram))
            }
            if ctx.tokenProgram == ProgramAddresses.token2022, let fee = ctx.transferFee {
                instructions.append(Token2022Program.transferCheckedWithFee(
                    source: ctx.senderAta, mint: ctx.mint, destination: ctx.recipientAta, owner: request.from,
                    amount: ctx.amount, decimals: ctx.decimals, fee: fee.fee(for: ctx.amount)))
            } else if ctx.tokenProgram == ProgramAddresses.token2022 {
                instructions.append(Token2022Program.transferChecked(
                    source: ctx.senderAta, mint: ctx.mint, destination: ctx.recipientAta, owner: request.from,
                    amount: ctx.amount, decimals: ctx.decimals))
            } else {
                instructions.append(TokenProgram.transferChecked(
                    source: ctx.senderAta, mint: ctx.mint, destination: ctx.recipientAta, owner: request.from,
                    amount: ctx.amount, decimals: ctx.decimals))
            }
        }
        return TransactionMessage(feePayer: request.from, instructions: instructions, lifetime: lifetime)
    }

    private func computeWritableAccounts(
        request: SendRequest,
        tokenContext: TokenSendContext?) -> [String]
    {
        switch request.asset {
        case .sol:
            return [request.from.base58, request.recipient.base58]
        case .splToken:
            guard let ctx = tokenContext else { return [request.from.base58] }
            return [request.from.base58, ctx.senderAta.base58, ctx.recipientAta.base58]
        }
    }

    // MARK: - Private: fee math + balance checks

    private func computeNetworkFee(
        numSignatures: Int,
        computeUnitLimit: UInt32,
        computeUnitPriceMicroLamports: UInt64) -> Lamports
    {
        let baseFee = UInt64(numSignatures) * 5000
        // ceil(cuLimit * cuPrice / 1_000_000)
        let product = UInt64(computeUnitLimit) * computeUnitPriceMicroLamports
        let priorityFee = (product + 999_999) / 1_000_000
        return Lamports(rawValue: baseFee + priorityFee)
    }

    private func assertSolSufficient(
        request: SendRequest,
        senderLamports: UInt64,
        networkFee: Lamports,
        ataRentNeeded: Lamports?) throws
    {
        var required = networkFee.rawValue
        if let rent = ataRentNeeded {
            required += rent.rawValue
        }
        if case let .sol(amount) = request.asset {
            required += amount.rawValue
        }
        if senderLamports < required {
            if let rent = ataRentNeeded, senderLamports < networkFee.rawValue + rent.rawValue {
                throw SendError.insufficientSolForRent(
                    required: Lamports(rawValue: networkFee.rawValue + rent.rawValue),
                    available: Lamports(rawValue: senderLamports))
            }
            throw SendError.insufficientSolForFee(
                required: Lamports(rawValue: required), available: Lamports(rawValue: senderLamports))
        }
    }

    private func computeRecipientReceives(asset: SendAsset, context: TokenSendContext?) -> SendAsset {
        switch asset {
        case .sol:
            return asset
        case let .splToken(mint, amount, decimals):
            if let ctx = context, let fee = ctx.transferFee {
                let feeAmount = fee.fee(for: amount)
                let net = amount > feeAmount ? amount - feeAmount : 0
                return .splToken(mint: mint, amount: net, decimals: decimals)
            }
            return asset
        }
    }

    // MARK: - Private: RPC helpers

    private func fetchLatestBlockhash() async throws -> (Blockhash, UInt64) {
        let req = LatestBlockhashRPC.request()
        let resp: JSONRPCResponse<LatestBlockhashRPC.Result> = try await transport.send(
            req, responseType: JSONRPCResponse<LatestBlockhashRPC.Result>.self)
        let result = try resp.unwrap()
        let blockhash = try Blockhash(base58: result.value.blockhash)
        return (blockhash, result.value.lastValidBlockHeight)
    }

    private func fetchAccount(address: WalletAddress) async throws -> AccountInfoRPC.AccountValue? {
        let req = AccountInfoRPC.request(address: address.base58)
        let resp: JSONRPCResponse<AccountInfoRPC.Result> = try await transport.send(
            req, responseType: JSONRPCResponse<AccountInfoRPC.Result>.self)
        let result = try resp.unwrap()
        return result.value
    }

    private func fetchLamports(address: WalletAddress) async throws -> UInt64 {
        try await self.fetchAccount(address: address)?.lamports ?? 0
    }

    private func fetchCurrentEpoch() async throws -> UInt64 {
        let req = EpochInfoRPC.request()
        let resp: JSONRPCResponse<EpochInfoRPC.Result> = try await transport.send(
            req, responseType: JSONRPCResponse<EpochInfoRPC.Result>.self)
        return try resp.unwrap().epoch
    }

    private func fetchPriorityFee(writableAccounts: [String], tier: PriorityTier) async throws -> UInt64 {
        let req = RecentPrioritizationFeesRPC.request(accountAddresses: writableAccounts)
        let resp: JSONRPCResponse<RecentPrioritizationFeesRPC.Result> = try await transport.send(
            req, responseType: JSONRPCResponse<RecentPrioritizationFeesRPC.Result>.self)
        let fees = try resp.unwrap().map(\.prioritizationFee).sorted()
        guard !fees.isEmpty else { return self.config.priorityFeeFloorMicroLamports }
        let index = max(0, min(fees.count - 1, Int(Double(fees.count) * tier.percentile)))
        return max(fees[index], self.config.priorityFeeFloorMicroLamports)
    }

    // MARK: - Private: simulation

    private func simulateForCompute(_ compiled: CompiledMessage) async throws -> UInt64 {
        let placeholder = try MessageCompiler.placeholderTransaction(for: compiled)
        let base64 = placeholder.wireBytes.base64EncodedString()
        let outcome = try await runSimulation(base64: base64)
        if let err = outcome.errorString {
            throw SendError.simulationFailed(logs: outcome.logs, error: err)
        }
        return outcome.unitsConsumed ?? 200_000
    }

    private func simulateForSafety(_ compiled: CompiledMessage) async throws -> SimulationOutcome {
        let placeholder = try MessageCompiler.placeholderTransaction(for: compiled)
        let base64 = placeholder.wireBytes.base64EncodedString()
        return try await self.runSimulation(base64: base64)
    }

    private func runSimulation(base64: String) async throws -> SimulationOutcome {
        let req = SimulateTransactionRPC.request(base64Transaction: base64)
        let resp: JSONRPCResponse<SimulateTransactionRPC.Result> = try await transport.send(
            req, responseType: JSONRPCResponse<SimulateTransactionRPC.Result>.self)
        let result = try resp.unwrap()
        return SimulationOutcome(
            logs: result.value.logs ?? [],
            unitsConsumed: result.value.unitsConsumed,
            errorString: result.value.err.map { Self.stringify($0) })
    }

    // MARK: - Private: confirmation loop

    private func pollForConfirmation(
        signature: Signature,
        lastValidBlockHeight: UInt64,
        walletId: UUID) async throws -> SendOutcome
    {
        let deadline = Date().addingTimeInterval(TimeInterval(self.config.confirmationTimeoutSeconds))
        var ticksSinceEpochCheck = 0

        while Date() < deadline {
            try Task.checkCancellation()

            // Status check.
            let statusReq = SignatureStatusesRPC.request(signatures: [signature.base58])
            let resp: JSONRPCResponse<SignatureStatusesRPC.Result> = try await transport.send(
                statusReq, responseType: JSONRPCResponse<SignatureStatusesRPC.Result>.self)
            let result = try resp.unwrap()
            if let status = result.value.first ?? nil {
                if status.err != nil {
                    await self.pendingStore.remove(signatureBase58: signature.base58)
                    return .failed(signature, error: Self.stringify(status.err))
                }
                if Self.isFinalEnough(status.confirmationStatus) {
                    await self.pendingStore.remove(signatureBase58: signature.base58)
                    return .confirmed(signature, slot: status.slot)
                }
            }

            // Every ~3 ticks check block height for blockhash expiry.
            ticksSinceEpochCheck += 1
            if ticksSinceEpochCheck >= 3 {
                ticksSinceEpochCheck = 0
                let epochReq = EpochInfoRPC.request()
                let epochResp: JSONRPCResponse<EpochInfoRPC.Result> = try await transport.send(
                    epochReq, responseType: JSONRPCResponse<EpochInfoRPC.Result>.self)
                let epoch = try epochResp.unwrap()
                if epoch.blockHeight > lastValidBlockHeight {
                    await self.pendingStore.remove(signatureBase58: signature.base58)
                    return .expired(signature)
                }
            }

            try await self.clock.sleep(for: self.config.pollInterval)
        }
        // Timed out without confirmation.
        await self.pendingStore.remove(signatureBase58: signature.base58)
        return .expired(signature)
    }

    // MARK: - Private: utilities

    private static func isFinalEnough(_ confirmationStatus: String?) -> Bool {
        confirmationStatus == "confirmed" || confirmationStatus == "finalized"
    }

    private static func stringify(_ err: AnyJSON?) -> String {
        guard let err else { return "unknown error" }
        let encoder = JSONEncoder()
        if let data = try? encoder.encode(err), let s = String(data: data, encoding: .utf8) {
            return s
        }
        return "unstructured error"
    }

    private static func mapRPCError(_ error: RPCError) -> SolanaProviderError {
        switch error {
        case .canceled: return .canceled
        case let .http(status, retryAfter):
            switch status {
            case 401, 403: return .unauthorized
            case 429: return .rateLimited(retryAfter: retryAfter)
            default: return .providerUnavailable(message: "HTTP \(status)")
            }
        case let .transport(code):
            if code == .notConnectedToInternet || code == .cannotConnectToHost {
                return .networkUnavailable
            }
            return .providerUnavailable(message: "transport: \(code.rawValue)")
        case let .decoding(message):
            return .malformedResponse(message)
        case let .rpc(rpcError):
            return .providerUnavailable(message: rpcError.message)
        }
    }

    private func unwrap(lifetime: Lifetime) -> (Blockhash, UInt64) {
        switch lifetime {
        case let .blockhash(blockhash, lastValidBlockHeight):
            (blockhash, lastValidBlockHeight)
        }
    }
}
