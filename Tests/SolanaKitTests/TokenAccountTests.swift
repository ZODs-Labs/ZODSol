import XCTest
@testable import SolanaKit

final class TokenAccountTests: XCTestCase {
    func testParseInitializedAccountReadsCoreFields() throws {
        let mint = Data(repeating: 1, count: 32)
        let owner = Data(repeating: 2, count: 32)
        let data = Self.baseAccount(mint: mint, owner: owner, amount: 42)

        let profile = try TokenAccount.parse(data)

        XCTAssertEqual(profile.mint.base58, Base58.encode(mint))
        XCTAssertEqual(profile.owner.base58, Base58.encode(owner))
        XCTAssertEqual(profile.amount, 42)
        XCTAssertEqual(profile.state, .initialized)
        XCTAssertEqual(profile.compatibility, .ok)
        XCTAssertFalse(profile.isNative)
        XCTAssertNil(profile.delegate)
        XCTAssertNil(profile.closeAuthority)
    }

    func testParseUnknownToken2022AccountExtensionRefuses() throws {
        let mint = Data(repeating: 1, count: 32)
        let owner = Data(repeating: 2, count: 32)
        var data = Self.baseAccount(mint: mint, owner: owner, amount: 42)
        data.append(2)
        appendU16(99, to: &data)
        appendU16(0, to: &data)

        let profile = try TokenAccount.parse(data)

        XCTAssertEqual(
            profile.compatibility,
            .refused(reason: "This token account uses an unsupported Token-2022 extension."))
    }

    func testParseToken2022MintShapeAsAccountFailsDiscriminator() throws {
        let mint = Data(repeating: 1, count: 32)
        let owner = Data(repeating: 2, count: 32)
        var data = Self.baseAccount(mint: mint, owner: owner, amount: 42)
        data.append(1)

        XCTAssertThrowsError(try TokenAccount.parse(data)) { error in
            XCTAssertEqual(error as? TokenAccount.ParseError, .notAccount(accountType: 1))
        }
    }

    private static func baseAccount(mint: Data, owner: Data, amount: UInt64) -> Data {
        var data = Data(repeating: 0, count: TokenAccount.baseSize)
        data.replaceSubrange(0..<32, with: mint)
        data.replaceSubrange(32..<64, with: owner)
        writeU64(amount, into: &data, at: 64)
        data[108] = TokenAccountProfile.State.initialized.rawValue
        return data
    }
}

private func writeU64(_ value: UInt64, into data: inout Data, at offset: Int) {
    for index in 0..<8 {
        data[offset + index] = UInt8((value >> (8 * index)) & 0xff)
    }
}

private func appendU16(_ value: UInt16, to data: inout Data) {
    data.append(UInt8(value & 0xff))
    data.append(UInt8((value >> 8) & 0xff))
}
