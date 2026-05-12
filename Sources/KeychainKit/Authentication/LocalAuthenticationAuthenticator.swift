import Foundation
import LocalAuthentication

/// Production `BiometricAuthenticating` implementation backed by `LAContext`.
///
/// A fresh `LAContext` is created per call: `LAContext` is not safe to reuse
/// across authentication attempts because its `interactionNotAllowed` state
/// and any pending authorization linger past the first prompt. This matches
/// Apple's recommendation for single-shot biometric checks.
public struct LocalAuthenticationAuthenticator: BiometricAuthenticating {
    public init() {}

    public func authenticate(reason: String) async throws {
        let context = LAContext()
        let policy: LAPolicy = .deviceOwnerAuthentication
        let prompt = reason.isEmpty ? "Authenticate to continue" : reason
        context.localizedReason = prompt

        var probeError: NSError?
        guard context.canEvaluatePolicy(policy, error: &probeError) else {
            if let laError = probeError as? LAError {
                throw Self.mapLAError(laError)
            }
            throw KeychainError.biometryNotAvailable
        }

        try await withCheckedThrowingContinuation { (cont: CheckedContinuation<Void, Error>) in
            context.evaluatePolicy(policy, localizedReason: prompt) { success, error in
                if success {
                    cont.resume(returning: ())
                    return
                }
                if let laError = error as? LAError {
                    cont.resume(throwing: Self.mapLAError(laError))
                } else if let nsError = error as NSError? {
                    cont.resume(throwing: KeychainError.unhandledStatus(OSStatus(nsError.code)))
                } else {
                    cont.resume(throwing: KeychainError.biometricFailed)
                }
            }
        }
    }

    private static func mapLAError(_ error: LAError) -> KeychainError {
        switch error.code {
        case .userCancel, .systemCancel, .appCancel:
            .userCanceled
        case .userFallback:
            .userCanceled
        case .biometryLockout:
            .biometryLockout
        case .biometryNotAvailable:
            .biometryNotAvailable
        case .biometryNotEnrolled:
            .biometryNotEnrolled
        case .authenticationFailed, .invalidContext:
            .biometricFailed
        default:
            .biometricFailed
        }
    }
}
