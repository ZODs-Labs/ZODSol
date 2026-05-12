import Foundation

/// Abstraction over the user-presence prompt invoked before a privileged
/// Keychain operation. Conforming types decide whether to invoke
/// `LAContext.evaluatePolicy(.deviceOwnerAuthentication)`, no-op, or fail.
///
/// The protocol exists so XCTest suites can inject a fake authenticator that
/// never prompts the developer's Touch ID sensor during routine `swift test`
/// runs. Production code passes `LocalAuthenticationAuthenticator()` (the
/// default in `SecureItemStore`).
public protocol BiometricAuthenticating: Sendable {
    /// Drive the platform's user-presence prompt with `reason` as the
    /// localized message. Throws a typed `KeychainError` on user-cancel,
    /// biometric lockout, missing enrollment or any other LAError.
    func authenticate(reason: String) async throws
}
