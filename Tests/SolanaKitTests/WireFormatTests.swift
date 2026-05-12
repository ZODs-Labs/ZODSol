import XCTest
@testable import SolanaKit

final class WireFormatTests: XCTestCase {
    // MARK: - Encoding

    func testEncodeZero() {
        XCTAssertEqual(WireFormat.encodeShortU16(0), Data([0x00]))
    }

    func testEncodeOne() {
        XCTAssertEqual(WireFormat.encodeShortU16(1), Data([0x01]))
    }

    func testEncodeMaxSingleByte() {
        XCTAssertEqual(WireFormat.encodeShortU16(127), Data([0x7F]))
    }

    func testEncodeFirstTwoByte() {
        XCTAssertEqual(WireFormat.encodeShortU16(128), Data([0x80, 0x01]))
    }

    func testEncodeMaxTwoByte() {
        XCTAssertEqual(WireFormat.encodeShortU16(16383), Data([0xFF, 0x7F]))
    }

    func testEncodeFirstThreeByte() {
        XCTAssertEqual(WireFormat.encodeShortU16(16384), Data([0x80, 0x80, 0x01]))
    }

    func testEncodeMaxThreeByte() {
        XCTAssertEqual(WireFormat.encodeShortU16(65535), Data([0xFF, 0xFF, 0x03]))
    }

    // MARK: - Decoding

    func testDecodeRoundTripsAllBoundaries() throws {
        for value: UInt16 in [0, 1, 127, 128, 1000, 16383, 16384, 32768, 65535] {
            let encoded = WireFormat.encodeShortU16(value)
            var offset = 0
            let decoded = try WireFormat.decodeShortU16(from: encoded, offset: &offset)
            XCTAssertEqual(decoded, value, "round-trip failed for \(value)")
            XCTAssertEqual(offset, encoded.count, "offset wrong for \(value)")
        }
    }

    func testDecodeAdvancesOffsetForSubsequentReads() throws {
        // Concatenate three encodings: [1, 128, 16384].
        var data = WireFormat.encodeShortU16(1)
        data.append(WireFormat.encodeShortU16(128))
        data.append(WireFormat.encodeShortU16(16384))

        var offset = 0
        XCTAssertEqual(try WireFormat.decodeShortU16(from: data, offset: &offset), 1)
        XCTAssertEqual(offset, 1)
        XCTAssertEqual(try WireFormat.decodeShortU16(from: data, offset: &offset), 128)
        XCTAssertEqual(offset, 3)
        XCTAssertEqual(try WireFormat.decodeShortU16(from: data, offset: &offset), 16384)
        XCTAssertEqual(offset, 6)
    }

    func testDecodeRejectsTruncated() {
        var offset = 0
        XCTAssertThrowsError(try WireFormat.decodeShortU16(from: Data(), offset: &offset)) { error in
            XCTAssertEqual(error as? WireFormat.DecodeError, .truncated)
        }
        offset = 0
        XCTAssertThrowsError(try WireFormat.decodeShortU16(from: Data([0x80]), offset: &offset)) { error in
            XCTAssertEqual(error as? WireFormat.DecodeError, .truncated)
        }
    }

    func testDecodeRejectsOverflow() {
        // Three continuation bytes is impossible for a u16.
        var offset = 0
        XCTAssertThrowsError(try WireFormat.decodeShortU16(from: Data([0xFF, 0xFF, 0xFF]), offset: &offset)) { error in
            XCTAssertEqual(error as? WireFormat.DecodeError, .overflow)
        }
        // Payload greater than u16 fits in three bytes.
        offset = 0
        XCTAssertThrowsError(try WireFormat.decodeShortU16(from: Data([0xFF, 0xFF, 0x04]), offset: &offset)) { error in
            XCTAssertEqual(error as? WireFormat.DecodeError, .overflow)
        }
    }

    func testDecodeRejectsNonCanonical() {
        // [0x80, 0x00] encodes zero in two bytes; canonical is [0x00].
        var offset = 0
        XCTAssertThrowsError(try WireFormat.decodeShortU16(from: Data([0x80, 0x00]), offset: &offset)) { error in
            XCTAssertEqual(error as? WireFormat.DecodeError, .nonCanonical)
        }
        // [0x80, 0x80, 0x00] encodes zero in three bytes.
        offset = 0
        XCTAssertThrowsError(try WireFormat.decodeShortU16(from: Data([0x80, 0x80, 0x00]), offset: &offset)) { error in
            XCTAssertEqual(error as? WireFormat.DecodeError, .nonCanonical)
        }
    }
}
