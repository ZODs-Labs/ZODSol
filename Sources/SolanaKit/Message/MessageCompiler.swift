import Foundation

/// Compiles a `TransactionMessage` into V0 wire bytes per Solana's compiled-
/// transaction format (account dedup, privilege merge, signer-first ordering,
/// short_vec length prefixes, empty address-table-lookup slot).
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

    /// Compile `message` to V0 wire bytes. Account order:
    /// 1. Writable signers (fee payer first by construction).
    /// 2. Readonly signers.
    /// 3. Writable non-signers.
    /// 4. Readonly non-signers.
    public static func compile(_ message: TransactionMessage) throws -> CompiledMessage {
        let collection = self.collectAccounts(message: message)
        let groups = self.partitionByPrivilege(collection: collection)
        precondition(
            groups.writableSigners.first == message.feePayer,
            "Fee payer must be index 0 of writable signers")

        let accountKeys = groups.writableSigners + groups.readonlySigners
            + groups.writableNonSigners + groups.readonlyNonSigners

        // App cap, below the u8 wire limit, keeps signed packets under Solana's 1232-byte MTU budget.
        guard accountKeys.count <= 64 else {
            throw CompileError.tooManyAccounts(accountKeys.count)
        }
        let signerCount = groups.writableSigners.count + groups.readonlySigners.count
        // Each signer adds a 64-byte signature, so this cap protects the same packet budget.
        guard signerCount <= 12 else {
            throw CompileError.tooManySigners(signerCount)
        }
        // Instruction count is capped with the static-account limit so pathological messages fail early.
        guard message.instructions.count <= 64 else {
            throw CompileError.tooManyInstructions(message.instructions.count)
        }

        let header = MessageHeader(
            numRequiredSignatures: UInt8(groups.writableSigners.count + groups.readonlySigners.count),
            numReadonlySigned: UInt8(groups.readonlySigners.count),
            numReadonlyUnsigned: UInt8(groups.readonlyNonSigners.count))

        let bytes = try encodeBytes(
            message: message,
            header: header,
            accountKeys: accountKeys)

        return CompiledMessage(
            messageBytes: bytes,
            signerAddresses: groups.writableSigners + groups.readonlySigners,
            accountKeys: accountKeys)
    }

    // MARK: - Stage 1: collect accounts in observation order

    private struct AccountCollection {
        let ordered: [WalletAddress]
        let metas: [WalletAddress: AccountMeta]
    }

    private static func collectAccounts(message: TransactionMessage) -> AccountCollection {
        var ordered: [WalletAddress] = []
        var metas: [WalletAddress: AccountMeta] = [:]

        func observe(_ meta: AccountMeta) {
            if let existing = metas[meta.pubkey] {
                metas[meta.pubkey] = existing.mergingPrivileges(with: meta)
            } else {
                metas[meta.pubkey] = meta
                ordered.append(meta.pubkey)
            }
        }

        observe(AccountMeta(pubkey: message.feePayer, isSigner: true, isWritable: true))
        for instruction in message.instructions {
            for accountMeta in instruction.accounts {
                observe(accountMeta)
            }
            observe(AccountMeta(pubkey: instruction.programAddress, isSigner: false, isWritable: false))
        }
        return AccountCollection(ordered: ordered, metas: metas)
    }

    // MARK: - Stage 2: partition into signer/writable groups

    private struct AccountGroups {
        let writableSigners: [WalletAddress]
        let readonlySigners: [WalletAddress]
        let writableNonSigners: [WalletAddress]
        let readonlyNonSigners: [WalletAddress]
    }

    private static func partitionByPrivilege(collection: AccountCollection) -> AccountGroups {
        var writableSigners: [WalletAddress] = []
        var readonlySigners: [WalletAddress] = []
        var writableNonSigners: [WalletAddress] = []
        var readonlyNonSigners: [WalletAddress] = []
        for address in collection.ordered {
            guard let meta = collection.metas[address] else { continue }
            switch (meta.isSigner, meta.isWritable) {
            case (true, true): writableSigners.append(address)
            case (true, false): readonlySigners.append(address)
            case (false, true): writableNonSigners.append(address)
            case (false, false): readonlyNonSigners.append(address)
            }
        }
        return AccountGroups(
            writableSigners: writableSigners,
            readonlySigners: readonlySigners,
            writableNonSigners: writableNonSigners,
            readonlyNonSigners: readonlyNonSigners)
    }

    // MARK: - Stage 4: emit bytes

    private struct MessageHeader {
        let numRequiredSignatures: UInt8
        let numReadonlySigned: UInt8
        let numReadonlyUnsigned: UInt8
    }

    private static func encodeBytes(
        message: TransactionMessage,
        header: MessageHeader,
        accountKeys: [WalletAddress]) throws -> Data
    {
        let blockhashBytes: Data = switch message.lifetime {
        case let .blockhash(blockhash, _):
            blockhash.bytes
        }

        var data = Data()
        data.reserveCapacity(64 + 32 * accountKeys.count + 64 * message.instructions.count)
        data.append(0x80) // V0 version prefix
        data.append(header.numRequiredSignatures)
        data.append(header.numReadonlySigned)
        data.append(header.numReadonlyUnsigned)
        try self.appendAccountKeys(accountKeys, into: &data)
        data.append(blockhashBytes)
        let accountIndex = self.indexMap(accountKeys)
        try self.appendInstructions(message.instructions, accountIndex: accountIndex, into: &data)
        data.append(WireFormat.encodeShortU16(0)) // 0 address-table lookups
        return data
    }

    private static func indexMap(_ accountKeys: [WalletAddress]) -> [WalletAddress: UInt8] {
        var map: [WalletAddress: UInt8] = [:]
        map.reserveCapacity(accountKeys.count)
        for (offset, addr) in accountKeys.enumerated() {
            map[addr] = UInt8(offset)
        }
        return map
    }

    private static func appendAccountKeys(_ accountKeys: [WalletAddress], into data: inout Data) throws {
        data.append(WireFormat.encodeShortU16(UInt16(accountKeys.count)))
        for address in accountKeys {
            let decoded: Data
            do {
                decoded = try Base58.decode(address.base58)
            } catch {
                throw CompileError.malformedAccountKey
            }
            guard decoded.count == 32 else { throw CompileError.malformedAccountKey }
            data.append(decoded)
        }
    }

    private static func appendInstructions(
        _ instructions: [Instruction],
        accountIndex: [WalletAddress: UInt8],
        into data: inout Data) throws
    {
        data.append(WireFormat.encodeShortU16(UInt16(instructions.count)))
        for instruction in instructions {
            guard let programIndex = accountIndex[instruction.programAddress] else {
                throw CompileError.malformedAccountKey
            }
            data.append(programIndex)
            guard instruction.accounts.count <= Int(UInt16.max) else {
                throw CompileError.tooManyAccountsInInstruction(instruction.accounts.count)
            }
            data.append(WireFormat.encodeShortU16(UInt16(instruction.accounts.count)))
            for accountMeta in instruction.accounts {
                guard let idx = accountIndex[accountMeta.pubkey] else {
                    throw CompileError.malformedAccountKey
                }
                data.append(idx)
            }
            guard instruction.data.count <= Int(UInt16.max) else {
                throw CompileError.instructionDataTooLong(instruction.data.count)
            }
            data.append(WireFormat.encodeShortU16(UInt16(instruction.data.count)))
            data.append(instruction.data)
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
