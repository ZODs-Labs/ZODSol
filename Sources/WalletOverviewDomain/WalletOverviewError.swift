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
