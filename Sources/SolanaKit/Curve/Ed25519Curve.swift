import CryptoKit
import Foundation

/// Ed25519 curve helpers required by the send-assets pipeline.
///
/// `isOnCurve` mirrors Solana's `bytes_are_curve_point` — used to refuse SOL
/// transfers to Program-Derived Addresses (PDAs cannot sign and any lamports
/// sent to a non-ATA PDA cannot be moved by the recipient).
///
/// `findProgramAddress` matches Solana's PDA derivation; we use it to derive
/// Associated Token Accounts and any other deterministically derived address.
public enum Ed25519Curve {
    /// 21-byte ASCII marker appended to the seed list before hashing, matching
    /// the constant used by Solana's `find_program_address`.
    private static let pdaMarker: Data = .init("ProgramDerivedAddress".utf8)

    /// Returns `true` if the 32-byte string decodes as a valid Ed25519 Edwards
    /// point. Returns `false` for non-32-byte input or off-curve points.
    public static func isOnCurve(_ bytes: Data) -> Bool {
        guard bytes.count == 32 else { return false }

        // Decode the compressed y coordinate. The high bit of byte 31 carries
        // the sign of x; mask it off before reading y.
        var yBytes = bytes
        let xSign = (yBytes[yBytes.startIndex + 31] >> 7) & 1
        yBytes[yBytes.startIndex + 31] &= 0x7F

        let y = Field25519(bytesLE: yBytes)

        let yy = Field25519.mul(y, y)
        let u = Field25519.sub(yy, .one)
        let dyy = Field25519.mul(Field25519(canonicalLimbs: Field25519.dLimbs), yy)
        let v = Field25519.add(dyy, .one)

        if v.isZero { return false }

        let vInv = Field25519.inv(v)
        let xSquared = Field25519.mul(u, vInv)

        if xSquared.isZero {
            // The only valid encoding of x = 0 has sign bit 0.
            return xSign == 0
        }

        // Euler's criterion: xSquared is a quadratic residue iff
        //   xSquared^((p-1)/2) == 1 mod p.
        let legendre = Field25519.pow(xSquared, Field25519.pMinus1Over2Limbs)
        return legendre == .one
    }

    /// Convenience overload for `WalletAddress` recipients.
    public static func isOnCurve(_ address: WalletAddress) -> Bool {
        guard let bytes = try? Base58.decode(address.base58) else { return false }
        return self.isOnCurve(bytes)
    }

    /// Derive a Program Derived Address from a sequence of seeds and a program
    /// id. Mirrors `Pubkey::find_program_address`: tries bumps 255..=0,
    /// returning the first hash that lands off-curve.
    ///
    /// Returns `nil` only if every bump produces an on-curve hash, which is
    /// astronomically unlikely (P ~ 2^-256) but guarded for correctness.
    public static func findProgramAddress(
        seeds: [Data],
        programId: WalletAddress) -> (address: WalletAddress, bump: UInt8)?
    {
        let programBytes: Data
        do {
            programBytes = try Base58.decode(programId.base58)
        } catch {
            return nil
        }

        // Solana rejects any individual seed > 32 bytes and rejects > 16 total
        // seeds. Bump occupies the 16th slot, so user-supplied seeds may be
        // at most 15.
        guard seeds.count <= 15 else { return nil }
        for seed in seeds where seed.count > 32 {
            return nil
        }

        var bump: UInt8 = 255
        while true {
            var hasher = SHA256()
            for seed in seeds {
                hasher.update(data: seed)
            }
            hasher.update(data: Data([bump]))
            hasher.update(data: programBytes)
            hasher.update(data: self.pdaMarker)
            let digest = Data(hasher.finalize())
            if !self.isOnCurve(digest) {
                guard let address = try? WalletAddress(base58: Base58.encode(digest)) else {
                    // 32 zero bytes is the only 32-byte length that could fail
                    // `WalletAddress` construction, and it is off-curve, so we
                    // would have to encounter the (unreachable) all-zero hash.
                    return nil
                }
                return (address, bump)
            }
            if bump == 0 { return nil }
            bump -= 1
        }
    }
}
