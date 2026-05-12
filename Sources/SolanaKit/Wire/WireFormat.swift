import Foundation

/// Low-level Solana wire-format helpers.
///
/// `short_u16` (compact-u16) is the length prefix used by every `Vec<T>` in
/// Solana's transaction encoding. Sequential 7-bit groups, little-endian,
/// high bit set when more bytes follow. A u16 value occupies at most 3 bytes.
public enum WireFormat {
    public enum DecodeError: Error, Sendable, Equatable {
        /// The buffer ended mid-varint.
        case truncated
        /// The encoded value exceeded 2^16 - 1 (more than three continuation bytes).
        case overflow
        /// A length-prefixed slice's length pointed past the end of the buffer.
        case lengthOutOfBounds
        /// A multi-byte short_u16 used a non-minimal encoding.
        case nonCanonical
    }

    /// Encode a value in compact-u16 form. 0-127 fits in 1 byte; 128-16383 in
    /// 2 bytes; 16384-65535 in 3 bytes.
    public static func encodeShortU16(_ value: UInt16) -> Data {
        var data = Data()
        data.reserveCapacity(3)
        var remaining = UInt32(value)
        repeat {
            var byte = UInt8(remaining & 0x7F)
            remaining >>= 7
            if remaining != 0 {
                byte |= 0x80
            }
            data.append(byte)
        } while remaining != 0
        return data
    }

    /// Decode a compact-u16 starting at `offset`. Advances `offset` past the
    /// last byte read. Throws on truncation, overflow, or non-canonical
    /// encoding (e.g. trailing zero continuation bytes).
    public static func decodeShortU16(from data: Data, offset: inout Int) throws -> UInt16 {
        var value: UInt32 = 0
        for byteIndex in 0..<3 {
            guard offset < data.count else { throw DecodeError.truncated }
            let byte = data[data.startIndex + offset]
            offset += 1
            let payload = UInt32(byte & 0x7F)
            let hasContinuation = (byte & 0x80) != 0

            // Reject non-canonical encodings: a continuation byte of zero would
            // re-encode a smaller value, and a non-continuation byte with zero
            // payload after the first byte is the same.
            if byteIndex > 0, payload == 0, !hasContinuation {
                throw DecodeError.nonCanonical
            }

            value |= payload << (7 * byteIndex)

            if !hasContinuation {
                guard value <= UInt32(UInt16.max) else { throw DecodeError.overflow }
                return UInt16(value)
            }
        }
        // After three bytes we must be done; if the third byte still had a
        // continuation flag we have an overflow.
        throw DecodeError.overflow
    }
}
