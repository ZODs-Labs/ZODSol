import Foundation

/// One account reference in a Solana instruction.
///
/// Solana's runtime decides which signatures are required and which accounts
/// may mutate based on the `isSigner` and `isWritable` flags carried on every
/// `AccountMeta`. When the same account appears in multiple instructions of
/// the same transaction the runtime merges the privileges by taking the
/// strongest claim (any-signer wins, any-writable wins); the message compiler
/// must replicate that semantic before encoding the wire format.
public struct AccountMeta: Hashable, Sendable {
    public let pubkey: WalletAddress
    public let isSigner: Bool
    public let isWritable: Bool

    public init(pubkey: WalletAddress, isSigner: Bool, isWritable: Bool) {
        self.pubkey = pubkey
        self.isSigner = isSigner
        self.isWritable = isWritable
    }

    public static func signer(_ pubkey: WalletAddress, writable: Bool = true) -> AccountMeta {
        AccountMeta(pubkey: pubkey, isSigner: true, isWritable: writable)
    }

    public static func writable(_ pubkey: WalletAddress) -> AccountMeta {
        AccountMeta(pubkey: pubkey, isSigner: false, isWritable: true)
    }

    public static func readonly(_ pubkey: WalletAddress) -> AccountMeta {
        AccountMeta(pubkey: pubkey, isSigner: false, isWritable: false)
    }

    /// Merge two metas referring to the same `pubkey`, taking the strongest
    /// signer/writable flags. Callers must check `pubkey` equality first.
    public func mergingPrivileges(with other: AccountMeta) -> AccountMeta {
        AccountMeta(
            pubkey: self.pubkey,
            isSigner: self.isSigner || other.isSigner,
            isWritable: self.isWritable || other.isWritable)
    }
}
