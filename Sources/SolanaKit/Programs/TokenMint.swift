import Foundation

public struct TokenMintProfile: Sendable, Equatable {
    public let decimals: UInt8
    public let isInitialized: Bool
    public let freezeAuthority: WalletAddress?

    public init(decimals: UInt8, isInitialized: Bool, freezeAuthority: WalletAddress?) {
        self.decimals = decimals
        self.isInitialized = isInitialized
        self.freezeAuthority = freezeAuthority
    }
}

public enum TokenMint {
    public enum ParseError: Error, Sendable, Equatable {
        case tooShort
        case uninitialized
        case malformedAuthority
    }

    public static let size = 82

    public static func parse(_ accountData: Data) throws -> TokenMintProfile {
        guard accountData.count >= self.size else { throw ParseError.tooShort }
        let decimals = accountData[accountData.startIndex + 44]
        let initialized = accountData[accountData.startIndex + 45] == 1
        guard initialized else { throw ParseError.uninitialized }
        let freezeAuthority = try self.parseAuthorityOption(accountData, optionOffset: 46, keyOffset: 50)
        return TokenMintProfile(decimals: decimals, isInitialized: initialized, freezeAuthority: freezeAuthority)
    }

    private static func parseAuthorityOption(_ data: Data, optionOffset: Int, keyOffset: Int) throws -> WalletAddress? {
        let option = self.readU32(data, at: optionOffset)
        guard option != 0 else { return nil }
        guard option == 1 else { throw ParseError.malformedAuthority }
        let key = data.subdata(in: keyOffset..<(keyOffset + 32))
        return try WalletAddress(base58: Base58.encode(key))
    }

    private static func readU32(_ data: Data, at offset: Int) -> UInt32 {
        var value: UInt32 = 0
        for index in 0..<4 {
            value |= UInt32(data[data.startIndex + offset + index]) << (8 * index)
        }
        return value
    }
}
