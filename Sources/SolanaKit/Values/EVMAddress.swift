import Foundation

/// Validation and normalization for EVM contract addresses.
///
/// We deliberately normalize to lowercase everywhere and do NOT verify the
/// EIP-55 mixed-case checksum: that needs keccak256, which Apple frameworks do
/// not provide and the repo bans third-party dependencies for. Addresses are
/// case-insensitive by value, so lowercasing loses nothing the price hosts need;
/// the indexer returning no market for a bad address is the real validity gate.
public enum EVMAddress {
    /// A bare `0x` + 40 hex address, lowercased, or nil if the whole string is
    /// not exactly one address.
    public static func normalized(_ raw: String) -> String? {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard trimmed.count == 42, trimmed.hasPrefix("0x") else { return nil }
        let hex = trimmed.dropFirst(2)
        guard hex.allSatisfy(\.isHexDigit) else { return nil }
        return "0x" + hex
    }

    /// The first `0x` + exactly-40-hex address embedded in arbitrary text, so a
    /// pasted block-explorer URL resolves. Requires the hex run to be exactly 40
    /// so a 64-hex transaction hash is not mistaken for an address.
    public static func firstAddress(in text: String) -> String? {
        let lower = text.lowercased()
        var searchStart = lower.startIndex
        while let marker = lower.range(of: "0x", range: searchStart..<lower.endIndex) {
            let hex = lower[marker.upperBound...].prefix { $0.isHexDigit }
            if hex.count == 40 {
                return "0x" + hex
            }
            searchStart = marker.upperBound
        }
        return nil
    }
}
