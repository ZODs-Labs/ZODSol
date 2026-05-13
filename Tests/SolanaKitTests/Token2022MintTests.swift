import XCTest
@testable import SolanaKit

/// Tests construct synthetic mint account bytes that exercise each Token-2022
/// extension's compatibility decision. No external fixtures.
final class Token2022MintTests: XCTestCase {
    // MARK: - Builders for synthetic mint bytes

    /// Build a synthetic Token-2022 mint account with the given decimals,
    /// extension type IDs + raw bodies. Returns bytes laid out per the
    /// `Mint` (82) + padding (83) + accountType (1) + TLV format.
    private func makeMint(decimals: UInt8, extensions: [(type: UInt16, body: Data)]) -> Data {
        var data = Data()
        data.reserveCapacity(166 + extensions.reduce(0) { $0 + 4 + $1.body.count })

        // Base Mint (82 bytes).
        data.append(Data(repeating: 0x00, count: 4)) // mint_authority option = None
        data.append(Data(repeating: 0x00, count: 32)) // mint_authority pubkey (ignored)
        data.append(Data(repeating: 0x00, count: 8)) // supply = 0
        data.append(decimals)
        data.append(0x01) // is_initialized = true
        data.append(Data(repeating: 0x00, count: 4)) // freeze_authority option = None
        data.append(Data(repeating: 0x00, count: 32)) // freeze_authority pubkey

        // Padding (83 bytes) + accountType (1 byte = Mint).
        data.append(Data(repeating: 0x00, count: 83))
        data.append(0x01)

        // TLV extensions.
        for (type, body) in extensions {
            data.append(UInt8(type & 0xFF))
            data.append(UInt8((type >> 8) & 0xFF))
            let length = UInt16(body.count)
            data.append(UInt8(length & 0xFF))
            data.append(UInt8((length >> 8) & 0xFF))
            data.append(body)
        }

        return data
    }

    private func makeTransferFeeConfigBody(
        olderEpoch: UInt64, olderBps: UInt16, olderMax: UInt64,
        newerEpoch: UInt64, newerBps: UInt16, newerMax: UInt64) -> Data
    {
        var body = Data()
        body.reserveCapacity(108)
        // authorities (None) + withheld_amount = 0.
        body.append(Data(repeating: 0, count: 32)) // transfer_fee_config_authority
        body.append(Data(repeating: 0, count: 32)) // withdraw_withheld_authority
        body.append(Data(repeating: 0, count: 8)) // withheld_amount

        func appendTransferFee(epoch: UInt64, max: UInt64, bps: UInt16) {
            self.appendU64(epoch, into: &body)
            self.appendU64(max, into: &body)
            self.appendU16(bps, into: &body)
        }
        appendTransferFee(epoch: olderEpoch, max: olderMax, bps: olderBps)
        appendTransferFee(epoch: newerEpoch, max: newerMax, bps: newerBps)
        return body
    }

    private func appendU16(_ value: UInt16, into data: inout Data) {
        data.append(UInt8(value & 0xFF))
        data.append(UInt8((value >> 8) & 0xFF))
    }

    private func appendU64(_ value: UInt64, into data: inout Data) {
        for shift: UInt64 in stride(from: 0, to: 64, by: 8) {
            data.append(UInt8((value >> shift) & 0xFF))
        }
    }

    // MARK: - Base parsing

    func testLegacyMintBytesParseAsExtensionFree() throws {
        // Exactly 82 bytes = legacy SPL mint with no extensions.
        var data = Data(repeating: 0, count: 82)
        data[44] = 9 // decimals = 9
        data[45] = 1 // is_initialized = true
        let profile = try Token2022Mint.parse(data, currentEpoch: 500)
        XCTAssertEqual(profile.compatibility, .ok)
        XCTAssertEqual(profile.decimals, 9)
        XCTAssertNil(profile.transferFee)
        XCTAssertFalse(profile.permanentDelegate)
    }

    func testTooShortBytesThrows() {
        XCTAssertThrowsError(try Token2022Mint.parse(Data(count: 50), currentEpoch: 0)) { error in
            XCTAssertEqual(error as? Token2022Mint.ParseError, .tooShort)
        }
    }

    func testUninitializedMintThrows() {
        var data = Data(repeating: 0, count: 82)
        // data[45] = 0 stays uninitialized.
        XCTAssertThrowsError(try Token2022Mint.parse(data, currentEpoch: 0)) { error in
            XCTAssertEqual(error as? Token2022Mint.ParseError, .mintUninitialized)
        }
    }

    func testWrongAccountTypeThrows() {
        // Build 200 bytes with byte 165 = 2 (Account, not Mint).
        var data = Data(repeating: 0, count: 200)
        data[44] = 6
        data[45] = 1
        data[165] = 2
        XCTAssertThrowsError(try Token2022Mint.parse(data, currentEpoch: 0)) { error in
            XCTAssertEqual(error as? Token2022Mint.ParseError, .notMint(accountType: 2))
        }
    }

    // MARK: - TransferFeeConfig

    func testTransferFeeConfigCurrentEpochPicksNewer() throws {
        let body = self.makeTransferFeeConfigBody(
            olderEpoch: 50, olderBps: 100, olderMax: 1000,
            newerEpoch: 500, newerBps: 200, newerMax: 2000)
        let mint = self.makeMint(decimals: 6, extensions: [(type: 1, body: body)])
        let profile = try Token2022Mint.parse(mint, currentEpoch: 600)
        XCTAssertEqual(profile.compatibility, .ok)
        XCTAssertEqual(profile.transferFee?.basisPoints, 200)
        XCTAssertEqual(profile.transferFee?.maximumFee, 2000)
        XCTAssertEqual(profile.transferFee?.epoch, 500)
    }

    func testTransferFeeConfigEarlyEpochUsesOlder() throws {
        let body = self.makeTransferFeeConfigBody(
            olderEpoch: 50, olderBps: 100, olderMax: 1000,
            newerEpoch: 500, newerBps: 200, newerMax: 2000)
        let mint = self.makeMint(decimals: 6, extensions: [(type: 1, body: body)])
        let profile = try Token2022Mint.parse(mint, currentEpoch: 300)
        XCTAssertEqual(profile.transferFee?.basisPoints, 100)
        XCTAssertEqual(profile.transferFee?.epoch, 50)
    }

    func testTransferFeeOfZeroIsNotEmitted() throws {
        let body = self.makeTransferFeeConfigBody(
            olderEpoch: 0, olderBps: 0, olderMax: 0,
            newerEpoch: 0, newerBps: 0, newerMax: 0)
        let mint = self.makeMint(decimals: 6, extensions: [(type: 1, body: body)])
        let profile = try Token2022Mint.parse(mint, currentEpoch: 100)
        XCTAssertNil(profile.transferFee, "fee with 0 basis points should not be emitted")
    }

    func testTransferFeeFormula() {
        let fee = Token2022MintProfile.TransferFeeForEpoch(
            basisPoints: 250, maximumFee: 1_000_000, epoch: 0)
        // 1_000_000 * 250 / 10_000 = 25_000.
        XCTAssertEqual(fee.fee(for: 1_000_000), 25000)
        // Clamps to maximum when computed > max.
        XCTAssertEqual(fee.fee(for: 1_000_000_000), 1_000_000)
        // Zero amount → zero fee.
        XCTAssertEqual(fee.fee(for: 0), 0)
    }

    // MARK: - Refusals

    func testNonTransferableIsRefused() throws {
        let mint = self.makeMint(decimals: 6, extensions: [(type: 9, body: Data())])
        let profile = try Token2022Mint.parse(mint, currentEpoch: 0)
        if case let .refused(reason) = profile.compatibility {
            XCTAssertTrue(reason.lowercased().contains("non-transferable"))
        } else {
            XCTFail("Expected refusal for NonTransferable, got \(profile.compatibility)")
        }
    }

    func testTransferHookWithZeroProgramIdIsAllowed() throws {
        // 32 bytes authority (zero) + 32 bytes program_id (zero) = inert hook.
        let body = Data(repeating: 0, count: 64)
        let mint = self.makeMint(decimals: 6, extensions: [(type: 14, body: body)])
        let profile = try Token2022Mint.parse(mint, currentEpoch: 0)
        XCTAssertEqual(profile.compatibility, .ok)
    }

    func testTransferHookWithNonZeroProgramIdIsRefused() throws {
        // authority = zero, program_id = nonzero.
        var body = Data(repeating: 0, count: 32) // authority
        body.append(Data(repeating: 0x01, count: 32)) // program_id
        let mint = self.makeMint(decimals: 6, extensions: [(type: 14, body: body)])
        let profile = try Token2022Mint.parse(mint, currentEpoch: 0)
        if case let .refused(reason) = profile.compatibility {
            XCTAssertTrue(reason.lowercased().contains("transfer hook"))
        } else {
            XCTFail("Expected refusal for TransferHook with program, got \(profile.compatibility)")
        }
    }

    func testDefaultAccountStateFrozenIsRefused() throws {
        let body = Data([0x02]) // 2 = Frozen
        let mint = self.makeMint(decimals: 6, extensions: [(type: 6, body: body)])
        let profile = try Token2022Mint.parse(mint, currentEpoch: 0)
        if case let .refused(reason) = profile.compatibility {
            XCTAssertTrue(reason.lowercased().contains("frozen"))
        } else {
            XCTFail("Expected refusal for DefaultAccountState=Frozen")
        }
    }

    func testDefaultAccountStateInitializedIsAllowed() throws {
        let body = Data([0x01]) // 1 = Initialized
        let mint = self.makeMint(decimals: 6, extensions: [(type: 6, body: body)])
        let profile = try Token2022Mint.parse(mint, currentEpoch: 0)
        XCTAssertEqual(profile.compatibility, .ok)
    }

    func testConfidentialTransferMintIsRefused() throws {
        let mint = self.makeMint(decimals: 6, extensions: [(type: 4, body: Data(count: 100))])
        let profile = try Token2022Mint.parse(mint, currentEpoch: 0)
        if case .refused = profile.compatibility {
            // ok
        } else {
            XCTFail("Expected refusal for ConfidentialTransferMint")
        }
    }

    func testPermanentDelegateBannerSet() throws {
        let body = Data(repeating: 0x11, count: 32)
        let mint = self.makeMint(decimals: 6, extensions: [(type: 12, body: body)])
        let profile = try Token2022Mint.parse(mint, currentEpoch: 0)
        XCTAssertEqual(profile.compatibility, .ok)
        XCTAssertTrue(profile.permanentDelegate)
    }

    func testIgnoredExtensionsDoNotRefuse() throws {
        // MetadataPointer (18), MintCloseAuthority (3), InterestBearingConfig (10),
        // TokenMetadata (19).
        let mint = self.makeMint(decimals: 6, extensions: [
            (type: 3, body: Data(count: 32)),
            (type: 10, body: Data(count: 48)),
            (type: 18, body: Data(count: 64)),
            (type: 19, body: Data(count: 80)),
        ])
        let profile = try Token2022Mint.parse(mint, currentEpoch: 0)
        XCTAssertEqual(profile.compatibility, .ok)
        XCTAssertFalse(profile.permanentDelegate)
    }

    func testUnknownExtensionsAreRefused() throws {
        // Unknown mint extensions are fail-closed.
        let mint = self.makeMint(decimals: 6, extensions: [
            (type: 9999, body: Data(repeating: 0xAA, count: 16)),
            (type: 12, body: Data(repeating: 0x11, count: 32)),
        ])
        let profile = try Token2022Mint.parse(mint, currentEpoch: 0)
        XCTAssertEqual(
            profile.compatibility,
            .refused(reason: "This token uses an unknown Token-2022 extension."))
    }

    func testMalformedExtensionLengthThrows() {
        // Build manually so length overflows the buffer.
        var data = Data(repeating: 0, count: 200)
        data[44] = 6
        data[45] = 1
        data[165] = 1
        // Type = 1, length = 50000 (way more than buffer has).
        data[166] = 0x01
        data[167] = 0x00
        data[168] = 0x50
        data[169] = 0xC3
        XCTAssertThrowsError(try Token2022Mint.parse(data, currentEpoch: 0)) { error in
            XCTAssertEqual(error as? Token2022Mint.ParseError, .malformedExtension(typeId: 1))
        }
    }
}
