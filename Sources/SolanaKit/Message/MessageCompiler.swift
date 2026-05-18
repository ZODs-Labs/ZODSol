import Foundation
import Kit

/// Adapter around swift-solana-kit's transaction compiler.
public enum MessageCompiler {
    public enum CompileError: Error, Sendable, Equatable {
        /// Account count exceeded the current v0 static-account limit.
        case tooManyAccounts(Int)
        /// Signer count exceeded the packet-level signature limit.
        case tooManySigners(Int)
        /// Instruction count exceeded the runtime instruction trace limit.
        case tooManyInstructions(Int)
        /// An instruction's `accounts` list exceeded UInt16.max.
        case tooManyAccountsInInstruction(Int)
        /// Instruction data exceeded UInt16.max bytes.
        case instructionDataTooLong(Int)
        /// Caller passed signatures whose count does not match the compiled
        /// message's required signer count.
        case signatureCountMismatch(expected: Int, got: Int)
        /// Failed to base58-decode a 32-byte account key (corrupt input).
        case malformedAccountKey
    }

    public static func compile(_ message: TransactionMessage) throws -> CompiledMessage {
        try self.validateAppLimits(message)
        let kitMessage = message.kitMessage
        let compiled = try Kit.compileTransactionMessage(kitMessage)
        let transaction = try Kit.compileTransaction(kitMessage)
        let staticAccounts: [Kit.Address]
        let signerCount: Int
        switch compiled {
        case let .legacy(legacy):
            staticAccounts = legacy.staticAccounts
            signerCount = legacy.header.numSignerAccounts
        case let .v0(v0):
            staticAccounts = v0.staticAccounts
            signerCount = v0.header.numSignerAccounts
        case let .v1(v1):
            staticAccounts = v1.staticAccounts
            signerCount = v1.header.numSignerAccounts
        }
        return CompiledMessage(
            messageBytes: transaction.messageBytes,
            signerAddresses: staticAccounts.prefix(signerCount).map(WalletAddress.init(address:)),
            accountKeys: staticAccounts.map(WalletAddress.init(address:)),
            lifetimeConstraint: transaction.lifetimeConstraint)
    }

    private static func validateAppLimits(_ message: TransactionMessage) throws {
        guard message.instructions.count <= 64 else {
            throw CompileError.tooManyInstructions(message.instructions.count)
        }
        var accounts: Set<WalletAddress> = [message.feePayer]
        var signers: Set<WalletAddress> = [message.feePayer]
        for instruction in message.instructions {
            accounts.insert(instruction.programAddress)
            guard instruction.accounts.count <= Int(UInt16.max) else {
                throw CompileError.tooManyAccountsInInstruction(instruction.accounts.count)
            }
            guard instruction.data.count <= Int(UInt16.max) else {
                throw CompileError.instructionDataTooLong(instruction.data.count)
            }
            for account in instruction.accounts {
                accounts.insert(account.pubkey)
                if account.isSigner {
                    signers.insert(account.pubkey)
                }
            }
        }
        guard accounts.count <= 64 else {
            throw CompileError.tooManyAccounts(accounts.count)
        }
        guard signers.count <= 12 else {
            throw CompileError.tooManySigners(signers.count)
        }
    }

    /// Build a `CompiledTransaction` whose signatures are all 64 zero bytes.
    /// Useful for `simulateTransaction` with `sigVerify=false`, which only
    /// requires the transaction to be syntactically valid (correct number of
    /// signature slots).
    public static func placeholderTransaction(for message: CompiledMessage) throws -> CompiledTransaction {
        let zeros = try Signature(bytes: Data(count: 64))
        let signatures = Array(repeating: zeros, count: message.signerAddresses.count)
        return try CompiledTransaction(message: message, signatures: signatures)
    }
}
