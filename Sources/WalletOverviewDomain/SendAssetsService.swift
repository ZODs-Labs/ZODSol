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

    /// Rebuild a fresh message, sign it, broadcast in a task that survives
    /// parent cancellation, then poll for confirmation. The seed never leaves
    /// `signer.signMessage`.
    func send(quote: SendQuote) async throws -> SendOutcome

    /// Refresh status of previously-persisted signatures. Used on panel
    /// reopen when a prior `send` was cancelled mid-poll.
    func resync(walletId: UUID) async -> [PendingSendResolution]
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

    /// UI patience budget used by callers. Expiration is decided only by the
    /// chain block-height window.
    public let confirmationTimeoutSeconds: Int

    /// How long between `getSignatureStatuses` polls.
    public let pollInterval: Duration

    /// Floor for priority-fee selection (microLamports / CU). Devnet
    /// returns mostly zeros from `getRecentPrioritizationFees`; without a
    /// floor we'd never compete during congestion spikes.
    public let priorityFeeFloorMicroLamports: UInt64
    public let priorityFeeCapMicroLamports: UInt64
    public let priorityFeeRecentSlotWindow: UInt64
    public let priorityFeeOutlierMultiplier: UInt64

    public static let `default` = SendAssetsServiceConfig(
        ataRentLamports: Lamports(rawValue: 2_039_280),
        confirmationTimeoutSeconds: 90,
        pollInterval: .milliseconds(1500),
        priorityFeeFloorMicroLamports: 1000,
        priorityFeeCapMicroLamports: 250_000,
        priorityFeeRecentSlotWindow: 150,
        priorityFeeOutlierMultiplier: 8)

    public init(
        ataRentLamports: Lamports,
        confirmationTimeoutSeconds: Int,
        pollInterval: Duration,
        priorityFeeFloorMicroLamports: UInt64,
        priorityFeeCapMicroLamports: UInt64 = 250_000,
        priorityFeeRecentSlotWindow: UInt64 = 150,
        priorityFeeOutlierMultiplier: UInt64 = 8)
    {
        self.ataRentLamports = ataRentLamports
        self.confirmationTimeoutSeconds = confirmationTimeoutSeconds
        self.pollInterval = pollInterval
        self.priorityFeeFloorMicroLamports = priorityFeeFloorMicroLamports
        self.priorityFeeCapMicroLamports = priorityFeeCapMicroLamports
        self.priorityFeeRecentSlotWindow = priorityFeeRecentSlotWindow
        self.priorityFeeOutlierMultiplier = priorityFeeOutlierMultiplier
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
    private static let pendingSendMaxAge: TimeInterval = 24 * 60 * 60

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
        let prepared = try await self.prepare(request: request, tier: tier)
        let tokenContext = prepared.tokenContext
        let recipientReceives = computeRecipientReceives(asset: request.asset, context: tokenContext)
        let placeholder = try MessageCompiler.placeholderTransaction(for: prepared.compiled)
        let shapeDigest = self.makeQuoteShapeDigest(
            request: request,
            tokenContext: tokenContext,
            prepared: prepared,
            recipientReceives: recipientReceives)

        return SendQuote(
            request: request,
            networkFeeLamports: prepared.networkFee,
            priorityFeeMicroLamports: prepared.priorityFee,
            computeUnitLimit: prepared.computeUnitLimit,
            recipientAtaWillBeCreated: tokenContext?.recipientAtaWillBeCreated ?? false,
            rentForRecipientAta: tokenContext?.recipientAtaWillBeCreated == true ? self.config
                .ataRentLamports : Lamports(rawValue: 0),
            token2022Notice: tokenContext?.notice,
            recipientReceives: recipientReceives,
            cluster: self.network,
            simulationLogs: prepared.finalSimulation.logs,
            priorityTier: tier,
            reviewDetails: self.makeReviewDetails(
                request: request,
                tokenContext: tokenContext,
                prepared: prepared,
                placeholderBytes: placeholder.wireBytes.count),
            shapeDigest: shapeDigest)
    }

    // MARK: - send

    public func send(quote: SendQuote) async throws -> SendOutcome {
        let walletId = quote.request.walletId
        guard !self.inFlight.contains(walletId) else {
            throw SendError.sendAlreadyInFlight
        }
        self.inFlight.insert(walletId)
        defer { inFlight.remove(walletId) }

        let prepared = try await self.prepare(request: quote.request, tier: quote.priorityTier)
        let recipientReceives = self.computeRecipientReceives(asset: quote.request.asset, context: prepared.tokenContext)
        let freshShape = self.makeQuoteShapeDigest(
            request: quote.request,
            tokenContext: prepared.tokenContext,
            prepared: prepared,
            recipientReceives: recipientReceives)
        if freshShape != quote.shapeDigest {
            throw SendError.quoteExpired(
                changedField: quote.shapeDigest.firstDifference(from: freshShape) ?? "transaction details")
        }
        guard prepared.priorityFee <= quote.priorityFeeMicroLamports else {
            throw SendError.quoteExpired(changedField: "priority fee")
        }
        guard prepared.computeUnitLimit <= quote.computeUnitLimit else {
            throw SendError.quoteExpired(changedField: "compute limit")
        }
        guard prepared.networkFee.rawValue <= quote.networkFeeLamports.rawValue else {
            throw SendError.quoteExpired(changedField: "network fee")
        }
        let placeholder = try MessageCompiler.placeholderTransaction(for: prepared.compiled)
        guard !placeholder.exceedsPacketLimit else {
            throw SendError.transactionTooLarge(bytes: placeholder.wireBytes.count)
        }

        // 1. Sign the fresh message. Seed never leaves the closure.
        let signature: Signature
        do {
            signature = try await self.signer.signMessage(
                walletId: walletId,
                message: prepared.compiled.messageBytes,
                prompt: "Sign Solana transfer")
        } catch is CancellationError {
            throw SendError.canceled
        } catch WalletOverviewError.canceled {
            // User cancelled the biometric prompt or the auth failed. Treat
            // the same as a cancellation so the UI returns to the input
            // screen without wiping any state.
            throw SendError.canceled
        }

        // 2. Build wire transaction.
        let signed = try CompiledTransaction(message: prepared.compiled, signatures: [signature])
        let base64Wire = signed.wireBytes.base64EncodedString()

        // 3. Persist the signature BEFORE broadcasting so a crash mid-broadcast
        //    leaves a recoverable record.
        let (blockhash, lastValidBlockHeight) = unwrap(lifetime: prepared.lifetime)
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
            let req = SendTransactionRPC.request(
                base64Transaction: base64Wire,
                skipPreflight: false,
                preflightCommitment: "confirmed",
                minContextSlot: prepared.minContextSlot)
            let resp: JSONRPCResponse<String> = try await transport.sendOnce(
                req, responseType: JSONRPCResponse<String>.self)
            _ = try resp.unwrap()
        }

        do {
            try await broadcastTask.value
        } catch let rpcError as RPCError {
            if Self.shouldRetainPending(after: rpcError) {
                self.logger.debug(
                    "broadcast threw \(String(describing: rpcError), privacy: .public); falling through to confirmation polling")
            } else {
                await self.pendingStore.remove(signatureBase58: signature.base58)
                throw SendError.rpc(Self.mapRPCError(rpcError))
            }
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

    public func resync(walletId: UUID) async -> [PendingSendResolution] {
        let pending = await pendingStore.list(for: walletId)
        let staleCutoff = Date().addingTimeInterval(-Self.pendingSendMaxAge)
        var outcomes: [PendingSendResolution] = []

        for entry in pending {
            guard let signature = try? Signature(base58: entry.signatureBase58) else {
                await self.pendingStore.remove(signatureBase58: entry.signatureBase58)
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
                        outcomes.append(PendingSendResolution(
                            signature: signature,
                            outcome: .failed(signature, error: Self.stringify(status.err)),
                            createdAt: entry.createdAt))
                    } else if Self.isFinalEnough(status.confirmationStatus) {
                        await self.pendingStore.remove(signatureBase58: entry.signatureBase58)
                        outcomes.append(PendingSendResolution(
                            signature: signature,
                            outcome: .confirmed(signature, slot: status.slot),
                            createdAt: entry.createdAt))
                    }
                    // else: still in-flight; leave in store, no outcome yet
                } else {
                    let epoch = try await self.fetchEpochInfo()
                    if epoch.blockHeight > entry.lastValidBlockHeight {
                        await self.pendingStore.remove(signatureBase58: entry.signatureBase58)
                        outcomes.append(PendingSendResolution(
                            signature: signature,
                            outcome: .expired(signature),
                            createdAt: entry.createdAt))
                    }
                }
            } catch {
                // Transient error during resync — leave entry for next try.
                self.logger
                    .debug("resync failed for \(entry.signatureBase58, privacy: .public): \(String(describing: error))")
            }
            if entry.createdAt < staleCutoff,
               !outcomes.contains(where: { $0.signature == signature })
            {
                await self.pendingStore.remove(signatureBase58: entry.signatureBase58)
            }
        }
        return outcomes.sorted { $0.createdAt < $1.createdAt }
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

    struct PreparedSend {
        let compiled: CompiledMessage
        let lifetime: Lifetime
        let tokenContext: TokenSendContext?
        let networkFee: Lamports
        let priorityFee: UInt64
        let priorityFeeCap: UInt64
        let priorityFeeWasCapped: Bool
        let computeUnitLimit: UInt32
        let finalSimulation: SimulationOutcome
        let minContextSlot: UInt64
        let instructions: [Instruction]
    }
}

// MARK: - Helpers (split out so the main actor body fits the type-body lint cap)

extension DefaultSendAssetsService {
    func prepare(request: SendRequest, tier: PriorityTier) async throws -> PreparedSend {
        try Self.validateRecipient(request.recipient, asset: request.asset)
        let currentSender = try await self.walletLookup.address(for: request.walletId)
        guard currentSender == request.from else { throw SendError.walletAddressMismatch }

        let tokenContext: TokenSendContext?
        switch request.asset {
        case .sol:
            tokenContext = nil
        case let .splToken(mint, amount, decimals):
            tokenContext = try await self.resolveTokenContext(
                mint: mint,
                amount: amount,
                decimals: decimals,
                sender: request.from,
                recipient: request.recipient)
        }

        let writableAccounts = self.computeWritableAccounts(request: request, tokenContext: tokenContext)
        let priorityFee = try await self.fetchPriorityFee(writableAccounts: writableAccounts, tier: tier)
        let latest = try await self.fetchLatestBlockhash()
        let lifetime = Lifetime.blockhash(
            latest.blockhash,
            lastValidBlockHeight: latest.lastValidBlockHeight)

        let estimateMessage = try self.buildMessage(
            request: request,
            tokenContext: tokenContext,
            computeUnitLimit: 400_000,
            computeUnitPrice: priorityFee.priceMicroLamports,
            lifetime: lifetime)
        let estimateCompiled = try MessageCompiler.compile(estimateMessage)
        let units = try await self.simulateForCompute(estimateCompiled, minContextSlot: latest.contextSlot)
        let computeUnitLimit = Self.computeUnitLimit(from: units)

        let finalMessage = try self.buildMessage(
            request: request,
            tokenContext: tokenContext,
            computeUnitLimit: computeUnitLimit,
            computeUnitPrice: priorityFee.priceMicroLamports,
            lifetime: lifetime)
        let compiled = try MessageCompiler.compile(finalMessage)
        let placeholder = try MessageCompiler.placeholderTransaction(for: compiled)
        guard !placeholder.exceedsPacketLimit else {
            throw SendError.transactionTooLarge(bytes: placeholder.wireBytes.count)
        }

        let simulation = try await self.simulateForSafety(compiled, minContextSlot: latest.contextSlot)
        if let err = simulation.errorString {
            throw SendError.simulationFailed(logs: simulation.logs, error: err)
        }

        let networkFee = self.computeNetworkFee(
            numSignatures: compiled.signerAddresses.count,
            computeUnitLimit: computeUnitLimit,
            computeUnitPriceMicroLamports: priorityFee.priceMicroLamports)
        let senderLamports = try await self.fetchLamports(address: request.from)
        try self.assertSolSufficient(
            request: request,
            senderLamports: senderLamports,
            networkFee: networkFee,
            ataRentNeeded: tokenContext?.recipientAtaWillBeCreated == true ? self.config.ataRentLamports : nil)

        return PreparedSend(
            compiled: compiled,
            lifetime: lifetime,
            tokenContext: tokenContext,
            networkFee: networkFee,
            priorityFee: priorityFee.priceMicroLamports,
            priorityFeeCap: priorityFee.capMicroLamports,
            priorityFeeWasCapped: priorityFee.wasCapped,
            computeUnitLimit: computeUnitLimit,
            finalSimulation: simulation,
            minContextSlot: latest.contextSlot,
            instructions: finalMessage.instructions)
    }

    static func computeUnitLimit(from unitsConsumed: UInt64) -> UInt32 {
        let padded = (unitsConsumed * 11 + 9) / 10
        let clamped = min(max(padded, 25_000), 1_400_000)
        return UInt32(clamped)
    }

    func makeReviewDetails(
        request: SendRequest,
        tokenContext: TokenSendContext?,
        prepared: PreparedSend,
        placeholderBytes: Int) -> TransactionReviewDetails
    {
        let (_, lastValidBlockHeight) = self.unwrap(lifetime: prepared.lifetime)
        let baseFee = Lamports(rawValue: UInt64(prepared.compiled.signerAddresses.count) * 5000)
        let priorityFeeLamports = Lamports(rawValue: prepared.networkFee.rawValue - baseFee.rawValue)
        let simulationStatus = prepared.finalSimulation.errorString == nil ? "Simulation passed" : "Simulation failed"
        let logs = prepared.finalSimulation.logs.map(Self.sanitizeLog)
        return TransactionReviewDetails(
            feePayer: request.from,
            cluster: self.network,
            recipient: request.recipient,
            tokenMint: tokenContext?.mint,
            tokenProgram: tokenContext?.tokenProgram,
            instructions: prepared.instructions.map(Self.summarizeInstruction),
            computeUnitLimit: prepared.computeUnitLimit,
            priorityFeeMicroLamports: prepared.priorityFee,
            priorityFeeCapMicroLamports: prepared.priorityFeeCap,
            priorityFeeWasCapped: prepared.priorityFeeWasCapped,
            priorityFeeLamports: priorityFeeLamports,
            baseFeeLamports: baseFee,
            lastValidBlockHeight: lastValidBlockHeight,
            simulationStatus: "\(simulationStatus), \(placeholderBytes) bytes",
            sanitizedLogs: logs,
            solanaPay: request.solanaPay)
    }

    func makeQuoteShapeDigest(
        request: SendRequest,
        tokenContext: TokenSendContext?,
        prepared: PreparedSend,
        recipientReceives: SendAsset) -> QuoteShapeDigest
    {
        QuoteShapeDigest(
            recipient: request.recipient,
            asset: request.asset,
            solanaPayMemo: request.solanaPay?.memo,
            solanaPayReferences: request.solanaPay?.references ?? [],
            tokenProgram: tokenContext?.tokenProgram,
            recipientAtaWillBeCreated: tokenContext?.recipientAtaWillBeCreated ?? false,
            rentForRecipientAta: tokenContext?.recipientAtaWillBeCreated == true
                ? self.config.ataRentLamports
                : Lamports(rawValue: 0),
            recipientReceives: recipientReceives,
            instructions: prepared.instructions.map {
                QuoteShapeDigest.InstructionShape(
                    programAddress: $0.programAddress,
                    accountCount: $0.accounts.count)
            })
    }

    static func validateRecipient(_ recipient: WalletAddress, asset: SendAsset) throws {
        let knownPrograms: [WalletAddress] = [
            ProgramAddresses.system,
            ProgramAddresses.token,
            ProgramAddresses.token2022,
            ProgramAddresses.associatedToken,
            ProgramAddresses.computeBudget,
            ProgramAddresses.memo,
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
            let raw = try mintAccount.validatedBase64Bytes(
                expectedOwner: tokenProgram.base58,
                allowExecutable: false,
                minimumLength: TokenMint.size)
            let legacyProfile = try TokenMint.parse(raw)
            mintProfile = Token2022MintProfile(
                compatibility: .ok,
                decimals: legacyProfile.decimals,
                transferFee: nil,
                permanentDelegate: false)
        case ProgramAddresses.token2022.base58:
            tokenProgram = ProgramAddresses.token2022
            let raw = try mintAccount.validatedBase64Bytes(
                expectedOwner: tokenProgram.base58,
                allowExecutable: false,
                minimumLength: TokenMint.size)
            let currentEpoch = try await fetchCurrentEpoch()
            mintProfile = try Token2022Mint.parse(raw, currentEpoch: currentEpoch)
        default:
            throw SendError.mintOwnedByUnknownProgram(owner: mintAccount.owner)
        }

        if case let .refused(reason) = mintProfile.compatibility {
            throw SendError.unsupportedToken2022Extension(reason: reason)
        }
        guard mintProfile.decimals == decimals else {
            throw SendError.mintDecimalsMismatch(expected: decimals, actual: mintProfile.decimals)
        }

        // 2. Derive sender + recipient ATA against the discovered token program.
        let senderAta = try AssociatedTokenProgram.findAssociatedTokenAddress(
            owner: sender, mint: mint, tokenProgram: tokenProgram)
        let recipientAta = try AssociatedTokenProgram.findAssociatedTokenAddress(
            owner: recipient, mint: mint, tokenProgram: tokenProgram)

        let senderAccount = try await fetchAccount(address: senderAta)
        guard let senderAccount else { throw SendError.tokenAccountNotFound }
        let senderBytes = try senderAccount.validatedBase64Bytes(
            expectedOwner: tokenProgram.base58,
            allowExecutable: false,
            minimumLength: TokenAccount.baseSize)
        let senderProfile = try TokenAccount.parse(senderBytes)
        try Self.validateTokenAccount(senderProfile, mint: mint, owner: sender, amount: amount)

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
        let references = request.solanaPay?.references ?? []
        switch request.asset {
        case let .sol(amount):
            instructions.append(SystemProgram.transferSol(
                from: request.from,
                to: request.recipient,
                lamports: amount,
                references: references))
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
                    amount: ctx.amount, decimals: ctx.decimals, fee: fee.fee(for: ctx.amount),
                    references: references))
            } else if ctx.tokenProgram == ProgramAddresses.token2022 {
                instructions.append(Token2022Program.transferChecked(
                    source: ctx.senderAta, mint: ctx.mint, destination: ctx.recipientAta, owner: request.from,
                    amount: ctx.amount, decimals: ctx.decimals, references: references))
            } else {
                instructions.append(TokenProgram.transferChecked(
                    source: ctx.senderAta, mint: ctx.mint, destination: ctx.recipientAta, owner: request.from,
                    amount: ctx.amount, decimals: ctx.decimals, references: references))
            }
        }
        if let memo = request.solanaPay?.memo, !memo.isEmpty {
            instructions.append(MemoProgram.memo(memo))
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

    static func validateTokenAccount(
        _ account: TokenAccountProfile,
        mint: WalletAddress,
        owner: WalletAddress,
        amount: UInt64) throws
    {
        guard account.mint == mint else {
            throw SendError.tokenAccountInvalid(reason: "Token account mint does not match.")
        }
        guard account.owner == owner else {
            throw SendError.tokenAccountInvalid(reason: "Token account owner does not match.")
        }
        guard account.state == .initialized else {
            throw SendError.tokenAccountInvalid(reason: "Token account is not initialized.")
        }
        if case let .refused(reason) = account.compatibility {
            throw SendError.unsupportedToken2022Extension(reason: reason)
        }
        guard account.amount >= amount else {
            throw SendError.tokenAccountInvalid(reason: "Token account balance is too low.")
        }
    }

    static func summarizeInstruction(_ instruction: Instruction) -> TransactionReviewDetails.InstructionSummary {
        let name: String
        switch instruction.programAddress {
        case ProgramAddresses.computeBudget:
            name = instruction.data.first == 2 ? "Set compute unit limit" : "Set compute unit price"
        case ProgramAddresses.system:
            name = "Transfer SOL"
        case ProgramAddresses.associatedToken:
            name = "Create recipient token account"
        case ProgramAddresses.token:
            name = "Transfer token"
        case ProgramAddresses.token2022:
            name = "Transfer Token-2022"
        case ProgramAddresses.memo:
            name = "Attach memo"
        default:
            name = "Invoke program"
        }
        return TransactionReviewDetails.InstructionSummary(program: instruction.programAddress, name: name)
    }

    static func sanitizeLog(_ log: String) -> String {
        let trimmed = log.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count > 240 else { return trimmed }
        return String(trimmed.prefix(237)) + "..."
    }

    // MARK: - Private: RPC helpers

    private func fetchLatestBlockhash() async throws -> (
        blockhash: Blockhash,
        lastValidBlockHeight: UInt64,
        contextSlot: UInt64)
    {
        let req = LatestBlockhashRPC.request()
        let resp: JSONRPCResponse<LatestBlockhashRPC.Result> = try await transport.send(
            req, responseType: JSONRPCResponse<LatestBlockhashRPC.Result>.self)
        let result = try resp.unwrap()
        let blockhash = try Blockhash(base58: result.value.blockhash)
        return (blockhash, result.value.lastValidBlockHeight, result.context.slot)
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
        try await self.fetchEpochInfo().epoch
    }

    private func fetchEpochInfo() async throws -> EpochInfoRPC.Result {
        let req = EpochInfoRPC.request()
        let resp: JSONRPCResponse<EpochInfoRPC.Result> = try await transport.send(
            req, responseType: JSONRPCResponse<EpochInfoRPC.Result>.self)
        return try resp.unwrap()
    }

    struct PriorityFeeSelection {
        let priceMicroLamports: UInt64
        let capMicroLamports: UInt64
        let wasCapped: Bool
    }

    private func fetchPriorityFee(writableAccounts: [String], tier: PriorityTier) async throws -> PriorityFeeSelection {
        let req = RecentPrioritizationFeesRPC.request(accountAddresses: writableAccounts)
        let resp: JSONRPCResponse<RecentPrioritizationFeesRPC.Result> = try await transport.send(
            req, responseType: JSONRPCResponse<RecentPrioritizationFeesRPC.Result>.self)
        let raw = try resp.unwrap()
        let maxSlot = raw.map(\.slot).max() ?? 0
        let minSlot = maxSlot > self.config.priorityFeeRecentSlotWindow
            ? maxSlot - self.config.priorityFeeRecentSlotWindow
            : 0
        var fees = raw
            .filter { $0.slot >= minSlot }
            .map(\.prioritizationFee)
            .sorted()
        guard !fees.isEmpty else {
            return PriorityFeeSelection(
                priceMicroLamports: self.config.priorityFeeFloorMicroLamports,
                capMicroLamports: self.config.priorityFeeCapMicroLamports,
                wasCapped: false)
        }
        if fees.count >= 5 {
            let median = fees[fees.count / 2]
            let cap = max(
                self.config.priorityFeeCapMicroLamports,
                median.saturatingMultiplied(by: self.config.priorityFeeOutlierMultiplier))
            fees = fees.filter { $0 <= cap }
        }
        let index = max(0, min(fees.count - 1, Int(Double(fees.count) * tier.percentile)))
        let selected = max(fees[index], self.config.priorityFeeFloorMicroLamports)
        let capped = min(selected, self.config.priorityFeeCapMicroLamports)
        return PriorityFeeSelection(
            priceMicroLamports: capped,
            capMicroLamports: self.config.priorityFeeCapMicroLamports,
            wasCapped: selected > self.config.priorityFeeCapMicroLamports)
    }

    // MARK: - Private: simulation

    private func simulateForCompute(_ compiled: CompiledMessage, minContextSlot: UInt64) async throws -> UInt64 {
        let placeholder = try MessageCompiler.placeholderTransaction(for: compiled)
        let base64 = placeholder.wireBytes.base64EncodedString()
        let outcome = try await runSimulation(base64: base64, minContextSlot: minContextSlot)
        if let err = outcome.errorString {
            throw SendError.simulationFailed(logs: outcome.logs, error: err)
        }
        return outcome.unitsConsumed ?? 200_000
    }

    private func simulateForSafety(_ compiled: CompiledMessage, minContextSlot: UInt64) async throws -> SimulationOutcome {
        let placeholder = try MessageCompiler.placeholderTransaction(for: compiled)
        let base64 = placeholder.wireBytes.base64EncodedString()
        return try await self.runSimulation(base64: base64, minContextSlot: minContextSlot)
    }

    private func runSimulation(base64: String, minContextSlot: UInt64) async throws -> SimulationOutcome {
        let req = SimulateTransactionRPC.request(
            base64Transaction: base64,
            minContextSlot: minContextSlot)
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
        let confirmationConfig = TransactionConfirmation.Config(
            commitment: .confirmed,
            pollInterval: self.config.pollInterval,
            timeout: .seconds(self.config.confirmationTimeoutSeconds))
        let transport = self.transport
        let clock = self.clock
        let timeoutSeconds = self.config.confirmationTimeoutSeconds
        do {
            let outcome: TransactionConfirmation.Outcome? = try await withThrowingTaskGroup(
                of: TransactionConfirmation.Outcome?.self)
            { group in
                group.addTask {
                    try await TransactionConfirmation.waitForRecentTransaction(
                        signatureBase58: signature.base58,
                        lastValidBlockHeight: lastValidBlockHeight,
                        transport: transport,
                        clock: clock,
                        config: confirmationConfig)
                }
                group.addTask {
                    try await clock.sleep(for: .seconds(timeoutSeconds))
                    return nil
                }
                defer { group.cancelAll() }
                while let next = try await group.next() {
                    if let outcome = next { return outcome }
                    return nil
                }
                return nil
            }
            guard let outcome else {
                return .stillPending(signature)
            }
            await self.pendingStore.remove(signatureBase58: signature.base58)
            switch outcome.status {
            case let .confirmed(slot):
                return .confirmed(signature, slot: slot)
            case let .failed(error):
                return .failed(signature, error: error)
            case .expired:
                return .expired(signature)
            }
        } catch is CancellationError {
            throw SendError.canceled
        } catch let error as RPCError {
            throw SendError.rpc(Self.mapRPCError(error))
        }
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

    static func shouldRetainPending(after error: RPCError) -> Bool {
        switch error {
        case .canceled:
            return false
        case let .http(status, _):
            return (500..<600).contains(status)
        case let .transport(code):
            switch code {
            case .userAuthenticationRequired, .userCancelledAuthentication:
                return false
            default:
                return true
            }
        case .decoding:
            return true
        case .rpc:
            return false
        }
    }
}

private extension UInt64 {
    func saturatingMultiplied(by rhs: UInt64) -> UInt64 {
        let product = self.multipliedFullWidth(by: rhs)
        return product.high == 0 ? product.low : UInt64.max
    }
}
