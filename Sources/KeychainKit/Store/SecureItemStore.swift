import Foundation
import LocalAuthentication
import OSLog
import Security

public actor SecureItemStore {
    private let service: String
    private let logger: Logger

    public init(
        service: String,
        logger: Logger = Logger(subsystem: "dev.zods.zodsol", category: "keychain"))
    {
        self.service = service
        self.logger = logger
    }

    /// Fresh `LAContext` per call. `interactionNotAllowed = true` suppresses
    /// the biometric/`SecAccessControl` prompt path. The legacy login-keychain
    /// "Always Allow / Deny" ACL prompt that ad-hoc rebuilds trigger is a
    /// separate UI path - `kSecUseAuthenticationUI: kSecUseAuthenticationUIFail`
    /// (applied alongside this context on every query) is what suppresses
    /// that one, returning `errSecInteractionNotAllowed` so the stale-ACL
    /// case can be handled in code.
    private func nonInteractiveContext() -> LAContext {
        let context = LAContext()
        context.interactionNotAllowed = true
        return context
    }

    public func write(
        _ data: Data,
        to item: SecureItem,
        accessibility: SecureAccessibility,
        gate: BiometricGate) async throws
    {
        try await self.authenticateIfNeeded(for: gate)

        let silent = self.nonInteractiveContext()
        var addQuery: [CFString: Any] = [
            kSecClass: kSecClassGenericPassword,
            kSecAttrService: item.service,
            kSecAttrAccount: item.account,
            kSecValueData: data,
            kSecUseAuthenticationContext: silent,
            kSecUseAuthenticationUI: kSecUseAuthenticationUIFail,
        ]
        try self.apply(accessibility, to: &addQuery)

        let searchQuery: [CFString: Any] = [
            kSecClass: kSecClassGenericPassword,
            kSecAttrService: item.service,
            kSecAttrAccount: item.account,
            kSecMatchLimit: kSecMatchLimitOne,
            kSecUseAuthenticationContext: silent,
            kSecUseAuthenticationUI: kSecUseAuthenticationUIFail,
        ]

        var unused: AnyObject?
        let searchStatus = SecItemCopyMatching(searchQuery as CFDictionary, &unused)

        if searchStatus == errSecItemNotFound {
            try self.performAdd(addQuery, label: "add")
            return
        }

        if searchStatus != errSecSuccess {
            self.logger.debug("keychain \("write-check", privacy: .public) status=\(searchStatus, privacy: .public)")
            throw Self.mapStatus(searchStatus)
        }

        var updateAttrs: [CFString: Any] = [kSecValueData: data]
        try apply(accessibility, to: &updateAttrs)
        let updateStatus = SecItemUpdate(searchQuery as CFDictionary, updateAttrs as CFDictionary)
        self.logger.debug("keychain \("update", privacy: .public) status=\(updateStatus, privacy: .public)")
        switch updateStatus {
        case errSecSuccess:
            return
        case errSecAuthFailed, errSecInteractionNotAllowed:
            try self.evictOrphan(matching: searchQuery)
            try self.performAdd(addQuery, label: "add-after-evict")
        case errSecParam:
            try self.clearOrEvict(matching: searchQuery)
            try self.performAdd(addQuery, label: "add-after-delete")
        default:
            throw Self.mapStatus(updateStatus)
        }
    }

    private func performAdd(_ query: [CFString: Any], label: StaticString) throws {
        let status = SecItemAdd(query as CFDictionary, nil)
        self.logger.debug("keychain \(label, privacy: .public) status=\(status, privacy: .public)")
        if status != errSecSuccess { throw Self.mapStatus(status) }
    }

    private func clearOrEvict(matching searchQuery: [CFString: Any]) throws {
        let status = SecItemDelete(searchQuery as CFDictionary)
        if status == errSecSuccess || status == errSecItemNotFound { return }
        if Self.isOrphanStatus(status) {
            try self.evictOrphan(matching: searchQuery)
            return
        }
        throw Self.mapStatus(status)
    }

    public func read(_ item: SecureItem, prompt: String? = nil) async throws -> Data {
        if let prompt {
            try await self.authenticate(reason: prompt)
        }

        let query: [CFString: Any] = [
            kSecClass: kSecClassGenericPassword,
            kSecAttrService: item.service,
            kSecAttrAccount: item.account,
            kSecReturnData: true,
            kSecMatchLimit: kSecMatchLimitOne,
            kSecUseAuthenticationContext: self.nonInteractiveContext(),
            kSecUseAuthenticationUI: kSecUseAuthenticationUIFail,
        ]

        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        self.logger.debug("keychain \("read", privacy: .public) status=\(status, privacy: .public)")

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
            kSecUseAuthenticationContext: self.nonInteractiveContext(),
            kSecUseAuthenticationUI: kSecUseAuthenticationUIFail,
        ]

        let status = SecItemDelete(query as CFDictionary)
        self.logger.debug("keychain \("delete", privacy: .public) status=\(status, privacy: .public)")

        if status == errSecSuccess || status == errSecItemNotFound { return }

        if Self.isOrphanStatus(status) {
            try self.evictOrphan(matching: query)
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
            kSecUseAuthenticationContext: self.nonInteractiveContext(),
            kSecUseAuthenticationUI: kSecUseAuthenticationUIFail,
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
            kSecAttrAccount: "\(originalAccount).\(suffix)",
        ]
        let status = SecItemUpdate(searchQuery as CFDictionary, rename as CFDictionary)
        self.logger.debug("keychain \("evict-orphan", privacy: .public) status=\(status, privacy: .public)")
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
        try await self.authenticate(reason: gate.localizedPrompt)
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
