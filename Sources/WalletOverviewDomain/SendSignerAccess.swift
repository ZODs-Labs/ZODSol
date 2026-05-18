import Foundation
import SolanaKit

/// Single-purpose signing seam for the send pipeline.
///
/// The 32-byte Ed25519 seed never crosses this boundary. `signMessage`
/// constructs the Kit private key inside `WalletStore`'s `withPrivateKey`
/// closure and the key goes out of scope on return. Callers receive only the
/// resulting 64-byte signature.
public protocol SendSignerAccess: Sendable {
    /// Sign `message` with the seed owned by `walletId`. Prompts the user
    /// for biometric unlock; throws `WalletOverviewError.biometricInvalidated`
    /// on cancel/denial.
    func signMessage(walletId: UUID, message: Data, prompt: String) async throws -> Signature
}

/// Address lookup seam kept narrow so tests can stub it without standing
/// up the full Keychain-backed `WalletStore`.
public protocol SendWalletLookup: Sendable {
    func address(for walletId: UUID) async throws -> WalletAddress
}

extension WalletStore {
    public func signMessage(walletId: UUID, message: Data, prompt: String) async throws -> Signature {
        try await withPrivateKey(walletId: walletId, prompt: prompt) { buffer in
            let seed = Data(buffer.prefix(32))
            do {
                return try Signature.sign(message: message, seed: seed)
            } catch {
                throw WalletOverviewError.malformedResponse("stored private key is corrupt")
            }
        }
    }
}

extension WalletStore: SendSignerAccess {}
extension WalletStore: SendWalletLookup {}
