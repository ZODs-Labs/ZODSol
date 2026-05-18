import Foundation
import Kit

/// Builders for the Associated Token Account program.
///
/// Associated Token Accounts (ATAs) are the canonical token accounts a wallet
/// uses to hold a specific mint. Their address is derived deterministically
/// from `(owner, tokenProgram, mint)` via the PDA algorithm.
public enum AssociatedTokenProgram {
    public static let id = ProgramAddresses.associatedToken

    /// Derive the canonical ATA address for `(owner, mint, tokenProgram)`.
    /// The `tokenProgram` argument MUST match the mint's owner program
    /// (`TOKEN_PROGRAM` for legacy SPL mints, `TOKEN_2022_PROGRAM` for
    /// Token-2022 mints), passing the wrong one yields an invalid address.
    public static func findAssociatedTokenAddress(
        owner: WalletAddress,
        mint: WalletAddress,
        tokenProgram: WalletAddress) throws -> WalletAddress
    {
        let seeds: [Kit.ProgramDerivedAddressSeed] = try [
            .bytes(Base58.decode(owner.base58)),
            .bytes(Base58.decode(tokenProgram.base58)),
            .bytes(Base58.decode(mint.base58)),
        ]
        guard let derived = try? Kit.getProgramDerivedAddress(
            programAddress: self.id.address,
            seeds: seeds,
            using: ZODSolCryptoBackend())
        else {
            throw SolanaProviderError.invalidInput(
                "associated token address derivation failed")
        }
        return WalletAddress(address: derived.address)
    }

    /// Create the ATA if it does not already exist; succeeds silently if it
    /// does. Always use this over the non-idempotent variant: a non-idempotent
    /// create fails when the recipient races us by creating their own ATA and
    /// the cost of the no-op is zero CU when the account already exists.
    ///
    /// Wire data: a single byte `1` (CreateIdempotent discriminator).
    public static func createAssociatedTokenIdempotent(
        payer: WalletAddress,
        owner: WalletAddress,
        mint: WalletAddress,
        associatedToken: WalletAddress,
        tokenProgram: WalletAddress) -> Instruction
    {
        Instruction(
            programAddress: self.id,
            accounts: [
                AccountMeta(pubkey: payer, isSigner: true, isWritable: true),
                AccountMeta(pubkey: associatedToken, isSigner: false, isWritable: true),
                AccountMeta(pubkey: owner, isSigner: false, isWritable: false),
                AccountMeta(pubkey: mint, isSigner: false, isWritable: false),
                AccountMeta(pubkey: ProgramAddresses.system, isSigner: false, isWritable: false),
                AccountMeta(pubkey: tokenProgram, isSigner: false, isWritable: false),
            ],
            data: Data([0x01]))
    }
}
