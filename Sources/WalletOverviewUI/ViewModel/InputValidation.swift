import Foundation

public enum InputValidation: Sendable, Equatable {
    case ok
    case noBalance
    case belowFeeReserve
    case sendingToSelf
    case offCurveForSol
    case knownProgramRecipient
    case freshRecipientATA
    case unsupportedToken2022(reason: String)
    case amountExceedsBalance
    case amountTooSmall
    case decimalsExceedMint(decimals: UInt8)
    case quoteError(String)
}

extension InputValidation {
    var userMessage: String {
        switch self {
        case .ok: ""
        case .noBalance: "This wallet has no balance for this asset."
        case .belowFeeReserve: "Not enough SOL to cover the network fee."
        case .sendingToSelf: "You are sending to your own address."
        case .offCurveForSol: "SOL cannot be sent to a program-derived address."
        case .knownProgramRecipient: "That address is a Solana program, not a wallet."
        case .freshRecipientATA: "Recipient does not have a token account yet. The transfer will create one."
        case let .unsupportedToken2022(reason): reason
        case .amountExceedsBalance: "Amount exceeds available balance."
        case .amountTooSmall: "Amount is too small to send."
        case let .decimalsExceedMint(decimals): "This token allows at most \(decimals) decimal places."
        case let .quoteError(message): message
        }
    }
}
