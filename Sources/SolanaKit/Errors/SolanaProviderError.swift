import Foundation

/// Errors thrown by any `SolanaProvider` implementation at the SolanaKit boundary.
///
/// Provider-specific errors (RPC, Helius, transport-level) are mapped to one of
/// these cases by the concrete provider so that callers in `WalletOverviewDomain`
/// and the UI layer never need to know which backend produced the failure.
public enum SolanaProviderError: Error, Sendable, Equatable {
    /// The device or network stack reported no reachable route.
    case networkUnavailable

    /// The provider returned a rate-limit response. `retryAfter`, when present,
    /// communicates the minimum delay the provider asked the caller to honor.
    case rateLimited(retryAfter: Duration?)

    /// The provider rejected the request because the credential is missing,
    /// invalid, or revoked.
    case unauthorized

    /// The provider is reachable but cannot service the request right now.
    /// `message` carries a short, log-safe reason (never a secret).
    case providerUnavailable(message: String)

    /// The provider responded with a payload that failed validation or decoding.
    /// `message` describes what was malformed.
    case malformedResponse(String)

    /// A caller-supplied input failed validation before any network call was
    /// made (for example: a base58 string that does not decode to 32 bytes).
    case invalidInput(String)

    /// The work was canceled — either by structured cancellation in the caller's
    /// task tree or by an explicit cancellation request.
    case canceled
}
