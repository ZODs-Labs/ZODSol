import Foundation

/// Builders for instructions on the legacy SPL Token program.
///
/// `transferChecked` is the recommended instruction for moving SPL tokens
/// (the older `Transfer` opcode does not validate decimals and is deprecated
/// in Token-2022 for safety; we never emit it).
public enum TokenProgram {
    public static let id = ProgramAddresses.token

    /// Transfer a checked amount between two associated token accounts.
    ///
    /// Wire data: 1-byte discriminator `12` (TransferChecked), 8-byte LE u64
    /// amount, 1-byte u8 decimals.
    public static func transferChecked(
        source: WalletAddress,
        mint: WalletAddress,
        destination: WalletAddress,
        owner: WalletAddress,
        amount: UInt64,
        decimals: UInt8,
        references: [WalletAddress] = []) -> Instruction
    {
        var data = Data()
        data.reserveCapacity(10)
        data.append(0x0C)
        LittleEndianEncoder.appendUInt64(amount, to: &data)
        data.append(decimals)
        let referenceMetas = references.map { AccountMeta(pubkey: $0, isSigner: false, isWritable: false) }
        return Instruction(
            programAddress: self.id,
            accounts: [
                AccountMeta(pubkey: source, isSigner: false, isWritable: true),
                AccountMeta(pubkey: mint, isSigner: false, isWritable: false),
                AccountMeta(pubkey: destination, isSigner: false, isWritable: true),
                AccountMeta(pubkey: owner, isSigner: true, isWritable: false),
            ] + referenceMetas,
            data: data)
    }
}
