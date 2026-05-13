import Foundation
import LocalAuthentication
import OSLog
import Security

public actor SecureItemStore {
    private let service: String
    private let logger: Logger
    private let authenticator: any BiometricAuthenticating

    public init(
        service: String,
        authenticator: any BiometricAuthenticating = LocalAuthenticationAuthenticator(),
        logger: Logger = Logger(subsystem: "dev.zods.zodsol", category: "keychain"))
    {
        self.service = service
        self.authenticator = authenticator
        self.logger = logger
    }

    /// Fresh non-interactive `LAContext`. `interactionNotAllowed = true`
    /// guarantees we never let any auth UI escape past the `evaluatePolicy`
    /// call we already made: a stale-ACL slot resolves to
    /// `errSecInteractionNotAllowed` and the caller treats it as orphan
    /// instead of popping the "Always Allow / Deny" sheet.
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
        ]
        try self.apply(accessibility, to: &addQuery)

        let searchQuery: [CFString: Any] = [
            kSecClass: kSecClassGenericPassword,
            kSecAttrService: item.service,
            kSecAttrAccount: item.account,
            kSecMatchLimit: kSecMatchLimitOne,
            kSecUseAuthenticationContext: silent,
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
        ]

        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        self.logger.debug("keychain \("read", privacy: .public) status=\(status, privacy: .public)")

        guard status == errSecSuccess else {
            self.logger.error(
                "keychain read failed account=\(item.account, privacy: .public) status=\(status, privacy: .public)")
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
        ]

        let status = SecItemCopyMatching(query as CFDictionary, nil)
        return status == errSecSuccess
    }

    /// Rename a Keychain entry the current binary is not authorized to
    /// mutate so its account slot can be reused. The legacy file keychain
    /// binds an item's ACL to the Designated Requirement of the binary that
    /// wrote it: when the DR changes (cdhash drift under ad-hoc signing,
    /// signing-identity change between dev and packaged builds) the existing
    /// item becomes opaque to us and a fresh `add` would collide. We rename
    /// the dead slot out of the way - the data is still encrypted under the
    /// prior ACL and unreadable - so the next add succeeds. The repo's
    /// `Scripts/setup_local_signing.sh` keeps the DR stable across rebuilds,
    /// so in normal operation this path is dead.
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
        try await self.authenticator.authenticate(reason: gate.localizedPrompt)
    }

    private func authenticate(reason: String) async throws {
        try await self.authenticator.authenticate(reason: reason)
    }
}
