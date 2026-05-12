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

    public init(walletId: UUID, from: WalletAddress, recipient: WalletAddress, asset: SendAsset) {
        self.walletId = walletId
        self.from = from
        self.recipient = recipient
        self.asset = asset
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

    /// The canonical V0 message bytes the user is being asked to sign. Stable
    /// between `quote` and `send` for the same SendRequest.
    public let signableMessage: Data

    /// Blockhash + last valid block height used to bound this transaction.
    public let lifetime: Lifetime

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
        signableMessage: Data,
        lifetime: Lifetime)
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
        self.signableMessage = signableMessage
        self.lifetime = lifetime
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
    case mintOwnedByUnknownProgram(owner: String)
    case simulationFailed(logs: [String], error: String)
    case transactionTooLarge(bytes: Int)
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
}
