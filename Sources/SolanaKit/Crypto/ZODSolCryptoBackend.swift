import CryptoBackend
import CryptoKit
import Foundation
import SolanaErrors

struct ZODSolCryptoBackend: CryptoBackend {
    func generateKeyPair() throws(KeysError) -> CryptoKeyPairBytes {
        let privateKey = Curve25519.Signing.PrivateKey()
        return CryptoKeyPairBytes(
            privateKey: Data(privateKey.rawRepresentation),
            publicKey: Data(privateKey.publicKey.rawRepresentation))
    }

    func createKeyPair(privateKeyBytes: Data) throws(KeysError) -> CryptoKeyPairBytes {
        guard privateKeyBytes.count == 32 else {
            throw KeysError.invalidPrivateKeyByteLength(actualLength: privateKeyBytes.count)
        }
        let privateKey = try self.makePrivateKey(privateKeyBytes)
        return CryptoKeyPairBytes(
            privateKey: privateKeyBytes,
            publicKey: Data(privateKey.publicKey.rawRepresentation))
    }

    func createKeyPair(solanaKeyPairBytes: Data) throws(KeysError) -> CryptoKeyPairBytes {
        guard solanaKeyPairBytes.count == 64 else {
            throw KeysError.invalidKeyPairByteLength(byteLength: solanaKeyPairBytes.count)
        }
        let seed = Data(solanaKeyPairBytes.prefix(32))
        let providedPublicKey = Data(solanaKeyPairBytes.suffix(32))
        let keyPair = try self.createKeyPair(privateKeyBytes: seed)
        guard keyPair.publicKey == providedPublicKey else {
            throw KeysError.publicKeyMustMatchPrivateKey
        }
        return keyPair
    }

    func publicKey(privateKeyBytes: Data) throws(KeysError) -> Data {
        try Data(self.makePrivateKey(privateKeyBytes).publicKey.rawRepresentation)
    }

    func sign(_ message: Data, privateKeyBytes: Data) throws(KeysError) -> Data {
        do {
            return try self.makePrivateKey(privateKeyBytes).signature(for: message)
        } catch let error as KeysError {
            throw error
        } catch {
            throw KeysError.invalidPrivateKeyByteLength(actualLength: privateKeyBytes.count)
        }
    }

    func verify(signature: Data, message: Data, publicKeyBytes: Data) throws(KeysError) -> Bool {
        guard signature.count == 64, publicKeyBytes.count == 32 else {
            return false
        }
        do {
            let publicKey = try Curve25519.Signing.PublicKey(rawRepresentation: publicKeyBytes)
            return publicKey.isValidSignature(signature, for: message)
        } catch {
            return false
        }
    }

    func sha256(_ data: Data) -> Data {
        Data(SHA256.hash(data: data))
    }

    func isOnCurve(_ compressedEdwardsY: Data) -> Bool {
        Self.compressedPointBytesAreOnCurve(compressedEdwardsY)
    }

    private func makePrivateKey(_ bytes: Data) throws(KeysError) -> Curve25519.Signing.PrivateKey {
        guard bytes.count == 32 else {
            throw KeysError.invalidPrivateKeyByteLength(actualLength: bytes.count)
        }
        do {
            return try Curve25519.Signing.PrivateKey(rawRepresentation: bytes)
        } catch {
            throw KeysError.invalidPrivateKeyByteLength(actualLength: bytes.count)
        }
    }

    private static func compressedPointBytesAreOnCurve(_ bytes: Data) -> Bool {
        guard bytes.count == 32 else { return false }
        var yBytes = Data(bytes)
        let lastByte = yBytes[31]
        yBytes[31] &= 0x7F

        let y = Field25519(bytesLE: yBytes)
        let yy = Field25519.mul(y, y)
        let u = Field25519.sub(yy, .one)
        let dyy = Field25519.mul(Field25519(canonicalLimbs: Field25519.dLimbs), yy)
        let v = Field25519.add(dyy, .one)
        if v.isZero {
            return false
        }
        let vInv = Field25519.inv(v)
        let xSquared = Field25519.mul(u, vInv)
        if xSquared.isZero {
            return (lastByte & 0x80) == 0
        }
        let legendre = Field25519.pow(xSquared, Field25519.pMinus1Over2Limbs)
        return legendre == .one
    }
}
