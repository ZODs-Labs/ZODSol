import Foundation

public enum WalletOverviewError: Error, Sendable, Equatable {
    case needsSetup
    case networkUnavailable
    case rateLimited(retryAfter: Duration?)
    case unauthorized
    case providerUnavailable(String)
    case malformedResponse(String)
    case biometricInvalidated
    case canceled
    case unknown(String)
}

extension WalletOverviewError: LocalizedError {
    public var errorDescription: String? {
        switch self {
        case .needsSetup:
            "Add a wallet to continue."
        case .networkUnavailable:
            "Network is unavailable. Check your internet connection and try again."
        case let .rateLimited(retryAfter):
            if let retryAfter {
                "Rate limited. Retry in \(Self.format(retryAfter))."
            } else {
                "Rate limited. Try again in a moment."
            }
        case .unauthorized:
            "Helius rejected the API key. Update it in Settings and try again."
        case let .providerUnavailable(detail):
            "Service is unavailable: \(detail)"
        case let .malformedResponse(detail):
            detail
        case .biometricInvalidated:
            "Wallet authentication failed. Remove and re-import this wallet to keep signing."
        case .canceled:
            "Cancelled."
        case let .unknown(detail):
            "Unexpected error: \(detail)"
        }
    }

    private static func format(_ duration: Duration) -> String {
        let seconds = Double(duration.components.seconds)
        if seconds < 60 { return "\(Int(seconds.rounded()))s" }
        let minutes = Int((seconds / 60).rounded())
        return "\(minutes)m"
    }
}
