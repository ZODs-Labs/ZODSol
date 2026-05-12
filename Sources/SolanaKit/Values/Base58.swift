import Foundation

public enum Base58 {
    public static let alphabet = Array("123456789ABCDEFGHJKLMNPQRSTUVWXYZabcdefghijkmnopqrstuvwxyz")

    private static let alphabetLookup: [UInt8: UInt8] = {
        var map = [UInt8: UInt8]()
        for (index, char) in alphabet.enumerated() {
            map[char.asciiValue!] = UInt8(index)
        }
        return map
    }()

    public static func decode(_ string: String) throws -> Data {
        guard !string.isEmpty else {
            return Data()
        }

        let bytes = Array(string.utf8)

        for byte in bytes {
            guard self.alphabetLookup[byte] != nil else {
                throw SolanaProviderError.invalidInput(
                    "invalid base58 character: \(Unicode.Scalar(byte))")
            }
        }

        var result = [UInt8](repeating: 0, count: bytes.count)
        var length = 0

        for byte in bytes {
            var carry = Int(alphabetLookup[byte]!)
            var j = 0
            var idx = result.count - 1
            while idx >= 0, carry != 0 || j < length {
                carry += 58 * Int(result[idx])
                result[idx] = UInt8(carry % 256)
                carry /= 256
                j += 1
                idx -= 1
            }
            length = j
        }

        let leadingZeros = bytes.prefix(while: { $0 == self.alphabet[0].asciiValue! }).count
        let startIndex = result.firstIndex(where: { $0 != 0 }) ?? result.endIndex
        let decoded = [UInt8](repeating: 0, count: leadingZeros) + result[startIndex...]
        return Data(decoded)
    }

    public static func encode(_ data: Data) -> String {
        guard !data.isEmpty else {
            return ""
        }

        let bytes = Array(data)
        var digits = [UInt8](repeating: 0, count: bytes.count * 2)
        var length = 0

        for byte in bytes {
            var carry = Int(byte)
            var j = 0
            var idx = digits.count - 1
            while idx >= 0, carry != 0 || j < length {
                carry += 256 * Int(digits[idx])
                digits[idx] = UInt8(carry % 58)
                carry /= 58
                j += 1
                idx -= 1
            }
            length = j
        }

        let leadingZeros = bytes.prefix(while: { $0 == 0 }).count
        let startIndex = digits.firstIndex(where: { $0 != 0 }) ?? digits.endIndex
        return String(repeating: self.alphabet[0], count: leadingZeros)
            + String(digits[startIndex...].map { self.alphabet[Int($0)] })
    }
}
