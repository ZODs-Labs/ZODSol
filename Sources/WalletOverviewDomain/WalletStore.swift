import Foundation
import KeychainKit
import OSLog
import SolanaKit

public actor WalletStore {
    private let defaults: UserDefaults
    private let secureStore: SecureItemStore
    private let service: String
    private let selectedWalletKey: String
    private let walletsIndexKey: String
    private let walletsIndexMigrationKey: String
    private let logger = Logger(subsystem: "dev.zods.zodsol", category: "wallet-store")

    private var indexCache: [WalletIdentity]?
    private var loadInFlight: Task<[WalletIdentity], Never>?
    private var addressCache: [UUID: WalletAddress] = [:]

    public init(secureStore: SecureItemStore, defaults: UserDefaults = .standard) {
        self.init(
            secureStore: secureStore,
            defaults: defaults,
            service: "dev.zods.zodsol",
            selectedWalletKey: "dev.zods.zodsol.selectedWalletId"
        )
    }

    internal init(
        secureStore: SecureItemStore,
        defaults: UserDefaults,
        service: String,
        selectedWalletKey: String
    ) {
        self.defaults = defaults
        self.secureStore = secureStore
        self.service = service
        self.selectedWalletKey = selectedWalletKey
        self.walletsIndexKey = "\(service).wallets.index"
        self.walletsIndexMigrationKey = "\(service).wallets.index.migrated.v1"
    }

    public func wallets() async -> [WalletIdentity] {
        if let cache = indexCache { return cache }
        return await ensureLoaded()
    }

    public func add(privateKey: ImportedPrivateKey, label: String) async throws -> WalletIdentity {
        if indexCache == nil { _ = await ensureLoaded() }
        if let existing = indexCache?.first(where: { $0.address == privateKey.publicAddress }) {
            return existing
        }

        let walletId = UUID()
        var key64 = privateKey.secretKey64
        defer { key64.resetBytes(in: 0 ..< key64.count) }

        let privateKeyItem = SecureItem(service: service, account: "wallet.\(walletId).privateKey")
        try await secureStore.write(
            key64,
            to: privateKeyItem,
            accessibility: .whenUnlockedThisDeviceOnly,
            gate: .userPresence(prompt: "Save your Solana signing key")
        )

        return try await addStoredWallet(
            address: privateKey.publicAddress,
            label: label,
            walletId: walletId,
            createdAt: Date()
        )
    }

    public func add(address: WalletAddress, label: String) async throws -> WalletIdentity {
        try await addStoredWallet(address: address, label: label, walletId: UUID(), createdAt: Date())
    }

    private func addStoredWallet(
        address: WalletAddress,
        label: String,
        walletId: UUID,
        createdAt: Date
    ) async throws -> WalletIdentity {
        if indexCache == nil { _ = await ensureLoaded() }
        var updated = indexCache ?? []

        if let existing = updated.first(where: { $0.address == address }) {
            return existing
        }

        let identity = WalletIdentity(id: walletId, address: address, label: label, createdAt: createdAt)
        updated.append(identity)
        indexCache = updated
        addressCache[walletId] = address
        try await persistIndex(updated)
        return identity
    }

    public func address(for walletId: UUID) async throws -> WalletAddress {
        if let cached = addressCache[walletId] { return cached }
        if indexCache == nil { _ = await ensureLoaded() }
        guard let identity = indexCache?.first(where: { $0.id == walletId }) else {
            throw WalletOverviewError.needsSetup
        }
        addressCache[walletId] = identity.address
        return identity.address
    }

    public func remove(walletId: UUID) async throws {
        await deleteKeychainItems(walletId: walletId)
        addressCache.removeValue(forKey: walletId)

        if indexCache == nil { _ = await ensureLoaded() }
        var updated = indexCache ?? []
        updated.removeAll { $0.id == walletId }
        indexCache = updated
        try await persistIndex(updated)

        if selectedWalletId() == walletId {
            setSelectedWallet(nil)
        }
    }

    public func withPrivateKey<R: Sendable>(
        walletId: UUID,
        prompt: String,
        _ body: @Sendable (inout Data) async throws -> R
    ) async throws -> R {
        let item = SecureItem(service: service, account: "wallet.\(walletId).privateKey")
        do {
            var buffer = try await secureStore.read(item, prompt: prompt)
            defer { buffer.resetBytes(in: 0 ..< buffer.count) }
            return try await body(&buffer)
        } catch let error as KeychainError where error == .itemNotFound {
            throw WalletOverviewError.biometricInvalidated
        }
    }

    public func rename(walletId: UUID, to newLabel: String) async throws {
        if indexCache == nil { _ = await ensureLoaded() }
        var updated = indexCache ?? []
        guard let idx = updated.firstIndex(where: { $0.id == walletId }) else {
            throw WalletOverviewError.needsSetup
        }
        updated[idx].label = newLabel
        indexCache = updated
        try await persistIndex(updated)
    }

    public func selectedWalletId() -> UUID? {
        defaults.string(forKey: selectedWalletKey).flatMap(UUID.init(uuidString:))
    }

    public func setSelectedWallet(_ id: UUID?) {
        if let id {
            defaults.set(id.uuidString, forKey: selectedWalletKey)
        } else {
            defaults.removeObject(forKey: selectedWalletKey)
        }
    }

    // MARK: - Private helpers

    private func ensureLoaded() async -> [WalletIdentity] {
        if let cache = indexCache { return cache }
        if let task = loadInFlight {
            let result = await task.value
            if indexCache == nil { indexCache = result }
            return indexCache ?? result
        }
        let task = Task<[WalletIdentity], Never> { [weak self] in
            guard let self else { return [] }
            return await self.readIndexOrEmpty()
        }
        loadInFlight = task
        let result = await task.value
        if indexCache == nil { indexCache = result }
        return indexCache ?? result
    }

    private func readIndexOrEmpty() async -> [WalletIdentity] {
        if let data = defaults.data(forKey: walletsIndexKey) {
            if let decoded = try? JSONDecoder().decode([WalletIdentity].self, from: data) {
                return decoded
            }
            logger.warning("wallet index corrupted, treating as empty")
            return []
        }

        // One-time migration from the legacy keychain `wallets.index` item to
        // UserDefaults. After the flag is set we never read the keychain
        // again for the index, so dev rebuilds with unstable ad-hoc signing
        // identities stop re-prompting on panel open.
        if !defaults.bool(forKey: walletsIndexMigrationKey) {
            defaults.set(true, forKey: walletsIndexMigrationKey)
            if let migrated = await readLegacyIndex() {
                try? writeIndex(migrated)
                try? await secureStore.delete(legacyIndexItem)
                return migrated
            }
        }
        return []
    }

    private func persistIndex(_ snapshot: [WalletIdentity]) async throws {
        try writeIndex(snapshot)
    }

    private func writeIndex(_ wallets: [WalletIdentity]) throws {
        let data = try JSONEncoder().encode(wallets)
        defaults.set(data, forKey: walletsIndexKey)
        defaults.set(true, forKey: walletsIndexMigrationKey)
    }

    private var legacyIndexItem: SecureItem {
        SecureItem(service: service, account: "wallets.index")
    }

    private func readLegacyIndex() async -> [WalletIdentity]? {
        do {
            let data = try await secureStore.read(legacyIndexItem)
            return try? JSONDecoder().decode([WalletIdentity].self, from: data)
        } catch {
            return nil
        }
    }

    private func deleteKeychainItems(walletId: UUID) async {
        let privateKeyItem = SecureItem(service: service, account: "wallet.\(walletId).privateKey")
        let addressItem = SecureItem(service: service, account: "wallet.\(walletId).address")
        try? await secureStore.delete(privateKeyItem)
        try? await secureStore.delete(addressItem)
    }
}
