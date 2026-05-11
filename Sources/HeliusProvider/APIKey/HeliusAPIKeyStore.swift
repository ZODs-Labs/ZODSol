import Foundation
import KeychainKit

public actor HeliusAPIKeyStore {
    private let store: SecureItemStore
    private let item: SecureItem

    /// Once the key has been read (or written) we keep it in memory for the
    /// lifetime of the actor so subsequent panel opens skip the keychain.
    private enum CacheState {
        case unloaded
        case loaded(String?)
    }
    private var cache: CacheState = .unloaded

    public init(secureStore: SecureItemStore, defaults: UserDefaults = .standard) {
        self.store = secureStore
        self.item = SecureItem(service: "dev.zods.zodsol", account: "helius.apiKey")
    }

    internal init(
        secureStore: SecureItemStore,
        item: SecureItem,
        defaults: UserDefaults = .standard
    ) {
        self.store = secureStore
        self.item = item
    }

    public func currentKey() async throws -> String? {
        if case .loaded(let value) = cache { return value }
        do {
            let data = try await store.read(item)
            let key = String(data: data, encoding: .utf8)
            cache = .loaded(key)
            return key
        } catch KeychainError.itemNotFound {
            cache = .loaded(nil)
            return nil
        } catch KeychainError.biometricFailed,
                KeychainError.interactionRequired,
                KeychainError.userCanceled {
            cache = .loaded(nil)
            return nil
        }
    }

    public func save(_ key: String) async throws {
        let trimmed = key.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { throw HeliusError.missingAPIKey }
        try? await store.delete(item)
        try await store.write(
            Data(trimmed.utf8),
            to: item,
            accessibility: .whenUnlockedThisDeviceOnly,
            gate: .none
        )
        cache = .loaded(trimmed)
    }

    public func clear() async throws {
        try await store.delete(item)
        cache = .loaded(nil)
    }
}
