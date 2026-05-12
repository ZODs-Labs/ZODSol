import Foundation

/// Builders for instructions on the SPL Token-2022 program.
///
/// Token-2022 reuses the legacy `TransferChecked` discriminator (12) for
/// regular transfers; mints with the `TransferFeeConfig` extension require
/// `TransferCheckedWithFee` instead, which is nested under the
/// `TransferFeeExtension` family (outer discriminator 26).
public enum Token2022Program {
    public static let id = ProgramAddresses.token2022

    /// Standard checked transfer, for Token-2022 mints without TransferFee.
    public static func transferChecked(
        source: WalletAddress,
        mint: WalletAddress,
        destination: WalletAddress,
        owner: WalletAddress,
        amount: UInt64,
        decimals: UInt8) -> Instruction
    {
        var data = Data()
        data.reserveCapacity(10)
        data.append(0x0C)
        LittleEndianEncoder.appendUInt64(amount, to: &data)
        data.append(decimals)
        return Instruction(
            programAddress: self.id,
            accounts: [
                AccountMeta(pubkey: source, isSigner: false, isWritable: true),
                AccountMeta(pubkey: mint, isSigner: false, isWritable: false),
                AccountMeta(pubkey: destination, isSigner: false, isWritable: true),
                AccountMeta(pubkey: owner, isSigner: true, isWritable: false),
            ],
            data: data)
    }

    /// Transfer for Token-2022 mints carrying `TransferFeeConfig`. The `fee`
    /// must match the per-epoch fee derived from the mint, or the program
    /// rejects the instruction.
    ///
    /// Wire data:
    ///  - byte 0: outer discriminator `26` (TransferFeeExtension)
    ///  - byte 1: inner discriminator `1` (TransferCheckedWithFee)
    ///  - bytes 2-9: u64 LE amount
    ///  - byte 10: u8 decimals
    ///  - bytes 11-18: u64 LE fee
    public static func transferCheckedWithFee(
        source: WalletAddress,
        mint: WalletAddress,
        destination: WalletAddress,
        owner: WalletAddress,
        amount: UInt64,
        decimals: UInt8,
        fee: UInt64) -> Instruction
    {
        var data = Data()
        data.reserveCapacity(19)
        data.append(0x1A)
        data.append(0x01)
        LittleEndianEncoder.appendUInt64(amount, to: &data)
        data.append(decimals)
        LittleEndianEncoder.appendUInt64(fee, to: &data)
        return Instruction(
            programAddress: self.id,
            accounts: [
                AccountMeta(pubkey: source, isSigner: false, isWritable: true),
                AccountMeta(pubkey: mint, isSigner: false, isWritable: false),
                AccountMeta(pubkey: destination, isSigner: false, isWritable: true),
                AccountMeta(pubkey: owner, isSigner: true, isWritable: false),
            ],
            data: data)
    }
}
