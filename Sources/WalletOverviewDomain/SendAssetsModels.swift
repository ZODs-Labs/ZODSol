import Foundation
import SolanaKit

/// What the user is sending.
public enum SendAsset: Sendable, Equatable {
    case sol(amount: Lamports)
    /// SPL token transfer. The orchestrator re-discovers the mint's owning
    /// program from `getAccountInfo(mint)` regardless of what's in the local
    /// asset summary — never trust a cached token-program value across a
    /// security-relevant boundary.
    case splToken(mint: WalletAddress, amount: UInt64, decimals: UInt8)
}

/// Priority-fee tier selected on the confirm screen. Maps to a percentile of
/// recent prioritization fees - higher tier means a more aggressive bid for
/// inclusion. The `.fast` tier preserves the historical default.
public enum PriorityTier: String, Sendable, Codable, CaseIterable, Equatable {
    case standard
    case fast
    case turbo

    public var percentile: Double {
        switch self {
        case .standard: 0.50
        case .fast: 0.75
        case .turbo: 0.95
        }
    }
}

/// Request to quote and (later) execute a transfer.
public struct SendRequest: Sendable, Equatable {
    public let walletId: UUID
    public let from: WalletAddress
    public let recipient: WalletAddress
    public let asset: SendAsset
    public let solanaPay: SolanaPayTransferContext?

    public init(
        walletId: UUID,
        from: WalletAddress,
        recipient: WalletAddress,
        asset: SendAsset,
        solanaPay: SolanaPayTransferContext? = nil)
    {
        self.walletId = walletId
        self.from = from
        self.recipient = recipient
        self.asset = asset
        self.solanaPay = solanaPay
    }
}

public struct SolanaPayTransferContext: Sendable, Equatable {
    public let label: String?
    public let message: String?
    public let memo: String?
    public let references: [WalletAddress]

    public init(label: String?, message: String?, memo: String?, references: [WalletAddress]) {
        self.label = label
        self.message = message
        self.memo = memo
        self.references = references
    }
}

public struct TransactionReviewDetails: Sendable, Equatable {
    public struct InstructionSummary: Sendable, Equatable {
        public let program: WalletAddress
        public let name: String

        public init(program: WalletAddress, name: String) {
            self.program = program
            self.name = name
        }
    }

    public let feePayer: WalletAddress
    public let cluster: SolanaNetwork
    public let recipient: WalletAddress
    public let tokenMint: WalletAddress?
    public let tokenProgram: WalletAddress?
    public let instructions: [InstructionSummary]
    public let computeUnitLimit: UInt32
    public let priorityFeeMicroLamports: UInt64
    public let priorityFeeCapMicroLamports: UInt64
    public let priorityFeeWasCapped: Bool
    public let priorityFeeLamports: Lamports
    public let baseFeeLamports: Lamports
    public let lastValidBlockHeight: UInt64
    public let simulationStatus: String
    public let sanitizedLogs: [String]
    public let solanaPay: SolanaPayTransferContext?

    public init(
        feePayer: WalletAddress,
        cluster: SolanaNetwork,
        recipient: WalletAddress,
        tokenMint: WalletAddress?,
        tokenProgram: WalletAddress?,
        instructions: [InstructionSummary],
        computeUnitLimit: UInt32,
        priorityFeeMicroLamports: UInt64,
        priorityFeeCapMicroLamports: UInt64,
        priorityFeeWasCapped: Bool,
        priorityFeeLamports: Lamports,
        baseFeeLamports: Lamports,
        lastValidBlockHeight: UInt64,
        simulationStatus: String,
        sanitizedLogs: [String],
        solanaPay: SolanaPayTransferContext?)
    {
        self.feePayer = feePayer
        self.cluster = cluster
        self.recipient = recipient
        self.tokenMint = tokenMint
        self.tokenProgram = tokenProgram
        self.instructions = instructions
        self.computeUnitLimit = computeUnitLimit
        self.priorityFeeMicroLamports = priorityFeeMicroLamports
        self.priorityFeeCapMicroLamports = priorityFeeCapMicroLamports
        self.priorityFeeWasCapped = priorityFeeWasCapped
        self.priorityFeeLamports = priorityFeeLamports
        self.baseFeeLamports = baseFeeLamports
        self.lastValidBlockHeight = lastValidBlockHeight
        self.simulationStatus = simulationStatus
        self.sanitizedLogs = sanitizedLogs
        self.solanaPay = solanaPay
    }
}

public struct QuoteShapeDigest: Sendable, Equatable {
    public struct InstructionShape: Sendable, Equatable {
        public let programAddress: WalletAddress
        public let accountCount: Int

        public init(programAddress: WalletAddress, accountCount: Int) {
            self.programAddress = programAddress
            self.accountCount = accountCount
        }
    }

    public let recipient: WalletAddress
    public let asset: SendAsset
    public let solanaPayMemo: String?
    public let solanaPayReferences: [WalletAddress]
    public let tokenProgram: WalletAddress?
    public let recipientAtaWillBeCreated: Bool
    public let rentForRecipientAta: Lamports
    public let recipientReceives: SendAsset
    public let instructions: [InstructionShape]

    public init(
        recipient: WalletAddress,
        asset: SendAsset,
        solanaPayMemo: String?,
        solanaPayReferences: [WalletAddress],
        tokenProgram: WalletAddress?,
        recipientAtaWillBeCreated: Bool,
        rentForRecipientAta: Lamports,
        recipientReceives: SendAsset,
        instructions: [InstructionShape])
    {
        self.recipient = recipient
        self.asset = asset
        self.solanaPayMemo = solanaPayMemo
        self.solanaPayReferences = solanaPayReferences
        self.tokenProgram = tokenProgram
        self.recipientAtaWillBeCreated = recipientAtaWillBeCreated
        self.rentForRecipientAta = rentForRecipientAta
        self.recipientReceives = recipientReceives
        self.instructions = instructions
    }

    public func firstDifference(from other: QuoteShapeDigest) -> String? {
        if self.recipient != other.recipient { return "recipient" }
        if self.asset != other.asset { return "asset" }
        if self.solanaPayMemo != other.solanaPayMemo { return "Solana Pay memo" }
        if self.solanaPayReferences != other.solanaPayReferences { return "Solana Pay references" }
        if self.tokenProgram != other.tokenProgram { return "token program" }
        if self.recipientAtaWillBeCreated != other.recipientAtaWillBeCreated {
            return "recipient token account"
        }
        if self.rentForRecipientAta != other.rentForRecipientAta { return "recipient token account rent" }
        if self.recipientReceives != other.recipientReceives { return "recipient receive amount" }
        if self.instructions != other.instructions { return "instruction list" }
        return nil
    }
}

/// What the user sees on the confirm screen, and what the service hands back
/// when the user accepts. Carries all the inputs needed to actually sign and
/// broadcast — keep this Sendable so it can cross the actor boundary verbatim.
public struct SendQuote: Sendable, Equatable {
    public let request: SendRequest

    /// Network base fee + priority fee for this transaction, in lamports.
    public let networkFeeLamports: Lamports
    /// Price (microLamports per CU) the orchestrator chose from the recent
    /// percentile. Visible so the UI can warn on unusually high fees.
    public let priorityFeeMicroLamports: UInt64
    /// Compute-unit limit set on the transaction. Derived from simulation × 1.1.
    public let computeUnitLimit: UInt32

    /// `true` if the orchestrator will prepend an idempotent ATA-create.
    public let recipientAtaWillBeCreated: Bool
    /// Rent the sender pays to fund a new recipient ATA. `Lamports(rawValue: 0)`
    /// when no ATA is created.
    public let rentForRecipientAta: Lamports

    /// Token-2022 informational fields. `nil` for SOL or legacy SPL.
    public let token2022Notice: Token2022Notice?

    /// Amount the recipient actually receives, after Token-2022 transfer fee.
    /// Equal to the requested amount for SOL and Token-2022 mints with no fee.
    public let recipientReceives: SendAsset

    /// Network the quote was computed against. Compared against the UI cluster
    /// indicator on the confirm screen — drift here would mean a quote-on-devnet,
    /// send-on-mainnet bug.
    public let cluster: SolanaNetwork

    /// Logs from the (sigVerify=false) simulation that the UI surfaces so the
    /// user can audit what the transaction will do.
    public let simulationLogs: [String]
    public let priorityTier: PriorityTier
    public let reviewDetails: TransactionReviewDetails
    public let shapeDigest: QuoteShapeDigest

    public init(
        request: SendRequest,
        networkFeeLamports: Lamports,
        priorityFeeMicroLamports: UInt64,
        computeUnitLimit: UInt32,
        recipientAtaWillBeCreated: Bool,
        rentForRecipientAta: Lamports,
        token2022Notice: Token2022Notice?,
        recipientReceives: SendAsset,
        cluster: SolanaNetwork,
        simulationLogs: [String],
        priorityTier: PriorityTier,
        reviewDetails: TransactionReviewDetails,
        shapeDigest: QuoteShapeDigest)
    {
        self.request = request
        self.networkFeeLamports = networkFeeLamports
        self.priorityFeeMicroLamports = priorityFeeMicroLamports
        self.computeUnitLimit = computeUnitLimit
        self.recipientAtaWillBeCreated = recipientAtaWillBeCreated
        self.rentForRecipientAta = rentForRecipientAta
        self.token2022Notice = token2022Notice
        self.recipientReceives = recipientReceives
        self.cluster = cluster
        self.simulationLogs = simulationLogs
        self.priorityTier = priorityTier
        self.reviewDetails = reviewDetails
        self.shapeDigest = shapeDigest
    }
}

/// UI-facing summary of the Token-2022 quirks of a mint we are about to send.
public struct Token2022Notice: Sendable, Equatable {
    /// `nil` when no `TransferFeeConfig` (or fee == 0). Otherwise the per-tx
    /// fee in raw token units.
    public let transferFeeAmount: UInt64?
    /// Basis points the transfer fee was computed from, for transparency in
    /// the banner ("This token charges a 1.00% transfer fee").
    public let transferFeeBasisPoints: UInt16?
    /// `true` if the mint has a `PermanentDelegate` set — show a "the issuer
    /// can sweep this token from any account" banner.
    public let permanentDelegate: Bool
}

/// Errors specific to the send pipeline. Each case is something the UI can
/// surface to the user with an actionable message — generic transport errors
/// are wrapped in `.rpc(...)`.
public enum SendError: Error, Sendable, Equatable {
    case invalidRecipient(InvalidRecipientReason)
    case insufficientSolForFee(required: Lamports, available: Lamports)
    case insufficientSolForRent(required: Lamports, available: Lamports)
    case unsupportedToken2022Extension(reason: String)
    case mintNotFound
    case tokenAccountNotFound
    case tokenAccountInvalid(reason: String)
    case mintDecimalsMismatch(expected: UInt8, actual: UInt8)
    case mintOwnedByUnknownProgram(owner: String)
    case simulationFailed(logs: [String], error: String)
    case transactionTooLarge(bytes: Int)
    case quoteExpired(changedField: String)
    case canceled
    case walletAddressMismatch
    case rpc(SolanaProviderError)
    /// Returned when `send` is called twice for the same wallet without the
    /// previous send finishing.
    case sendAlreadyInFlight
    /// The broadcast itself failed (network drop, RPC error). The signature
    /// is removed from PendingSendStore.
    case broadcastFailed(reason: String)
}

public enum InvalidRecipientReason: Sendable, Equatable {
    /// SOL transfer to an off-curve address (a PDA). Refused — lamports would
    /// be unrecoverable.
    case offCurveForSol
    /// Recipient matches a known on-chain program ID (System, Token, ATA,
    /// ComputeBudget). Always a mistake.
    case knownProgramAddress
    /// Recipient base58 didn't decode to 32 bytes (caught at `WalletAddress` init).
    case malformed
}

/// Resolution of a single send attempt.
public enum SendOutcome: Sendable, Equatable {
    /// Transaction reached `confirmed` or `finalized`.
    case confirmed(Signature, slot: UInt64)
    /// Blockhash window passed without a confirmation. Signature is dropped
    /// from the pending store; user may retry.
    case expired(Signature)
    /// On-chain failure (e.g. preflight passed but runtime err). Signature is
    /// dropped from the pending store.
    case failed(Signature, error: String)
    /// The UI patience budget elapsed, but the blockhash window has not closed.
    case stillPending(Signature)
}

public struct PendingSendResolution: Sendable, Equatable {
    public let signature: Signature
    public let outcome: SendOutcome
    public let createdAt: Date

    public init(signature: Signature, outcome: SendOutcome, createdAt: Date) {
        self.signature = signature
        self.outcome = outcome
        self.createdAt = createdAt
    }
}
