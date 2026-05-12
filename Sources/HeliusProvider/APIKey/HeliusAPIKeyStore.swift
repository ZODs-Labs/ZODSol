import Foundation
import KeychainKit
import OSLog

public actor HeliusAPIKeyStore {
    public static let defaultEnvironmentVariable = "ZODSOL_HELIUS_API_KEY"

    private let store: SecureItemStore
    private let item: SecureItem
    private let environment: EnvironmentKeySource?
    private let logger = Logger(subsystem: "dev.zods.zodsol", category: "helius-api-key")
    private var announcedEnvironmentOverride = false

    /// Once the key has been read (or written) we keep it in memory for the
    /// lifetime of the actor so subsequent panel opens skip the keychain.
    private enum CacheState {
        case unloaded
        case loaded(String?)
    }

    private var cache: CacheState = .unloaded

    public init(
        secureStore: SecureItemStore,
        environment: EnvironmentKeySource? = EnvironmentKeySource(
            variableName: HeliusAPIKeyStore.defaultEnvironmentVariable))
    {
        self.store = secureStore
        self.item = SecureItem(service: "dev.zods.zodsol", account: "helius.apiKey")
        self.environment = environment
    }

    init(
        secureStore: SecureItemStore,
        item: SecureItem,
        environment: EnvironmentKeySource? = nil)
    {
        self.store = secureStore
        self.item = item
        self.environment = environment
    }

    public func currentKey() async throws -> String? {
        if let override = self.environment?.value() {
            self.announceEnvironmentOverrideIfNeeded()
            return override
        }
        if case let .loaded(value) = self.cache { return value }
        do {
            let data = try await self.store.read(self.item)
            let key = String(data: data, encoding: .utf8)
            self.cache = .loaded(key)
            return key
        } catch KeychainError.itemNotFound {
            self.cache = .loaded(nil)
            return nil
        } catch KeychainError.biometricFailed,
            KeychainError.interactionRequired,
            KeychainError.userCanceled
        {
            self.cache = .loaded(nil)
            return nil
        }
    }

    public func save(_ key: String) async throws {
        let trimmed = key.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { throw HeliusError.missingAPIKey }
        if let environment = self.environment, environment.value() != nil {
            let name = environment.name
            self.logger.notice(
                "Helius API key written to Keychain; \(name, privacy: .public) is set and still overrides on read")
        }
        try? await self.store.delete(self.item)
        try await self.store.write(
            Data(trimmed.utf8),
            to: self.item,
            accessibility: .whenUnlockedThisDeviceOnly,
            gate: .none)
        self.cache = .loaded(trimmed)
    }

    public func clear() async throws {
        try await self.store.delete(self.item)
        self.cache = .loaded(nil)
    }

    private func announceEnvironmentOverrideIfNeeded() {
        guard !self.announcedEnvironmentOverride, let environment = self.environment else { return }
        self.announcedEnvironmentOverride = true
        let name = environment.name
        self.logger.notice(
            "Helius API key sourced from \(name, privacy: .public); Keychain value is ignored while it is set")
    }
}
