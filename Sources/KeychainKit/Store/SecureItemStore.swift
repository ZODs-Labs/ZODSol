import Foundation
import Security
import LocalAuthentication
import OSLog

public actor SecureItemStore {
    private let service: String
    private let logger: Logger

    public init(
        service: String,
        logger: Logger = Logger(subsystem: "dev.zods.zodsol", category: "keychain")
    ) {
        self.service = service
        self.logger = logger
    }

    public func write(
        _ data: Data,
        to item: SecureItem,
        accessibility: SecureAccessibility,
        gate: BiometricGate
    ) async throws {
        try await authenticateIfNeeded(for: gate)
        var query: [CFString: Any] = [
            kSecClass: kSecClassGenericPassword,
            kSecAttrService: item.service,
            kSecAttrAccount: item.account,
            kSecValueData: data
        ]
        try apply(accessibility, to: &query)

        let searchQuery: [CFString: Any] = [
            kSecClass: kSecClassGenericPassword,
            kSecAttrService: item.service,
            kSecAttrAccount: item.account,
            kSecMatchLimit: kSecMatchLimitOne
        ]

        var unused: AnyObject?
        let searchStatus = SecItemCopyMatching(searchQuery as CFDictionary, &unused)

        let status: OSStatus
        if searchStatus == errSecItemNotFound {
            status = SecItemAdd(query as CFDictionary, nil)
            logger.debug("keychain \("write", privacy: .public) status=\(status, privacy: .public)")
        } else if searchStatus == errSecSuccess {
            // Overwrite by removing the previous record entirely. This
            // sidesteps `errSecParam` from `SecItemUpdate` rejecting the
            // attribute set we built for the add path and guarantees the
            // new item is tied to the current signing identity.
            _ = SecItemDelete(searchQuery as CFDictionary)
            status = SecItemAdd(query as CFDictionary, nil)
            logger.debug("keychain \("rewrite", privacy: .public) status=\(status, privacy: .public)")
        } else {
            logger.debug("keychain \("write-check", privacy: .public) status=\(searchStatus, privacy: .public)")
            throw Self.mapStatus(searchStatus)
        }

        if status != errSecSuccess {
            throw Self.mapStatus(status)
        }
    }

    public func read(_ item: SecureItem, prompt: String? = nil) async throws -> Data {
        if let prompt {
            try await authenticate(reason: prompt)
        }

        let query: [CFString: Any] = [
            kSecClass: kSecClassGenericPassword,
            kSecAttrService: item.service,
            kSecAttrAccount: item.account,
            kSecReturnData: true,
            kSecMatchLimit: kSecMatchLimitOne
        ]

        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        logger.debug("keychain \("read", privacy: .public) status=\(status, privacy: .public)")

        guard status == errSecSuccess else {
            throw Self.mapStatus(status)
        }
        guard let data = result as? Data else {
            throw KeychainError.dataDecodingFailed
        }
        return data
    }

    public func delete(_ item: SecureItem) async throws {
        let query: [CFString: Any] = [
            kSecClass: kSecClassGenericPassword,
            kSecAttrService: item.service,
            kSecAttrAccount: item.account
        ]

        let status = SecItemDelete(query as CFDictionary)
        logger.debug("keychain \("delete", privacy: .public) status=\(status, privacy: .public)")

        if status != errSecSuccess && status != errSecItemNotFound {
            throw Self.mapStatus(status)
        }
    }

    public func contains(_ item: SecureItem) async -> Bool {
        let query: [CFString: Any] = [
            kSecClass: kSecClassGenericPassword,
            kSecAttrService: item.service,
            kSecAttrAccount: item.account,
            kSecMatchLimit: kSecMatchLimitOne
        ]

        let status = SecItemCopyMatching(query as CFDictionary, nil)
        return status == errSecSuccess
    }

    // MARK: - Biometric authentication

    private func apply(_ accessibility: SecureAccessibility, to query: inout [CFString: Any]) throws {
        switch accessibility {
        case .whenUnlockedThisDeviceOnly:
            query[kSecAttrAccessible] = kSecAttrAccessibleWhenUnlockedThisDeviceOnly
        }
    }

    private func authenticateIfNeeded(for gate: BiometricGate) async throws {
        guard gate.requiresUserPresence else { return }
        try await authenticate(reason: gate.localizedPrompt)
    }

    /// Run a Touch ID / Mac password prompt and throw a typed
    /// `KeychainError` on cancel or authentication failure.
    private func authenticate(reason: String) async throws {
        let context = LAContext()
        context.localizedReason = reason.isEmpty ? "Authenticate to continue" : reason
        var probeError: NSError?
        let policy: LAPolicy = .deviceOwnerAuthentication
        guard context.canEvaluatePolicy(policy, error: &probeError) else {
            if let probeError = probeError as? LAError {
                throw Self.mapLAError(probeError)
            }
            throw KeychainError.biometryNotAvailable
        }
        let prompt = reason.isEmpty ? "Authenticate to continue" : reason
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
            return .userCanceled
        case .userFallback:
            return .userCanceled
        case .biometryLockout:
            return .biometryLockout
        case .biometryNotAvailable:
            return .biometryNotAvailable
        case .biometryNotEnrolled:
            return .biometryNotEnrolled
        case .authenticationFailed, .invalidContext:
            return .biometricFailed
        default:
            return .biometricFailed
        }
    }
}
