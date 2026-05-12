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

    /// Fresh `LAContext` per call. Setting `interactionNotAllowed = true` and
    /// passing it via `kSecUseAuthenticationContext` is the modern way to tell
    /// `SecItem*` operations to never present UI - the legacy login-keychain
    /// password prompt that ad-hoc rebuilds otherwise trigger is suppressed,
    /// and the call fails fast with `errSecInteractionNotAllowed` so we can
    /// handle the stale-ACL case in code.
    private func nonInteractiveContext() -> LAContext {
        let context = LAContext()
        context.interactionNotAllowed = true
        return context
    }

    public func write(
        _ data: Data,
        to item: SecureItem,
        accessibility: SecureAccessibility,
        gate: BiometricGate
    ) async throws {
        try await authenticateIfNeeded(for: gate)

        let silent = nonInteractiveContext()
        var addQuery: [CFString: Any] = [
            kSecClass: kSecClassGenericPassword,
            kSecAttrService: item.service,
            kSecAttrAccount: item.account,
            kSecValueData: data,
            kSecUseAuthenticationContext: silent
        ]
        try apply(accessibility, to: &addQuery)

        let searchQuery: [CFString: Any] = [
            kSecClass: kSecClassGenericPassword,
            kSecAttrService: item.service,
            kSecAttrAccount: item.account,
            kSecMatchLimit: kSecMatchLimitOne,
            kSecUseAuthenticationContext: silent
        ]

        var unused: AnyObject?
        let searchStatus = SecItemCopyMatching(searchQuery as CFDictionary, &unused)

        if searchStatus == errSecItemNotFound {
            try performAdd(addQuery, label: "add")
            return
        }

        if searchStatus != errSecSuccess {
            logger.debug("keychain \("write-check", privacy: .public) status=\(searchStatus, privacy: .public)")
            throw Self.mapStatus(searchStatus)
        }

        var updateAttrs: [CFString: Any] = [kSecValueData: data]
        try apply(accessibility, to: &updateAttrs)
        let updateStatus = SecItemUpdate(searchQuery as CFDictionary, updateAttrs as CFDictionary)
        logger.debug("keychain \("update", privacy: .public) status=\(updateStatus, privacy: .public)")
        switch updateStatus {
        case errSecSuccess:
            return
        case errSecAuthFailed, errSecInteractionNotAllowed:
            try evictOrphan(matching: searchQuery)
            try performAdd(addQuery, label: "add-after-evict")
        case errSecParam:
            try clearOrEvict(matching: searchQuery)
            try performAdd(addQuery, label: "add-after-delete")
        default:
            throw Self.mapStatus(updateStatus)
        }
    }

    private func performAdd(_ query: [CFString: Any], label: StaticString) throws {
        let status = SecItemAdd(query as CFDictionary, nil)
        logger.debug("keychain \(label, privacy: .public) status=\(status, privacy: .public)")
        if status != errSecSuccess { throw Self.mapStatus(status) }
    }

    private func clearOrEvict(matching searchQuery: [CFString: Any]) throws {
        let status = SecItemDelete(searchQuery as CFDictionary)
        if status == errSecSuccess || status == errSecItemNotFound { return }
        if Self.isOrphanStatus(status) {
            try evictOrphan(matching: searchQuery)
            return
        }
        throw Self.mapStatus(status)
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
            kSecMatchLimit: kSecMatchLimitOne,
            kSecUseAuthenticationContext: nonInteractiveContext()
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
            kSecAttrAccount: item.account,
            kSecUseAuthenticationContext: nonInteractiveContext()
        ]

        let status = SecItemDelete(query as CFDictionary)
        logger.debug("keychain \("delete", privacy: .public) status=\(status, privacy: .public)")

        if status == errSecSuccess || status == errSecItemNotFound { return }

        if Self.isOrphanStatus(status) {
            try evictOrphan(matching: query)
            return
        }

        throw Self.mapStatus(status)
    }

    public func contains(_ item: SecureItem) async -> Bool {
        let query: [CFString: Any] = [
            kSecClass: kSecClassGenericPassword,
            kSecAttrService: item.service,
            kSecAttrAccount: item.account,
            kSecMatchLimit: kSecMatchLimitOne,
            kSecUseAuthenticationContext: nonInteractiveContext()
        ]

        let status = SecItemCopyMatching(query as CFDictionary, nil)
        return status == errSecSuccess
    }

    /// Rename a Keychain entry we are not authorized to mutate so the account
    /// slot can be reused. Ad-hoc rebuilds change the binary's signing hash,
    /// which leaves prior items "owned" by a defunct identity. We rename them
    /// out of the way (the data is still encrypted under the prior ACL and
    /// cannot be read) so the next add does not collide.
    private func evictOrphan(matching searchQuery: [CFString: Any]) throws {
        let suffix = "orphan.\(UUID().uuidString)"
        let originalAccount = (searchQuery[kSecAttrAccount] as? String) ?? ""
        let rename: [CFString: Any] = [
            kSecAttrAccount: "\(originalAccount).\(suffix)"
        ]
        let status = SecItemUpdate(searchQuery as CFDictionary, rename as CFDictionary)
        logger.debug("keychain \("evict-orphan", privacy: .public) status=\(status, privacy: .public)")
        if status == errSecSuccess || status == errSecItemNotFound { return }

        let deleteStatus = SecItemDelete(searchQuery as CFDictionary)
        if deleteStatus == errSecSuccess || deleteStatus == errSecItemNotFound { return }

        throw Self.mapStatus(status)
    }

    private static func isOrphanStatus(_ status: OSStatus) -> Bool {
        status == errSecAuthFailed || status == errSecInteractionNotAllowed
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
