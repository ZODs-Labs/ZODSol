import Foundation
import Kit

public enum Ed25519Curve {
    private static let backend = ZODSolCryptoBackend()

    public static func isOnCurve(_ compressedPublicKey: Data) -> Bool {
        self.backend.isOnCurve(compressedPublicKey)
    }

    public static func isOnCurve(_ address: WalletAddress) -> Bool {
        guard let bytes = try? Kit.getPublicKeyFromAddress(address.address) else {
            return false
        }
        return self.backend.isOnCurve(bytes)
    }

    public static func findProgramAddress(
        seeds: [Data],
        programId: WalletAddress) -> (address: WalletAddress, bump: UInt8)?
    {
        do {
            let derived = try Kit.getProgramDerivedAddress(
                programAddress: programId.address,
                seeds: seeds.map { Kit.ProgramDerivedAddressSeed.bytes($0) },
                using: self.backend)
            return (WalletAddress(address: derived.address), derived.bump.rawValue)
        } catch {
            return nil
        }
    }
}
