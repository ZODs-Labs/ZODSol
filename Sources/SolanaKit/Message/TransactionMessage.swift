import Foundation
import Kit

/// A versioned-V0 transaction message: the unit that gets compiled, signed,
/// and submitted to the cluster.
///
/// We always produce V0 messages: V0 supports priority-fee compute-budget
/// instructions and is the only format the latest validators emit for new
/// programs. Legacy (pre-V0) messages would refuse our `setComputeUnitPrice`
/// instruction, so the version is fixed.
public struct TransactionMessage: Hashable, Sendable {
    public let feePayer: WalletAddress
    public let instructions: [Instruction]
    public let lifetime: Lifetime

    public init(feePayer: WalletAddress, instructions: [Instruction], lifetime: Lifetime) {
        self.feePayer = feePayer
        self.instructions = instructions
        self.lifetime = lifetime
    }

    public var kitMessage: Kit.TransactionMessage {
        var message = Kit.createTransactionMessage(version: .v0)
        message = Kit.setTransactionMessageFeePayer(self.feePayer.address, message)
        switch self.lifetime {
        case let .blockhash(blockhash, lastValidBlockHeight):
            message = Kit.setTransactionMessageLifetimeUsingBlockhash(
                Kit.BlockhashLifetimeConstraint(
                    blockhash: blockhash.base58,
                    lastValidBlockHeight: lastValidBlockHeight),
                message)
        }
        return Kit.appendTransactionMessageInstructions(
            self.instructions.map(\.kitInstruction),
            message)
    }
}
