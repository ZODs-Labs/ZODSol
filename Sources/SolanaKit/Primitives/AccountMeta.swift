import Foundation
import Kit

/// One account reference in a Solana instruction.
///
/// Solana's runtime decides which signatures are required and which accounts
/// may mutate based on the `isSigner` and `isWritable` flags carried on every
/// `AccountMeta`. When the same account appears in multiple instructions of
/// the same transaction the runtime merges the privileges by taking the
/// strongest claim (any-signer wins, any-writable wins); the message compiler
/// must replicate that semantic before encoding the wire format.
public struct AccountMeta: Hashable, Sendable {
    public let kitMeta: Kit.AccountMeta

    public var pubkey: WalletAddress {
        WalletAddress(address: self.kitMeta.address)
    }

    public var isSigner: Bool {
        Kit.isSignerRole(self.kitMeta.role)
    }

    public var isWritable: Bool {
        Kit.isWritableRole(self.kitMeta.role)
    }

    public init(pubkey: WalletAddress, isSigner: Bool, isWritable: Bool) {
        self.kitMeta = Kit.AccountMeta(
            address: pubkey.address,
            role: Self.kitRole(isSigner: isSigner, isWritable: isWritable))
    }

    public init(kitMeta: Kit.AccountMeta) {
        self.kitMeta = kitMeta
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
        AccountMeta(kitMeta: Kit.AccountMeta(
            address: self.kitMeta.address,
            role: Kit.mergeRoles(self.kitMeta.role, other.kitMeta.role)))
    }

    public var kitRole: Kit.AccountRole {
        self.kitMeta.role
    }

    private static func kitRole(isSigner: Bool, isWritable: Bool) -> Kit.AccountRole {
        switch (isSigner, isWritable) {
        case (true, true):
            .writableSigner
        case (true, false):
            .readonlySigner
        case (false, true):
            .writable
        case (false, false):
            .readonly
        }
    }

    public var kitAccount: Kit.InstructionAccount {
        .account(self.kitMeta)
    }
}
