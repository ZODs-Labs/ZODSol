import XCTest
@testable import SolanaKit

final class ProgramsTests: XCTestCase {
    private let alice = try! WalletAddress(base58: "EPjFWdd5AufqSSqeM2qN1xzybapC8G4wEGGkZwyTDt1v")
    private let bob = try! WalletAddress(base58: "So11111111111111111111111111111111111111112")
    private let mint = try! WalletAddress(base58: "USDH1SM1ojwWUga67PGrgFWUHibbjqMvuMaDkRJTgkX")

    // MARK: - ProgramAddresses

    func testProgramAddressesAllDecodeTo32Bytes() throws {
        for address in [
            ProgramAddresses.system,
            ProgramAddresses.token,
            ProgramAddresses.token2022,
            ProgramAddresses.associatedToken,
            ProgramAddresses.computeBudget,
        ] {
            XCTAssertEqual(try Base58.decode(address.base58).count, 32, "\(address) wrong length")
        }
    }

    // MARK: - SystemProgram

    func testSystemTransferSolByteLayout() {
        let ix = SystemProgram.transferSol(
            from: self.alice,
            to: self.bob,
            lamports: Lamports(rawValue: 0x0102_0304_0506_0708))
        // Discriminator 2 (u32 LE) + lamports (u64 LE).
        XCTAssertEqual(ix.data, Data([
            0x02, 0x00, 0x00, 0x00,
            0x08, 0x07, 0x06, 0x05, 0x04, 0x03, 0x02, 0x01,
        ]))
        XCTAssertEqual(ix.programAddress, ProgramAddresses.system)
        XCTAssertEqual(ix.accounts.count, 2)
        XCTAssertEqual(ix.accounts[0], AccountMeta(pubkey: self.alice, isSigner: true, isWritable: true))
        XCTAssertEqual(ix.accounts[1], AccountMeta(pubkey: self.bob, isSigner: false, isWritable: true))
    }

    // MARK: - TokenProgram (legacy)

    func testTokenTransferCheckedByteLayout() throws {
        let owner = self.alice
        let source = try WalletAddress(base58: "EPjFWdd5AufqSSqeM2qN1xzybapC8G4wEGGkZwyTDt1v")
        let destination = try WalletAddress(base58: "So11111111111111111111111111111111111111112")
        let ix = TokenProgram.transferChecked(
            source: source,
            mint: self.mint,
            destination: destination,
            owner: owner,
            amount: 1_500_000,
            decimals: 6)
        // Discriminator 12 + u64 LE amount + u8 decimals.
        // 1_500_000 = 0x0016E360 → LE bytes: 0x60, 0xE3, 0x16, 0x00, ...
        XCTAssertEqual(ix.data, Data([
            0x0C,
            0x60, 0xE3, 0x16, 0x00, 0x00, 0x00, 0x00, 0x00,
            0x06,
        ]))
        XCTAssertEqual(ix.programAddress, ProgramAddresses.token)
        XCTAssertEqual(ix.accounts.map(\.pubkey), [source, self.mint, destination, owner])
        XCTAssertEqual(ix.accounts[0].isWritable, true)
        XCTAssertEqual(ix.accounts[0].isSigner, false)
        XCTAssertEqual(ix.accounts[1].isWritable, false) // mint readonly
        XCTAssertEqual(ix.accounts[2].isWritable, true) // destination writable
        XCTAssertEqual(ix.accounts[3].isSigner, true) // owner signs
        XCTAssertEqual(ix.accounts[3].isWritable, false)
    }

    // MARK: - Token2022Program

    func testToken2022TransferCheckedByteLayoutMatchesLegacy() {
        let owner = self.alice
        let source = self.bob
        let destination = self.mint
        let legacyIx = TokenProgram.transferChecked(
            source: source, mint: self.mint, destination: destination, owner: owner,
            amount: 42, decimals: 6)
        let extIx = Token2022Program.transferChecked(
            source: source, mint: self.mint, destination: destination, owner: owner,
            amount: 42, decimals: 6)
        XCTAssertEqual(legacyIx.data, extIx.data, "transferChecked data shape must be identical across token programs")
        XCTAssertEqual(legacyIx.accounts, extIx.accounts)
        XCTAssertNotEqual(legacyIx.programAddress, extIx.programAddress)
        XCTAssertEqual(extIx.programAddress, ProgramAddresses.token2022)
    }

    func testToken2022TransferCheckedWithFeeByteLayout() {
        let ix = Token2022Program.transferCheckedWithFee(
            source: self.bob, mint: self.mint, destination: self.alice, owner: self.alice,
            amount: 100_000, decimals: 6, fee: 1000)
        // 0x1A (TransferFeeExtension) + 0x01 (TransferCheckedWithFee) + u64 amount + u8 decimals + u64 fee.
        XCTAssertEqual(ix.data, Data([
            0x1A, 0x01,
            0xA0, 0x86, 0x01, 0x00, 0x00, 0x00, 0x00, 0x00, // 100_000 LE
            0x06,
            0xE8, 0x03, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, // 1_000 LE
        ]))
        XCTAssertEqual(ix.programAddress, ProgramAddresses.token2022)
    }

    // MARK: - AssociatedTokenProgram

    func testAtaDerivationIsDeterministic() throws {
        let a = try AssociatedTokenProgram.findAssociatedTokenAddress(
            owner: self.alice, mint: self.mint, tokenProgram: ProgramAddresses.token)
        let b = try AssociatedTokenProgram.findAssociatedTokenAddress(
            owner: self.alice, mint: self.mint, tokenProgram: ProgramAddresses.token)
        XCTAssertEqual(a, b)
    }

    func testAtaDerivationProducesOffCurveAddress() throws {
        let ata = try AssociatedTokenProgram.findAssociatedTokenAddress(
            owner: self.alice, mint: self.mint, tokenProgram: ProgramAddresses.token)
        XCTAssertFalse(Ed25519Curve.isOnCurve(ata), "ATA must be off-curve")
    }

    func testAtaDerivationDiffersByTokenProgram() throws {
        // Same owner + mint, different token program → different ATA. This is
        // the bug that bit solana-agent-kit; we test it explicitly to keep it
        // from regressing.
        let legacyAta = try AssociatedTokenProgram.findAssociatedTokenAddress(
            owner: self.alice, mint: self.mint, tokenProgram: ProgramAddresses.token)
        let extAta = try AssociatedTokenProgram.findAssociatedTokenAddress(
            owner: self.alice, mint: self.mint, tokenProgram: ProgramAddresses.token2022)
        XCTAssertNotEqual(legacyAta, extAta)
    }

    func testCreateAssociatedTokenIdempotentInstructionShape() throws {
        let ata = try AssociatedTokenProgram.findAssociatedTokenAddress(
            owner: self.alice, mint: self.mint, tokenProgram: ProgramAddresses.token)
        let ix = AssociatedTokenProgram.createAssociatedTokenIdempotent(
            payer: self.bob, owner: self.alice, mint: self.mint, associatedToken: ata,
            tokenProgram: ProgramAddresses.token)
        // Single-byte discriminator `1` (Create idempotent — not the default 0).
        XCTAssertEqual(ix.data, Data([0x01]))
        XCTAssertEqual(ix.programAddress, ProgramAddresses.associatedToken)
        XCTAssertEqual(ix.accounts.map(\.pubkey), [
            self.bob, ata, self.alice, self.mint, ProgramAddresses.system, ProgramAddresses.token,
        ])
        // Payer signs and is writable.
        XCTAssertTrue(ix.accounts[0].isSigner)
        XCTAssertTrue(ix.accounts[0].isWritable)
        // ATA itself is writable but not a signer.
        XCTAssertFalse(ix.accounts[1].isSigner)
        XCTAssertTrue(ix.accounts[1].isWritable)
        // Owner, mint, system, token are all readonly.
        for index in 2..<ix.accounts.count {
            XCTAssertFalse(ix.accounts[index].isSigner, "account \(index) should not sign")
            XCTAssertFalse(ix.accounts[index].isWritable, "account \(index) should be readonly")
        }
    }

    // MARK: - ComputeBudgetProgram

    func testSetComputeUnitLimitByteLayout() {
        let ix = ComputeBudgetProgram.setComputeUnitLimit(units: 200_000)
        // 0x02 + u32 LE 200_000 = 0x00_03_0D_40 LE -> [0x40, 0x0D, 0x03, 0x00].
        XCTAssertEqual(ix.data, Data([0x02, 0x40, 0x0D, 0x03, 0x00]))
        XCTAssertEqual(ix.programAddress, ProgramAddresses.computeBudget)
        XCTAssertEqual(ix.accounts.count, 0)
    }

    func testSetComputeUnitPriceByteLayout() {
        let ix = ComputeBudgetProgram.setComputeUnitPrice(microLamports: 50000)
        // 0x03 + u64 LE 50_000 = 0x00_00_00_00_00_00_C3_50.
        XCTAssertEqual(ix.data, Data([
            0x03,
            0x50, 0xC3, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00,
        ]))
        XCTAssertEqual(ix.programAddress, ProgramAddresses.computeBudget)
        XCTAssertEqual(ix.accounts.count, 0)
    }

    func testSetComputeUnitPriceZeroIsValid() {
        let ix = ComputeBudgetProgram.setComputeUnitPrice(microLamports: 0)
        XCTAssertEqual(ix.data, Data([0x03, 0, 0, 0, 0, 0, 0, 0, 0]))
    }
}
