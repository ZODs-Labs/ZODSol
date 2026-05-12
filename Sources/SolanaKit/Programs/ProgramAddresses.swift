import Foundation

/// Canonical addresses for the on-chain programs and sysvars that the send-
/// assets pipeline touches. The `try!` is safe: every literal is a known
/// 32-byte address whose base58 form decodes successfully; an accidental typo
/// would surface immediately as a fatal error on first access during tests.
public enum ProgramAddresses {
    public static let system: WalletAddress = try! WalletAddress(base58: "11111111111111111111111111111111")
    public static let token: WalletAddress = try! WalletAddress(base58: "TokenkegQfeZyiNwAJbNbGKPFXCWuBvf9Ss623VQ5DA")
    public static let token2022: WalletAddress =
        try! WalletAddress(base58: "TokenzQdBNbLqP5VEhdkAS6EPFLC1PHnBqCXEpPxuEb")
    public static let associatedToken: WalletAddress =
        try! WalletAddress(base58: "ATokenGPvbdGVxr1b2hvZbsiqW5xWH25efTNsLJA8knL")
    public static let computeBudget: WalletAddress =
        try! WalletAddress(base58: "ComputeBudget111111111111111111111111111111")
}
