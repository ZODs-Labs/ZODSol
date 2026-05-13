import XCTest
@testable import SolanaKit

final class TokenMintTests: XCTestCase {
    func testParseInitializedMintReadsDecimalsAndFreezeAuthority() throws {
        let freeze = Data(repeating: 7, count: 32)
        var data = Data(repeating: 0, count: TokenMint.size)
        data[44] = 6
        data[45] = 1
        writeU32(1, into: &data, at: 46)
        data.replaceSubrange(50..<82, with: freeze)

        let profile = try TokenMint.parse(data)

        XCTAssertEqual(profile.decimals, 6)
        XCTAssertTrue(profile.isInitialized)
        XCTAssertEqual(profile.freezeAuthority?.base58, Base58.encode(freeze))
    }

    func testParseUninitializedMintThrows() {
        let data = Data(repeating: 0, count: TokenMint.size)
        XCTAssertThrowsError(try TokenMint.parse(data)) { error in
            XCTAssertEqual(error as? TokenMint.ParseError, .uninitialized)
        }
    }
}

private func writeU32(_ value: UInt32, into data: inout Data, at offset: Int) {
    for index in 0..<4 {
        data[offset + index] = UInt8((value >> (8 * index)) & 0xff)
    }
}
