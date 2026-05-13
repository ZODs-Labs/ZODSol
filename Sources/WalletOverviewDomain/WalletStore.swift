import Foundation
import KeychainKit
import OSLog
import SolanaKit

public actor WalletStore {
    private let defaults: UserDefaults
    private let secureStore: SecureItemStore
    private let session: WalletSession?
    private let service: String
    private let selectedWalletKey: String
    private let walletsIndexKey: String
    private let walletsIndexMigrationKey: String
    private let logger = Logger(subsystem: "dev.zods.zodsol", category: "wallet-store")

    private var indexCache: [WalletIdentity]?
    private var loadInFlight: Task<[WalletIdentity], Never>?
    private var addressCache: [UUID: WalletAddress] = [:]

    public init(
        secureStore: SecureItemStore,
        defaults: UserDefaults = .standard,
        session: WalletSession? = nil)
    {
        self.init(
            secureStore: secureStore,
            defaults: defaults,
            service: "dev.zods.zodsol",
            selectedWalletKey: "dev.zods.zodsol.selectedWalletId",
            session: session)
    }

    init(
        secureStore: SecureItemStore,
        defaults: UserDefaults,
        service: String,
        selectedWalletKey: String,
        session: WalletSession? = nil)
    {
        self.defaults = defaults
        self.secureStore = secureStore
        self.session = session
        self.service = service
        self.selectedWalletKey = selectedWalletKey
        self.walletsIndexKey = "\(service).wallets.index"
        self.walletsIndexMigrationKey = "\(service).wallets.index.migrated.v1"
    }

    public func wallets() async -> [WalletIdentity] {
        if let cache = indexCache { return cache }
        return await self.ensureLoaded()
    }

    public func add(privateKey: ImportedPrivateKey, label: String) async throws -> WalletIdentity {
        if self.indexCache == nil { _ = await self.ensureLoaded() }
        if let existing = indexCache?.first(where: { $0.address == privateKey.publicAddress }) {
            return existing
        }

        let walletId = UUID()
        var key64 = privateKey.secretKey64
        defer { key64.resetBytes(in: 0..<key64.count) }

        let privateKeyItem = SecureItem(service: service, account: "wallet.\(walletId).privateKey")
        do {
            try await secureStore.write(
                key64,
                to: privateKeyItem,
                accessibility: .whenUnlockedThisDeviceOnly,
                gate: .userPresence(prompt: "Save your Solana signing key"))
        } catch {
            self.logger.error("add(walletId=\(walletId.uuidString, privacy: .public)) keychain write failed: \(String(describing: error), privacy: .public)")
            throw error
        }

        return try await self.addStoredWallet(
            address: privateKey.publicAddress,
            label: label,
            walletId: walletId,
            createdAt: Date())
    }

    public func add(address: WalletAddress, label: String) async throws -> WalletIdentity {
        try await self.addStoredWallet(address: address, label: label, walletId: UUID(), createdAt: Date())
    }

    private func addStoredWallet(
        address: WalletAddress,
        label: String,
        walletId: UUID,
        createdAt: Date) async throws -> WalletIdentity
    {
        if self.indexCache == nil { _ = await self.ensureLoaded() }
        var updated = self.indexCache ?? []

        if let existing = updated.first(where: { $0.address == address }) {
            return existing
        }

        let identity = WalletIdentity(id: walletId, address: address, label: label, createdAt: createdAt)
        updated.append(identity)
        self.indexCache = updated
        self.addressCache[walletId] = address
        try await self.persistIndex(updated)
        return identity
    }

    public func address(for walletId: UUID) async throws -> WalletAddress {
        if let cached = addressCache[walletId] { return cached }
        if self.indexCache == nil { _ = await self.ensureLoaded() }
        guard let identity = indexCache?.first(where: { $0.id == walletId }) else {
            throw WalletOverviewError.needsSetup
        }
        self.addressCache[walletId] = identity.address
        return identity.address
    }

    public func remove(walletId: UUID) async throws {
        self.logger.info("remove start walletId=\(walletId.uuidString, privacy: .public)")
        await self.deleteKeychainItems(walletId: walletId)
        if let session { await session.lock(walletId: walletId) }
        self.addressCache.removeValue(forKey: walletId)

        if self.indexCache == nil { _ = await self.ensureLoaded() }
        var updated = self.indexCache ?? []
        let before = updated.count
        updated.removeAll { $0.id == walletId }
        self.indexCache = updated
        try await self.persistIndex(updated)

        if self.selectedWalletId() == walletId {
            self.setSelectedWallet(nil)
        }
        self.logger.info(
            "remove done walletId=\(walletId.uuidString, privacy: .public) before=\(before) after=\(updated.count)")
    }

    public func withPrivateKey<R: Sendable>(
        walletId: UUID,
        prompt: String,
        _ body: @Sendable (inout Data) async throws -> R) async throws -> R
    {
        self.logger.notice("withPrivateKey start wallet=\(walletId.uuidString, privacy: .public)")
        // Fast path: if a recent biometric unlock left the seed in the
        // session vault, skip the Keychain entirely. This is what eliminates
        // the per-send Touch ID prompt and the stale-ACL "Keychain wants
        // access" dialogs that ad-hoc-signed builds trigger on every
        // SecItemCopyMatching.
        if let session, let result = try await session.withSeed(walletId: walletId, body) {
            self.logger.notice("withPrivateKey done (cache hit) wallet=\(walletId.uuidString, privacy: .public)")
            return result
        }

        self.logger.notice(
            "withPrivateKey prompting biometric wallet=\(walletId.uuidString, privacy: .public)")
        let item = SecureItem(service: service, account: "wallet.\(walletId).privateKey")
        do {
            var buffer = try await secureStore.read(item, prompt: prompt)
            defer { buffer.resetBytes(in: 0..<buffer.count) }
            if let session {
                await session.cache(walletId: walletId, seed: buffer)
            }
            let result = try await body(&buffer)
            self.logger.notice(
                "withPrivateKey done (Keychain read) wallet=\(walletId.uuidString, privacy: .public)")
            return result
        } catch let error as KeychainError where error == .userCanceled || error == .biometricFailed {
            // Transient: user pressed Cancel or biometric did not match. The
            // stored item is fine; surface a cancellation so the UI can
            // bounce back without wiping the wallet.
            self.logger.debug("withPrivateKey transient auth failure: \(String(describing: error), privacy: .public)")
            throw WalletOverviewError.canceled
        } catch let error as KeychainError where error == .itemNotFound || error == .interactionRequired {
            // Orphan: cdhash changed (ad-hoc rebuild) or the item was wiped
            // by a prior cleanup. Evict the dead slot so a fresh import can
            // reuse it, and signal the UI to onboard the user again.
            self.logger.error("withPrivateKey orphan keychain item: \(String(describing: error), privacy: .public)")
            try? await self.secureStore.delete(item)
            throw WalletOverviewError.biometricInvalidated
        }
    }

    public func rename(walletId: UUID, to newLabel: String) async throws {
        if self.indexCache == nil { _ = await self.ensureLoaded() }
        var updated = self.indexCache ?? []
        guard let idx = updated.firstIndex(where: { $0.id == walletId }) else {
            throw WalletOverviewError.needsSetup
        }
        updated[idx].label = newLabel
        self.indexCache = updated
        try await self.persistIndex(updated)
    }

    public func selectedWalletId() -> UUID? {
        self.defaults.string(forKey: self.selectedWalletKey).flatMap(UUID.init(uuidString:))
    }

    public func setSelectedWallet(_ id: UUID?) {
        if let id {
            self.defaults.set(id.uuidString, forKey: self.selectedWalletKey)
        } else {
            self.defaults.removeObject(forKey: self.selectedWalletKey)
        }
    }

    // MARK: - Private helpers

    private func ensureLoaded() async -> [WalletIdentity] {
        if let cache = indexCache { return cache }
        if let task = loadInFlight {
            let result = await task.value
            if self.indexCache == nil { self.indexCache = result }
            return self.indexCache ?? result
        }
        let task = Task<[WalletIdentity], Never> { [weak self] in
            guard let self else { return [] }
            return await self.readIndexOrEmpty()
        }
        self.loadInFlight = task
        let result = await task.value
        if self.indexCache == nil { self.indexCache = result }
        return self.indexCache ?? result
    }

    private func readIndexOrEmpty() async -> [WalletIdentity] {
        if let data = defaults.data(forKey: walletsIndexKey) {
            if let decoded = try? JSONDecoder().decode([WalletIdentity].self, from: data) {
                return decoded
            }
            self.logger.warning("wallet index corrupted, treating as empty")
            return []
        }

        // One-time migration from the legacy keychain `wallets.index` item to
        // UserDefaults. After the flag is set we never read the keychain
        // again for the index, so dev rebuilds with unstable ad-hoc signing
        // identities stop re-prompting on panel open.
        if !self.defaults.bool(forKey: self.walletsIndexMigrationKey) {
            self.defaults.set(true, forKey: self.walletsIndexMigrationKey)
            if let migrated = await readLegacyIndex() {
                try? self.writeIndex(migrated)
                try? await self.secureStore.delete(self.legacyIndexItem)
                return migrated
            }
        }
        return []
    }

    private func persistIndex(_ snapshot: [WalletIdentity]) async throws {
        try self.writeIndex(snapshot)
    }

    private func writeIndex(_ wallets: [WalletIdentity]) throws {
        let data = try JSONEncoder().encode(wallets)
        self.defaults.set(data, forKey: self.walletsIndexKey)
        self.defaults.set(true, forKey: self.walletsIndexMigrationKey)
    }

    private var legacyIndexItem: SecureItem {
        SecureItem(service: self.service, account: "wallets.index")
    }

    private func readLegacyIndex() async -> [WalletIdentity]? {
        do {
            let data = try await secureStore.read(self.legacyIndexItem)
            return try? JSONDecoder().decode([WalletIdentity].self, from: data)
        } catch {
            return nil
        }
    }

    private func deleteKeychainItems(walletId: UUID) async {
        let privateKeyItem = SecureItem(service: service, account: "wallet.\(walletId).privateKey")
        let addressItem = SecureItem(service: service, account: "wallet.\(walletId).address")
        try? await secureStore.delete(privateKeyItem)
        try? await self.secureStore.delete(addressItem)
    }
}
