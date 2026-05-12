import Foundation

/// Test seam: a `BiometricAuthenticating` that never invokes `LAContext`.
///
/// XCTest suites that exercise `SecureItemStore` or any code path that ends
/// up calling `secureStore.read(_:prompt:)` should inject this rather than
/// the production `LocalAuthenticationAuthenticator`, so `swift test` does
/// not spawn a real Touch ID dialog on the developer's machine.
///
/// Outcome is chosen at construction time: `.allow` returns immediately,
/// `.deny(_:)` throws the supplied `KeychainError` synchronously.
public struct StaticBiometricAuthenticator: BiometricAuthenticating {
    public enum Outcome: Sendable, Equatable {
        case allow
        case deny(KeychainError)
    }

    public let outcome: Outcome

    public init(_ outcome: Outcome = .allow) {
        self.outcome = outcome
    }

    public func authenticate(reason _: String) async throws {
        switch self.outcome {
        case .allow:
            return
        case let .deny(error):
            throw error
        }
    }
}
