import XCTest
@testable import SolanaKit

final class Base58Tests: XCTestCase {
    func testEncodeEmptyReturnsEmpty() {
        XCTAssertEqual(Base58.encode(Data()), "")
    }

    func testDecodeEmptyReturnsEmpty() throws {
        XCTAssertEqual(try Base58.decode(""), Data())
    }

    func testRoundTripPreservesLeadingZeros() throws {
        // 32 zero bytes (System program id) encodes as 32 '1's.
        let zeros = Data(repeating: 0, count: 32)
        let encoded = Base58.encode(zeros)
        XCTAssertEqual(encoded, String(repeating: "1", count: 32))
        XCTAssertEqual(try Base58.decode(encoded), zeros)
    }

    func testRoundTripPreservesRandomData() throws {
        let bytes: [UInt8] = [
            0xDE, 0xAD, 0xBE, 0xEF, 0x00, 0x11, 0x22, 0x33,
            0x44, 0x55, 0x66, 0x77, 0x88, 0x99, 0xAA, 0xBB,
            0xCC, 0xDD, 0xEE, 0xFF, 0x12, 0x34, 0x56, 0x78,
            0x9A, 0xBC, 0xDE, 0xF0, 0x0F, 0x1E, 0x2D, 0x3C,
        ]
        let data = Data(bytes)
        let encoded = Base58.encode(data)
        XCTAssertEqual(try Base58.decode(encoded), data)
    }

    func testDecodeRejectsInvalidAlphabet() {
        // '0' is not in the base58 alphabet.
        XCTAssertThrowsError(try Base58.decode("0xy")) { error in
            guard let providerError = error as? SolanaProviderError,
                  case .invalidInput = providerError
            else {
                XCTFail("Expected SolanaProviderError.invalidInput, got \(error)")
                return
            }
        }
    }
}
