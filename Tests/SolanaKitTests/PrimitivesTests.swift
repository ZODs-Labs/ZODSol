import XCTest
@testable import SolanaKit

final class PrimitivesTests: XCTestCase {
    // MARK: - Blockhash

    func testBlockhashRejectsWrongLengthBytes() {
        XCTAssertThrowsError(try Blockhash(bytes: Data(count: 31)))
        XCTAssertThrowsError(try Blockhash(bytes: Data(count: 33)))
        XCTAssertNoThrow(try Blockhash(bytes: Data(count: 32)))
    }

    func testBlockhashRoundTripsBase58() throws {
        let bytes = Data((0..<32).map { UInt8($0) })
        let bh = try Blockhash(bytes: bytes)
        let again = try Blockhash(base58: bh.base58)
        XCTAssertEqual(again, bh)
    }

    func testBlockhashCodable() throws {
        let bytes = Data((0..<32).map { UInt8(255 - $0) })
        let bh = try Blockhash(bytes: bytes)
        let encoded = try JSONEncoder().encode(bh)
        let decoded = try JSONDecoder().decode(Blockhash.self, from: encoded)
        XCTAssertEqual(decoded, bh)
    }

    // MARK: - Signature

    func testSignatureRejectsWrongLength() {
        XCTAssertThrowsError(try Signature(bytes: Data(count: 63)))
        XCTAssertThrowsError(try Signature(bytes: Data(count: 65)))
        XCTAssertNoThrow(try Signature(bytes: Data(count: 64)))
    }

    func testSignatureRoundTripsBase58() throws {
        let bytes = Data((0..<64).map { UInt8($0) })
        let sig = try Signature(bytes: bytes)
        let again = try Signature(base58: sig.base58)
        XCTAssertEqual(again, sig)
    }

    // MARK: - AccountMeta

    func testAccountMetaPrivilegeMerge() throws {
        let pk = try WalletAddress(base58: "EPjFWdd5AufqSSqeM2qN1xzybapC8G4wEGGkZwyTDt1v")
        let readonly = AccountMeta(pubkey: pk, isSigner: false, isWritable: false)
        let writableSigner = AccountMeta(pubkey: pk, isSigner: true, isWritable: true)
        let merged = readonly.mergingPrivileges(with: writableSigner)
        XCTAssertTrue(merged.isSigner)
        XCTAssertTrue(merged.isWritable)
    }

    func testAccountMetaConvenienceConstructors() throws {
        let pk = try WalletAddress(base58: "EPjFWdd5AufqSSqeM2qN1xzybapC8G4wEGGkZwyTDt1v")
        XCTAssertEqual(AccountMeta.signer(pk), AccountMeta(pubkey: pk, isSigner: true, isWritable: true))
        XCTAssertEqual(
            AccountMeta.signer(pk, writable: false),
            AccountMeta(pubkey: pk, isSigner: true, isWritable: false))
        XCTAssertEqual(AccountMeta.writable(pk), AccountMeta(pubkey: pk, isSigner: false, isWritable: true))
        XCTAssertEqual(AccountMeta.readonly(pk), AccountMeta(pubkey: pk, isSigner: false, isWritable: false))
    }
}
