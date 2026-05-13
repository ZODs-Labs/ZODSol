import XCTest
@testable import SolanaKit

/// Byte-level tests for the V0 message compiler. Targets the cases most
/// likely to drift: account dedup with mixed privileges, signer ordering,
/// fee-payer-at-index-0, and the exact wire-format byte layout.
final class MessageCompilerTests: XCTestCase {
    private let usdc = try! WalletAddress(base58: "EPjFWdd5AufqSSqeM2qN1xzybapC8G4wEGGkZwyTDt1v")
    private let wsol = try! WalletAddress(base58: "So11111111111111111111111111111111111111112")
    private let systemProgram = try! WalletAddress(base58: "11111111111111111111111111111111")

    private let testBlockhash: Blockhash = try! Blockhash(bytes: Data((0..<32).map { UInt8($0) }))

    // MARK: - End-to-end wire format

    func testSystemTransferProducesCanonicalBytes() throws {
        // Sender = USDC mint (acts as fee payer + signer), recipient = WSOL mint.
        // System transfer instruction: discriminator 2 (u32 LE) + lamports 1 (u64 LE).
        let sender = self.usdc
        let recipient = self.wsol
        let txData = Data([0x02, 0x00, 0x00, 0x00, 0x01, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00])

        let instruction = Instruction(
            programAddress: systemProgram,
            accounts: [
                AccountMeta(pubkey: sender, isSigner: true, isWritable: true),
                AccountMeta(pubkey: recipient, isSigner: false, isWritable: true),
            ],
            data: txData)

        let message = TransactionMessage(
            feePayer: sender,
            instructions: [instruction],
            lifetime: .blockhash(testBlockhash, lastValidBlockHeight: 200))

        let compiled = try MessageCompiler.compile(message)

        // Hand-computed expected layout.
        var expected = Data()
        expected.append(0x80) // V0 version
        expected.append(contentsOf: [0x01, 0x00, 0x01]) // header: 1 sig, 0 ro-signed, 1 ro-unsigned
        expected.append(0x03) // 3 accounts (short_u16)
        try expected.append(Base58.decode(sender.base58)) // index 0: sender (signer, writable)
        try expected.append(Base58.decode(recipient.base58)) // index 1: recipient (writable)
        try expected.append(Base58.decode(self.systemProgram.base58)) // index 2: system program (readonly)
        expected.append(self.testBlockhash.bytes) // blockhash
        expected.append(0x01) // 1 instruction
        expected.append(0x02) // programIdIndex
        expected.append(0x02) // 2 accounts in instruction
        expected.append(contentsOf: [0x00, 0x01]) // sender index, recipient index
        expected.append(0x0C) // 12 bytes data
        expected.append(txData)
        expected.append(0x00) // 0 address table lookups

        XCTAssertEqual(
            compiled.messageBytes,
            expected,
            "Compiled message bytes differ from hand-computed canonical form")
        XCTAssertEqual(compiled.signerAddresses, [sender])
        XCTAssertEqual(compiled.accountKeys, [sender, recipient, self.systemProgram])
    }

    // MARK: - Privilege merge and ordering

    func testPrivilegeMergeAcrossInstructions() throws {
        // Same account referenced twice: readonly in instruction 1, writable+signer
        // in instruction 2. After compile, it must be in the writable-signer group.
        let signerKey = try makeRandomAddress(seed: 0xAA)
        let sharedKey = try makeRandomAddress(seed: 0xBB)
        let programA = try makeRandomAddress(seed: 0xCC)
        let programB = try makeRandomAddress(seed: 0xDD)

        let ix1 = Instruction(
            programAddress: programA,
            accounts: [AccountMeta(pubkey: sharedKey, isSigner: false, isWritable: false)],
            data: Data([0xFF]))
        let ix2 = Instruction(
            programAddress: programB,
            accounts: [AccountMeta(pubkey: sharedKey, isSigner: true, isWritable: true)],
            data: Data([0xEE]))

        let compiled = try MessageCompiler.compile(TransactionMessage(
            feePayer: signerKey,
            instructions: [ix1, ix2],
            lifetime: .blockhash(self.testBlockhash, lastValidBlockHeight: 100)))

        // Account order: [signerKey (fee payer, writable+signer), sharedKey (writable+signer
        // after merge), programA (readonly non-signer), programB (readonly non-signer)].
        XCTAssertEqual(compiled.accountKeys, [signerKey, sharedKey, programA, programB])
        XCTAssertEqual(compiled.signerAddresses, [signerKey, sharedKey])
    }

    func testFeePayerForcedToIndexZero() throws {
        // Fee payer is referenced by the instruction as a readonly account; the
        // compiler must still hoist it to index 0 with full signer+writable privileges.
        let feePayer = try makeRandomAddress(seed: 0x01)
        let program = try makeRandomAddress(seed: 0x02)

        let ix = Instruction(
            programAddress: program,
            accounts: [
                AccountMeta(pubkey: feePayer, isSigner: false, isWritable: false),
            ],
            data: Data())

        let compiled = try MessageCompiler.compile(TransactionMessage(
            feePayer: feePayer,
            instructions: [ix],
            lifetime: .blockhash(self.testBlockhash, lastValidBlockHeight: 1)))

        XCTAssertEqual(compiled.accountKeys.first, feePayer)
        XCTAssertEqual(compiled.signerAddresses, [feePayer])
        // Header byte 0 (numRequiredSignatures) at offset 1 = 1.
        XCTAssertEqual(compiled.messageBytes[1], 0x01)
        // Header byte 2 (numReadonlyUnsigned) at offset 3 = 1 (program).
        XCTAssertEqual(compiled.messageBytes[3], 0x01)
    }

    // MARK: - CompiledTransaction

    func testCompiledTransactionWireBytesHaveSignaturePrefix() throws {
        let sender = self.usdc
        let ix = Instruction(
            programAddress: systemProgram,
            accounts: [
                AccountMeta(pubkey: sender, isSigner: true, isWritable: true),
                AccountMeta(pubkey: wsol, isSigner: false, isWritable: true),
            ],
            data: Data([0x02, 0x00, 0x00, 0x00, 0x01, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00]))
        let message = try MessageCompiler.compile(TransactionMessage(
            feePayer: sender,
            instructions: [ix],
            lifetime: .blockhash(self.testBlockhash, lastValidBlockHeight: 1)))
        let placeholder = try MessageCompiler.placeholderTransaction(for: message)
        let wire = placeholder.wireBytes

        // wire = short_u16(1) || 64-byte zero sig || messageBytes
        XCTAssertEqual(wire.first, 0x01)
        XCTAssertEqual(wire.count, 1 + 64 + message.messageBytes.count)
        XCTAssertEqual(wire.dropFirst(1).prefix(64), Data(count: 64))
        XCTAssertEqual(wire.dropFirst(1 + 64), message.messageBytes)
    }

    func testCompiledTransactionRejectsWrongSignatureCount() throws {
        let sender = self.usdc
        let message = try MessageCompiler.compile(TransactionMessage(
            feePayer: sender,
            instructions: [
                Instruction(programAddress: self.systemProgram, accounts: [
                    AccountMeta(pubkey: sender, isSigner: true, isWritable: true),
                ], data: Data()),
            ],
            lifetime: .blockhash(self.testBlockhash, lastValidBlockHeight: 1)))
        // Two sigs for one signer must throw.
        XCTAssertThrowsError(try CompiledTransaction(
            message: message,
            signatures: [Signature(bytes: Data(count: 64)), Signature(bytes: Data(count: 64))]))
    }

    func testCompileRejectsTooManySigners() throws {
        let feePayer = try makeRandomAddress(seed: 0x10)
        let program = try makeRandomAddress(seed: 0x11)
        let signers = try (0..<12).map { try makeRandomAddress(seed: UInt8(0x20 + $0)) }
        let instruction = Instruction(
            programAddress: program,
            accounts: signers.map { AccountMeta(pubkey: $0, isSigner: true, isWritable: false) },
            data: Data())
        let message = TransactionMessage(
            feePayer: feePayer,
            instructions: [instruction],
            lifetime: .blockhash(self.testBlockhash, lastValidBlockHeight: 1))

        XCTAssertThrowsError(try MessageCompiler.compile(message)) { error in
            XCTAssertEqual(error as? MessageCompiler.CompileError, .tooManySigners(13))
        }
    }

    func testCompileRejectsTooManyInstructions() throws {
        let feePayer = try makeRandomAddress(seed: 0x30)
        let program = try makeRandomAddress(seed: 0x31)
        let instructions = Array(repeating: Instruction(programAddress: program, accounts: [], data: Data()), count: 65)
        let message = TransactionMessage(
            feePayer: feePayer,
            instructions: instructions,
            lifetime: .blockhash(self.testBlockhash, lastValidBlockHeight: 1))

        XCTAssertThrowsError(try MessageCompiler.compile(message)) { error in
            XCTAssertEqual(error as? MessageCompiler.CompileError, .tooManyInstructions(65))
        }
    }

    // MARK: - Helpers

    /// Build a deterministic 32-byte address from a single seed byte.
    private func makeRandomAddress(seed: UInt8) throws -> WalletAddress {
        var bytes = Data(repeating: seed, count: 32)
        // Vary byte 0 so addresses derived from different seeds differ even when
        // the seed byte equals a recurring fill.
        bytes[0] = seed &+ 1
        return try WalletAddress(base58: Base58.encode(bytes))
    }
}
