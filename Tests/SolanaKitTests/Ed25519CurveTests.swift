import CryptoKit
import XCTest
@testable import SolanaKit

final class Ed25519CurveTests: XCTestCase {
    // MARK: - isOnCurve

    func testWrongLengthBytesAreOffCurve() {
        XCTAssertFalse(Ed25519Curve.isOnCurve(Data(count: 31)))
        XCTAssertFalse(Ed25519Curve.isOnCurve(Data(count: 33)))
        XCTAssertFalse(Ed25519Curve.isOnCurve(Data()))
    }

    func testEd25519BasePointIsOnCurve() {
        // Compressed encoding of the Ed25519 base point B per RFC 8032 §5.1:
        // little-endian Y = 0x66...66, byte 0 = 0x58. High bit of byte 31 is 0
        // (x_sign = 0).
        var bytes: [UInt8] = Array(repeating: 0x66, count: 32)
        bytes[0] = 0x58
        XCTAssertTrue(Ed25519Curve.isOnCurve(Data(bytes)))
    }

    func testIdentityPointWithSetSignBitIsOffCurve() {
        var bytes = Data(count: 32)
        bytes[0] = 1
        bytes[31] = 0x80
        XCTAssertFalse(Ed25519Curve.isOnCurve(bytes))
    }

    func testRfc8032TestVectorPublicKeyIsOnCurve() {
        // RFC 8032 §7.1 Test 1 public key, little-endian:
        // d75a980182b10ab7d54bfed3c964073a0ee172f3daa62325af021a68f707511a
        let hex = "d75a980182b10ab7d54bfed3c964073a0ee172f3daa62325af021a68f707511a"
        let bytes = Data(hexLE: hex)
        XCTAssertEqual(bytes.count, 32)
        XCTAssertTrue(Ed25519Curve.isOnCurve(bytes))
    }

    func testCryptoKitGeneratedPublicKeysAreOnCurve() {
        // Any CryptoKit-generated Ed25519 public key is on the curve by
        // construction. Verify across several keys to catch field-math bugs
        // that would happen with low probability.
        for _ in 0..<32 {
            let pk = Curve25519.Signing.PrivateKey()
            let bytes = pk.publicKey.rawRepresentation
            XCTAssertEqual(bytes.count, 32)
            XCTAssertTrue(
                Ed25519Curve.isOnCurve(bytes),
                "CryptoKit pub key flagged off-curve: \(bytes.map { String($0, radix: 16) }.joined())")
        }
    }

    func testWalletAddressOverloadMatchesByteOverload() throws {
        let usdc = try WalletAddress(base58: "EPjFWdd5AufqSSqeM2qN1xzybapC8G4wEGGkZwyTDt1v")
        let bytes = try Base58.decode(usdc.base58)
        XCTAssertEqual(Ed25519Curve.isOnCurve(usdc), Ed25519Curve.isOnCurve(bytes))
    }

    // MARK: - findProgramAddress

    func testFindProgramAddressIsDeterministic() throws {
        let programId = try WalletAddress(base58: "ATokenGPvbdGVxr1b2hvZbsiqW5xWH25efTNsLJA8knL")
        let seed = Data("hello".utf8)
        let a = Ed25519Curve.findProgramAddress(seeds: [seed], programId: programId)
        let b = Ed25519Curve.findProgramAddress(seeds: [seed], programId: programId)
        XCTAssertNotNil(a)
        XCTAssertEqual(a?.address, b?.address)
        XCTAssertEqual(a?.bump, b?.bump)
    }

    func testFindProgramAddressResultIsOffCurve() throws {
        let programId = try WalletAddress(base58: "ATokenGPvbdGVxr1b2hvZbsiqW5xWH25efTNsLJA8knL")
        let seed = Data("treasury".utf8)
        guard let (address, _) = Ed25519Curve.findProgramAddress(seeds: [seed], programId: programId) else {
            XCTFail("expected a PDA")
            return
        }
        XCTAssertFalse(Ed25519Curve.isOnCurve(address), "PDA must be off-curve by definition")
    }

    func testFindProgramAddressRejectsTooManySeeds() throws {
        let programId = try WalletAddress(base58: "ATokenGPvbdGVxr1b2hvZbsiqW5xWH25efTNsLJA8knL")
        let tooManySeeds = Array(repeating: Data([0]), count: 16)
        XCTAssertNil(Ed25519Curve.findProgramAddress(seeds: tooManySeeds, programId: programId))
    }

    func testFindProgramAddressRejectsOversizedSeed() throws {
        let programId = try WalletAddress(base58: "ATokenGPvbdGVxr1b2hvZbsiqW5xWH25efTNsLJA8knL")
        let oversized = Data(repeating: 0xAA, count: 33)
        XCTAssertNil(Ed25519Curve.findProgramAddress(seeds: [oversized], programId: programId))
    }

    func testFindProgramAddressMatchesMetaplexMetadataPDA() throws {
        // Canonical Metaplex Token Metadata PDA for the USDC mint. Verifiable
        // on-chain: any USDC token on mainnet has its metadata account at the
        // PDA derived with these inputs.
        //
        // Seeds:   ["metadata", METAPLEX_PROGRAM_ID, USDC_MINT]
        // Program: metaqbxxUerdq28cj1RbAWkYQm3ybzjb6a8bt518x1s
        // PDA:     5x38Kp4hvdomTCnCrAny4UtMUt5rQBdB6px2K1Ui45Wq, bump 255
        let metaplex = try WalletAddress(base58: "metaqbxxUerdq28cj1RbAWkYQm3ybzjb6a8bt518x1s")
        let usdc = try WalletAddress(base58: "EPjFWdd5AufqSSqeM2qN1xzybapC8G4wEGGkZwyTDt1v")

        let seeds: [Data] = try [
            Data("metadata".utf8),
            Base58.decode(metaplex.base58),
            Base58.decode(usdc.base58),
        ]

        guard let (address, bump) = Ed25519Curve.findProgramAddress(seeds: seeds, programId: metaplex) else {
            XCTFail("PDA derivation returned nil")
            return
        }
        XCTAssertEqual(address.base58, "5x38Kp4hvdomTCnCrAny4UtMUt5rQBdB6px2K1Ui45Wq")
        XCTAssertEqual(bump, 255)
    }
}

// MARK: - Hex helpers

extension Data {
    fileprivate init(hexLE hex: String) {
        let chars = Array(hex)
        var out: [UInt8] = []
        out.reserveCapacity(chars.count / 2)
        var i = 0
        while i < chars.count {
            let high = UInt8(String(chars[i]), radix: 16) ?? 0
            let low = UInt8(String(chars[i + 1]), radix: 16) ?? 0
            out.append((high << 4) | low)
            i += 2
        }
        self.init(out)
    }
}
