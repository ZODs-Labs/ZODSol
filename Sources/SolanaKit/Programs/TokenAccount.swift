import Foundation

public struct TokenAccountProfile: Sendable, Equatable {
    public enum State: UInt8, Sendable, Equatable {
        case uninitialized = 0
        case initialized = 1
        case frozen = 2
    }

    public enum Compatibility: Sendable, Equatable {
        case ok
        case refused(reason: String)
    }

    public let mint: WalletAddress
    public let owner: WalletAddress
    public let amount: UInt64
    public let delegate: WalletAddress?
    public let state: State
    public let isNative: Bool
    public let delegatedAmount: UInt64
    public let closeAuthority: WalletAddress?
    public let compatibility: Compatibility

    public init(
        mint: WalletAddress,
        owner: WalletAddress,
        amount: UInt64,
        delegate: WalletAddress?,
        state: State,
        isNative: Bool,
        delegatedAmount: UInt64,
        closeAuthority: WalletAddress?,
        compatibility: Compatibility)
    {
        self.mint = mint
        self.owner = owner
        self.amount = amount
        self.delegate = delegate
        self.state = state
        self.isNative = isNative
        self.delegatedAmount = delegatedAmount
        self.closeAuthority = closeAuthority
        self.compatibility = compatibility
    }
}

public enum TokenAccount {
    public enum ParseError: Error, Sendable, Equatable {
        case tooShort
        case malformedPubkey
        case malformedOption(offset: Int)
        case malformedState(UInt8)
        case notAccount(accountType: UInt8)
    }

    public static let baseSize = 165
    private static let accountTypeOffset = 165
    private static let extensionStart = 166

    private enum AccountExtensionType: UInt16 {
        case immutableOwner = 7
    }

    public static func parse(_ accountData: Data) throws -> TokenAccountProfile {
        guard accountData.count >= Self.baseSize else { throw ParseError.tooShort }
        let mint = try self.readAddress(accountData, at: 0)
        let owner = try self.readAddress(accountData, at: 32)
        let amount = self.readU64(accountData, at: 64)
        let delegate = try self.readOptionalAddress(accountData, optionOffset: 72, keyOffset: 76)
        let rawState = self.byte(accountData, at: 108)
        guard let state = TokenAccountProfile.State(rawValue: rawState) else {
            throw ParseError.malformedState(rawState)
        }
        let nativeReserve = try self.readOptionalU64(accountData, optionOffset: 109, valueOffset: 113)
        let delegatedAmount = self.readU64(accountData, at: 121)
        let closeAuthority = try self.readOptionalAddress(accountData, optionOffset: 129, keyOffset: 133)
        let compatibility = try self.parseCompatibility(accountData)
        return TokenAccountProfile(
            mint: mint,
            owner: owner,
            amount: amount,
            delegate: delegate,
            state: state,
            isNative: nativeReserve != nil,
            delegatedAmount: delegatedAmount,
            closeAuthority: closeAuthority,
            compatibility: compatibility)
    }

    private static func parseCompatibility(_ accountData: Data) throws -> TokenAccountProfile.Compatibility {
        guard accountData.count > Self.accountTypeOffset else { return .ok }
        let accountType = self.byte(accountData, at: Self.accountTypeOffset)
        guard accountType == 2 else { throw ParseError.notAccount(accountType: accountType) }
        var offset = Self.extensionStart
        while offset + 4 <= accountData.count {
            let typeIdRaw = self.readU16(accountData, at: offset)
            let length = Int(self.readU16(accountData, at: offset + 2))
            let dataStart = offset + 4
            let dataEnd = dataStart + length
            if typeIdRaw == 0 { break }
            guard dataEnd <= accountData.count else { throw ParseError.tooShort }
            if let typeId = AccountExtensionType(rawValue: typeIdRaw) {
                switch typeId {
                case .immutableOwner:
                    break
                }
            } else {
                return .refused(reason: "This token account uses an unsupported Token-2022 extension.")
            }
            offset = dataEnd
        }
        return .ok
    }

    private static func readAddress(_ data: Data, at offset: Int) throws -> WalletAddress {
        guard offset + 32 <= data.count else { throw ParseError.tooShort }
        let bytes = data.subdata(in: offset..<(offset + 32))
        do {
            return try WalletAddress(base58: Base58.encode(bytes))
        } catch {
            throw ParseError.malformedPubkey
        }
    }

    private static func readOptionalAddress(_ data: Data, optionOffset: Int, keyOffset: Int) throws -> WalletAddress? {
        let option = self.readU32(data, at: optionOffset)
        guard option != 0 else { return nil }
        guard option == 1 else { throw ParseError.malformedOption(offset: optionOffset) }
        return try self.readAddress(data, at: keyOffset)
    }

    private static func readOptionalU64(_ data: Data, optionOffset: Int, valueOffset: Int) throws -> UInt64? {
        let option = self.readU32(data, at: optionOffset)
        guard option != 0 else { return nil }
        guard option == 1 else { throw ParseError.malformedOption(offset: optionOffset) }
        return self.readU64(data, at: valueOffset)
    }

    private static func byte(_ data: Data, at offset: Int) -> UInt8 {
        data[data.startIndex + offset]
    }

    private static func readU16(_ data: Data, at offset: Int) -> UInt16 {
        UInt16(byte(data, at: offset)) | (UInt16(byte(data, at: offset + 1)) << 8)
    }

    private static func readU32(_ data: Data, at offset: Int) -> UInt32 {
        var value: UInt32 = 0
        for index in 0..<4 {
            value |= UInt32(byte(data, at: offset + index)) << (8 * index)
        }
        return value
    }

    private static func readU64(_ data: Data, at offset: Int) -> UInt64 {
        var value: UInt64 = 0
        for index in 0..<8 {
            value |= UInt64(byte(data, at: offset + index)) << (8 * index)
        }
        return value
    }
}
