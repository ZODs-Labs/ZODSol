import Foundation
import SolanaKit

public enum FiatMode: String, Sendable, Codable, Equatable {
    case token
    case fiat
}

public struct SendAmountInput: Sendable, Equatable {
    public let balanceBaseUnits: UInt64
    public let decimals: UInt8
    public let priceUSD: Decimal?
    public let feeReserveLamports: Lamports
    public let rentReserveLamports: Lamports
    public let isNativeSOL: Bool

    public init(
        balanceBaseUnits: UInt64,
        decimals: UInt8,
        priceUSD: Decimal?,
        feeReserveLamports: Lamports,
        rentReserveLamports: Lamports,
        isNativeSOL: Bool)
    {
        self.balanceBaseUnits = balanceBaseUnits
        self.decimals = decimals
        self.priceUSD = priceUSD
        self.feeReserveLamports = feeReserveLamports
        self.rentReserveLamports = rentReserveLamports
        self.isNativeSOL = isNativeSOL
    }
}

public enum SendAmountIntent: Sendable, Equatable {
    case percentage(Double)
    case manual(text: String, mode: FiatMode)
}

public struct SendAmountResult: Sendable, Equatable {
    public let baseUnits: UInt64
    public let displayToken: String
    public let inputTokenText: String
    public let displayFiat: String?
    public let exceedsBalance: Bool
    public let isZero: Bool
    public let roundedToZero: Bool
    public let decimalsError: Bool

    public init(
        baseUnits: UInt64,
        displayToken: String,
        inputTokenText: String,
        displayFiat: String?,
        exceedsBalance: Bool,
        isZero: Bool,
        roundedToZero: Bool,
        decimalsError: Bool)
    {
        self.baseUnits = baseUnits
        self.displayToken = displayToken
        self.inputTokenText = inputTokenText
        self.displayFiat = displayFiat
        self.exceedsBalance = exceedsBalance
        self.isZero = isZero
        self.roundedToZero = roundedToZero
        self.decimalsError = decimalsError
    }
}
