import CryptoKit
import Foundation
import SolanaKit

/// Single-purpose signing seam for the send pipeline.
///
/// The 32-byte Ed25519 seed never crosses this boundary — `signMessage`
/// constructs the `Curve25519.Signing.PrivateKey` inside `WalletStore`'s
/// `withPrivateKey` closure and the key goes out of scope on return. Callers
/// receive only the resulting 64-byte signature.
public protocol SendSignerAccess: Sendable {
    /// Sign `message` with the seed owned by `walletId`. Prompts the user
    /// for biometric unlock; throws `WalletOverviewError.biometricInvalidated`
    /// on cancel/denial.
    func signMessage(walletId: UUID, message: Data, prompt: String) async throws -> Signature
}

/// Address lookup seam — kept narrow so tests can stub it without standing
/// up the full Keychain-backed `WalletStore`.
public protocol SendWalletLookup: Sendable {
    func address(for walletId: UUID) async throws -> WalletAddress
}

extension WalletStore {
    public func signMessage(walletId: UUID, message: Data, prompt: String) async throws -> Signature {
        try await withPrivateKey(walletId: walletId, prompt: prompt) { buffer in
            let seed = buffer.prefix(32)
            let privateKey: Curve25519.Signing.PrivateKey
            do {
                privateKey = try Curve25519.Signing.PrivateKey(rawRepresentation: seed)
            } catch {
                throw WalletOverviewError.malformedResponse("stored private key is corrupt")
            }
            let sigBytes = try privateKey.signature(for: message)
            return try Signature(bytes: sigBytes)
        }
    }
}

extension WalletStore: SendSignerAccess {}
extension WalletStore: SendWalletLookup {}
