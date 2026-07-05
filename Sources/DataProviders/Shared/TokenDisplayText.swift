import Foundation

/// Sanitizes untrusted token symbol and name strings before they are frozen onto
/// a ticker entry and rendered into AppKit status-item text. Strips control,
/// format (bidi overrides, zero-width) and separator scalars that could spoof
/// another symbol or blow out the menu-bar width, then hard-truncates. Normal
/// symbols and names pass through unchanged. Reusable by any token resolver.
enum TokenDisplayText {
    static func symbol(_ raw: String, fallback: String) -> String {
        let cleaned = self.sanitize(raw, maxLength: 12)
        return cleaned.isEmpty ? fallback : cleaned
    }

    static func name(_ raw: String, fallback: String) -> String {
        let cleaned = self.sanitize(raw, maxLength: 48)
        return cleaned.isEmpty ? fallback : cleaned
    }

    /// A short `0xAB..CDEF` rendering for when no symbol is available.
    static func shortAddress(_ address: String) -> String {
        guard address.count > 12 else { return address }
        return "\(address.prefix(6))..\(address.suffix(4))"
    }

    private static func sanitize(_ raw: String, maxLength: Int) -> String {
        let scalars = raw.unicodeScalars.filter { scalar in
            switch scalar.properties.generalCategory {
            case .control, .format, .lineSeparator, .paragraphSeparator, .surrogate, .privateUse:
                false
            default:
                true
            }
        }
        var text = String(String.UnicodeScalarView(scalars)).trimmingCharacters(in: .whitespacesAndNewlines)
        if text.count > maxLength {
            text = String(text.prefix(maxLength)).trimmingCharacters(in: .whitespacesAndNewlines)
        }
        return text
    }
}
