import CryptoKit
import Foundation
import SolanaKit

public struct ImportedPrivateKey: Sendable {
    public let publicAddress: WalletAddress
    internal let secretKey64: Data

    internal init(publicAddress: WalletAddress, secretKey64: Data) {
        self.publicAddress = publicAddress
        self.secretKey64 = secretKey64
    }

    public static func parse(_ text: String) throws -> ImportedPrivateKey {
        let raw = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !raw.isEmpty else {
            throw WalletOverviewError.malformedResponse("Paste a Solana private key to continue.")
        }

        var secretKey64: Data = try decodeBytes(from: raw)
        let seed = secretKey64.prefix(32)
        let providedPubKey = secretKey64.suffix(32)

        let privateKey: Curve25519.Signing.PrivateKey
        do {
            privateKey = try Curve25519.Signing.PrivateKey(rawRepresentation: seed)
        } catch {
            secretKey64.resetBytes(in: 0 ..< secretKey64.count)
            throw WalletOverviewError.malformedResponse("Invalid private-key seed.")
        }

        let derivedPubKey = privateKey.publicKey.rawRepresentation
        guard derivedPubKey == Data(providedPubKey) else {
            secretKey64.resetBytes(in: 0 ..< secretKey64.count)
            throw WalletOverviewError.malformedResponse(
                "Private key does not match its public key. Re-export from your wallet and paste the 64-byte secret."
            )
        }

        do {
            let address = try WalletAddress(base58: Base58.encode(derivedPubKey))
            return ImportedPrivateKey(publicAddress: address, secretKey64: secretKey64)
        } catch {
            secretKey64.resetBytes(in: 0 ..< secretKey64.count)
            throw WalletOverviewError.malformedResponse("Derived public key is not a valid Solana address.")
        }
    }

    private static func decodeBytes(from text: String) throws -> Data {
        if looksLikeByteArray(text) {
            return try decodeByteArray(text)
        }
        if looksLikeHex(text) {
            return try decodeHex(text)
        }
        return try decodeBase58(text)
    }

    private static func looksLikeByteArray(_ text: String) -> Bool {
        if text.hasPrefix("[") { return true }
        let firstChar = text.first { !$0.isWhitespace }
        guard let firstChar, firstChar.isNumber else { return false }
        return text.contains(",") || text.contains("\n")
    }

    private static func decodeByteArray(_ text: String) throws -> Data {
        var body = text
        if body.hasPrefix("[") { body.removeFirst() }
        if body.hasSuffix("]") { body.removeLast() }

        let tokens = body
            .split { ch in ch == "," || ch == " " || ch == "\n" || ch == "\r" || ch == "\t" }
            .map(String.init)
            .filter { !$0.isEmpty }

        guard !tokens.isEmpty else {
            throw WalletOverviewError.malformedResponse(
                "The byte array is empty. Expected 64 numbers between 0 and 255."
            )
        }
        guard tokens.count == 64 else {
            throw WalletOverviewError.malformedResponse(
                "Expected 64 bytes; got \(tokens.count). A Solana private key is exactly 64 numbers."
            )
        }

        var bytes: [UInt8] = []
        bytes.reserveCapacity(64)
        for (offset, token) in tokens.enumerated() {
            guard let value = Int(token) else {
                throw WalletOverviewError.malformedResponse("Byte \(offset + 1) (\"\(token)\") is not a number.")
            }
            guard (0 ... 255).contains(value) else {
                throw WalletOverviewError.malformedResponse("Byte \(offset + 1) (\(value)) must be between 0 and 255.")
            }
            bytes.append(UInt8(value))
        }
        return Data(bytes)
    }

    private static func looksLikeHex(_ text: String) -> Bool {
        var normalized = text
        if normalized.hasPrefix("0x") || normalized.hasPrefix("0X") {
            normalized.removeFirst(2)
        }
        normalized = normalized.filter { !$0.isWhitespace }
        guard normalized.count == 128 else { return false }
        return normalized.allSatisfy(\.isHexDigit)
    }

    private static func decodeHex(_ text: String) throws -> Data {
        var normalized = text
        if normalized.hasPrefix("0x") || normalized.hasPrefix("0X") {
            normalized.removeFirst(2)
        }
        normalized = normalized.filter { !$0.isWhitespace }

        var bytes: [UInt8] = []
        bytes.reserveCapacity(64)
        var index = normalized.startIndex
        while index < normalized.endIndex {
            let next = normalized.index(index, offsetBy: 2)
            let pair = String(normalized[index ..< next])
            guard let value = UInt8(pair, radix: 16) else {
                throw WalletOverviewError.malformedResponse("Invalid hex byte \"\(pair)\".")
            }
            bytes.append(value)
            index = next
        }
        return Data(bytes)
    }

    private static func decodeBase58(_ text: String) throws -> Data {
        let decoded: Data
        do {
            decoded = try Base58.decode(text)
        } catch {
            throw WalletOverviewError.malformedResponse(
                "Could not read the private key. Paste a 64-byte secret as a base58 string, JSON byte array, or hex."
            )
        }
        guard decoded.count == 64 else {
            throw WalletOverviewError.malformedResponse(
                "Decoded base58 was \(decoded.count) bytes; a Solana private key is exactly 64."
            )
        }
        return decoded
    }
}
