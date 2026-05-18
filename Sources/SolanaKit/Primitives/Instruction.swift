import Foundation
import Kit

/// A single program invocation inside a Solana transaction.
///
/// Mirrors `Instruction` from `@solana/kit`'s `packages/instructions`. The
/// triple `(programAddress, accounts, data)` is the entire wire-format input
/// for an on-chain program call; everything else (signers, blockhash, fee
/// payer) lives on the surrounding `TransactionMessage`.
public struct Instruction: Hashable, Sendable {
    public let kitInstruction: Kit.Instruction

    public var programAddress: WalletAddress {
        WalletAddress(address: self.kitInstruction.programAddress)
    }

    public var accounts: [AccountMeta] {
        (self.kitInstruction.accounts ?? []).compactMap { account in
            switch account {
            case let .account(meta):
                AccountMeta(kitMeta: meta)
            case .lookup:
                nil
            }
        }
    }

    public var data: Data {
        self.kitInstruction.data ?? Data()
    }

    public init(programAddress: WalletAddress, accounts: [AccountMeta], data: Data) {
        self.kitInstruction = Kit.Instruction(
            programAddress: programAddress.address,
            accounts: accounts.map(\.kitAccount),
            data: data)
    }

    public init(kitInstruction: Kit.Instruction) {
        self.kitInstruction = kitInstruction
    }
}
