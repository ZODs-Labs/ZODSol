import Foundation

/// Little-endian byte serializers for the primitive integer widths used in
/// Solana instruction data. Kept internal: program-instruction files are the
/// only callers and they want raw `Data` to append.
enum LittleEndianEncoder {
    static func appendUInt32(_ value: UInt32, to data: inout Data) {
        data.append(UInt8(value & 0xFF))
        data.append(UInt8((value >> 8) & 0xFF))
        data.append(UInt8((value >> 16) & 0xFF))
        data.append(UInt8((value >> 24) & 0xFF))
    }

    static func appendUInt64(_ value: UInt64, to data: inout Data) {
        for shift: UInt64 in stride(from: 0, to: 64, by: 8) {
            data.append(UInt8((value >> shift) & 0xFF))
        }
    }
}
