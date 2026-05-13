import Foundation

/// Builders for instructions on the native System program.
public enum SystemProgram {
    public static let id = ProgramAddresses.system

    /// Transfer lamports from `from` to `to`. `from` must sign.
    ///
    /// Wire data: 4-byte LE instruction discriminator `2` (Transfer), followed
    /// by 8-byte LE u64 amount.
    public static func transferSol(
        from: WalletAddress,
        to: WalletAddress,
        lamports: Lamports,
        references: [WalletAddress] = []) -> Instruction
    {
        var data = Data()
        data.reserveCapacity(12)
        LittleEndianEncoder.appendUInt32(2, to: &data)
        LittleEndianEncoder.appendUInt64(lamports.rawValue, to: &data)
        let referenceMetas = references.map { AccountMeta(pubkey: $0, isSigner: false, isWritable: false) }
        return Instruction(
            programAddress: self.id,
            accounts: [
                AccountMeta(pubkey: from, isSigner: true, isWritable: true),
                AccountMeta(pubkey: to, isSigner: false, isWritable: true),
            ] + referenceMetas,
            data: data)
    }
}
