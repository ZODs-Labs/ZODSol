import Foundation

/// A single program invocation inside a Solana transaction.
///
/// Mirrors `Instruction` from `@solana/kit`'s `packages/instructions`. The
/// triple `(programAddress, accounts, data)` is the entire wire-format input
/// for an on-chain program call; everything else (signers, blockhash, fee
/// payer) lives on the surrounding `TransactionMessage`.
public struct Instruction: Hashable, Sendable {
    public let programAddress: WalletAddress
    public let accounts: [AccountMeta]
    public let data: Data

    public init(programAddress: WalletAddress, accounts: [AccountMeta], data: Data) {
        self.programAddress = programAddress
        self.accounts = accounts
        self.data = data
    }
}
