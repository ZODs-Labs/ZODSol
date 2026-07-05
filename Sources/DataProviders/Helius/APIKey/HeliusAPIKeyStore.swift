import Foundation
import KeychainKit
import OSLog

/// Helius API key storage. Resolution order:
///   1. `ZODSOL_HELIUS_API_KEY` environment variable (dev override).
///   2. `~/Library/Application Support/ZODSol/credentials.json` (primary).
///   3. Legacy Keychain item - read once, migrated into the file, then
///      deleted. Subsequent launches never touch the Keychain.
///
/// The migration eliminates the "Keychain wants access" password dialog that
/// ad-hoc-signed Homebrew builds suffer from on every release update. The
/// memory cache (`CacheState`) suppresses any further read after the first
/// for the actor's lifetime.
public actor HeliusAPIKeyStore {
    public static let defaultEnvironmentVariable = "ZODSOL_HELIUS_API_KEY"
    public static let migrationFlagDefaultsKey = "dev.zods.zodsol.helius.migrated.v1"

    private enum CacheState {
        case unloaded
        case loaded(String?)
    }

    private let fileStore: ApplicationSupportKeyStore
    private let legacySecureStore: SecureItemStore?
    private let legacyItem: SecureItem
    private let environment: EnvironmentKeySource?
    private let defaults: UserDefaults
    private let logger = Logger(subsystem: "dev.zods.zodsol", category: "helius-api-key")
    private var cache: CacheState = .unloaded
    private var announcedEnvironmentOverride = false

    /// Production initializer. Resolves the default Application Support path
    /// and treats `secureStore` as the legacy Keychain backing for one-time
    /// migration. If Application Support resolution fails (extraordinary),
    /// the file store points at a sentinel path under the temp directory so
    /// reads/writes fail gracefully rather than crashing the app.
    public init(
        secureStore: SecureItemStore,
        environment: EnvironmentKeySource? = EnvironmentKeySource(
            variableName: HeliusAPIKeyStore.defaultEnvironmentVariable),
        defaults: UserDefaults = .standard)
    {
        let fileURL: URL
        do {
            fileURL = try ApplicationSupportKeyStore.defaultFileURL()
        } catch {
            fileURL = FileManager.default.temporaryDirectory
                .appendingPathComponent("ZODSol-credentials-unresolvable.json")
        }
        self.fileStore = ApplicationSupportKeyStore(fileURL: fileURL)
        self.legacySecureStore = secureStore
        self.legacyItem = SecureItem(service: "dev.zods.zodsol", account: "helius.apiKey")
        self.environment = environment
        self.defaults = defaults
    }

    /// Test/init seam — fully injectable backends, no legacy migration unless
    /// `legacySecureStore` is supplied.
    public init(
        fileStore: ApplicationSupportKeyStore,
        legacySecureStore: SecureItemStore? = nil,
        legacyItem: SecureItem = SecureItem(service: "dev.zods.zodsol", account: "helius.apiKey"),
        environment: EnvironmentKeySource? = nil,
        defaults: UserDefaults = .standard)
    {
        self.fileStore = fileStore
        self.legacySecureStore = legacySecureStore
        self.legacyItem = legacyItem
        self.environment = environment
        self.defaults = defaults
    }

    public func currentKey() async throws -> String? {
        if let override = self.environment?.value() {
            self.announceEnvironmentOverrideIfNeeded()
            return override
        }
        if case let .loaded(value) = self.cache { return value }

        await self.runMigrationIfNeeded()

        let value = await self.fileStore.read()
        self.cache = .loaded(value)
        return value
    }

    public func save(_ key: String) async throws {
        let trimmed = key.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { throw HeliusError.missingAPIKey }
        if let environment = self.environment, environment.value() != nil {
            let name = environment.name
            self.logger.notice(
                "Helius API key written to disk; \(name, privacy: .public) is set and still overrides on read")
        }
        try await self.fileStore.write(heliusKey: trimmed)
        self.cache = .loaded(trimmed)
        self.markMigrationComplete()
        // Best-effort clean-up of any leftover Keychain item.
        if let legacySecureStore {
            try? await legacySecureStore.delete(self.legacyItem)
        }
    }

    public func clear() async throws {
        try await self.fileStore.clear()
        self.cache = .loaded(nil)
        self.markMigrationComplete()
        if let legacySecureStore {
            try? await legacySecureStore.delete(self.legacyItem)
        }
    }

    // MARK: - Private

    private func runMigrationIfNeeded() async {
        if self.defaults.bool(forKey: Self.migrationFlagDefaultsKey) { return }
        guard let legacySecureStore else {
            self.markMigrationComplete()
            return
        }
        if await self.fileStore.fileExists() {
            // Already migrated by a prior run (flag may have been cleared);
            // mark complete and drop the legacy item if it lingers.
            self.markMigrationComplete()
            try? await legacySecureStore.delete(self.legacyItem)
            return
        }
        do {
            let data = try await legacySecureStore.read(self.legacyItem)
            guard let value = String(data: data, encoding: .utf8) else {
                self.markMigrationComplete()
                return
            }
            let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmed.isEmpty {
                try? await self.fileStore.write(heliusKey: trimmed)
                self.logger.notice("migrated Helius API key from Keychain to Application Support")
            }
            try? await legacySecureStore.delete(self.legacyItem)
        } catch {
            // Legacy ACL drift / not-found / biometric rejection - the user
            // will be shown onboarding and re-enter their key once.
            self.logger.debug("Keychain migration skipped: \(String(describing: error), privacy: .public)")
        }
        self.markMigrationComplete()
    }

    private func markMigrationComplete() {
        self.defaults.set(true, forKey: Self.migrationFlagDefaultsKey)
    }

    private func announceEnvironmentOverrideIfNeeded() {
        guard !self.announcedEnvironmentOverride, let environment = self.environment else { return }
        self.announcedEnvironmentOverride = true
        let name = environment.name
        self.logger.notice(
            "Helius API key sourced from \(name, privacy: .public); disk value is ignored while it is set")
    }
}
