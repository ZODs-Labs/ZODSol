import KeychainKit
import XCTest
@testable import DataProviders

/// `UserDefaults` is documented thread-safe but not inferred `Sendable` under
/// Swift 6 strict concurrency. Same wrapping pattern as `PendingSendStoreTests`.
private struct Fixture: @unchecked Sendable {
    let tempDirectory: URL
    let fileURL: URL
    let fileStore: ApplicationSupportKeyStore
    let defaults: UserDefaults
    let defaultsSuiteName: String
}

private func makeFixture() -> Fixture {
    let unique = UUID().uuidString
    let tempDir = FileManager.default.temporaryDirectory
        .appendingPathComponent("zodsol-tests-\(unique)", isDirectory: true)
    let fileURL = tempDir.appendingPathComponent("credentials.json")
    let suiteName = "test.helius.\(unique)"
    let defaults = UserDefaults(suiteName: suiteName)!
    defaults.removePersistentDomain(forName: suiteName)
    return Fixture(
        tempDirectory: tempDir,
        fileURL: fileURL,
        fileStore: ApplicationSupportKeyStore(fileURL: fileURL),
        defaults: defaults,
        defaultsSuiteName: suiteName)
}

private func cleanup(_ fixture: Fixture) {
    try? FileManager.default.removeItem(at: fixture.tempDirectory)
    fixture.defaults.removePersistentDomain(forName: fixture.defaultsSuiteName)
}

private func makeStore(
    _ fixture: Fixture,
    environment: EnvironmentKeySource? = nil,
    legacy: SecureItemStore? = nil) -> HeliusAPIKeyStore
{
    HeliusAPIKeyStore(
        fileStore: fixture.fileStore,
        legacySecureStore: legacy,
        environment: environment,
        defaults: fixture.defaults)
}

final class HeliusAPIKeyStoreTests: XCTestCase {
    // MARK: - File-backed round trip

    func test_missingKey_returnsNil() async throws {
        let fixture = makeFixture()
        defer { cleanup(fixture) }
        let store = makeStore(fixture)
        let key = try await store.currentKey()
        XCTAssertNil(key)
    }

    func test_roundTrip() async throws {
        let fixture = makeFixture()
        defer { cleanup(fixture) }
        let store = makeStore(fixture)
        try await store.save("test-api-key-12345")
        let key = try await store.currentKey()
        XCTAssertEqual(key, "test-api-key-12345")
    }

    func test_clear_removesKey() async throws {
        let fixture = makeFixture()
        defer { cleanup(fixture) }
        let store = makeStore(fixture)
        try await store.save("test-api-key-12345")
        try await store.clear()
        let key = try await store.currentKey()
        XCTAssertNil(key)
    }

    func test_emptyString_rejected() async throws {
        let fixture = makeFixture()
        defer { cleanup(fixture) }
        let store = makeStore(fixture)
        do {
            try await store.save("")
            XCTFail("Should have thrown")
        } catch let error as HeliusError {
            XCTAssertEqual(error, .missingAPIKey)
        }
    }

    func test_whitespaceOnly_rejected() async throws {
        let fixture = makeFixture()
        defer { cleanup(fixture) }
        let store = makeStore(fixture)
        do {
            try await store.save("   \n  ")
            XCTFail("Should have thrown")
        } catch let error as HeliusError {
            XCTAssertEqual(error, .missingAPIKey)
        }
    }

    func test_save_trimsWhitespace() async throws {
        let fixture = makeFixture()
        defer { cleanup(fixture) }
        let store = makeStore(fixture)
        try await store.save("  trimmed-key  ")
        let key = try await store.currentKey()
        XCTAssertEqual(key, "trimmed-key")
    }

    func test_save_writesFileWith0600Permissions() async throws {
        let fixture = makeFixture()
        defer { cleanup(fixture) }
        let store = makeStore(fixture)
        try await store.save("permission-check-key")
        let attrs = try FileManager.default.attributesOfItem(atPath: fixture.fileURL.path)
        let mode = (attrs[.posixPermissions] as? NSNumber)?.intValue ?? -1
        XCTAssertEqual(mode, 0o600, "credentials.json must be owner-only readable")
    }

    func test_save_persistsAcrossActorInstances() async throws {
        let fixture = makeFixture()
        defer { cleanup(fixture) }
        let store1 = makeStore(fixture)
        try await store1.save("persistent-key")

        // Fresh store using the same backing file - simulates an app restart.
        let store2 = makeStore(fixture)
        let key = try await store2.currentKey()
        XCTAssertEqual(key, "persistent-key")
    }

    // MARK: - Environment override (no file/keychain dependency)

    func test_environmentOverride_returnsValue_withoutTouchingFile() async throws {
        let fixture = makeFixture()
        defer { cleanup(fixture) }
        let env = EnvironmentKeySource(
            variableName: "ZODSOL_HELIUS_API_KEY",
            environment: { ["ZODSOL_HELIUS_API_KEY": "env-key"] })
        let store = makeStore(fixture, environment: env)
        let key = try await store.currentKey()
        XCTAssertEqual(key, "env-key")
        XCTAssertFalse(
            FileManager.default.fileExists(atPath: fixture.fileURL.path),
            "env override must not produce a file write")
    }

    func test_environmentOverride_trimsWhitespace() async throws {
        let fixture = makeFixture()
        defer { cleanup(fixture) }
        let env = EnvironmentKeySource(
            variableName: "ZODSOL_HELIUS_API_KEY",
            environment: { ["ZODSOL_HELIUS_API_KEY": "  spaced-key  \n"] })
        let store = makeStore(fixture, environment: env)
        let key = try await store.currentKey()
        XCTAssertEqual(key, "spaced-key")
    }

    func test_environmentOverride_emptyValue_fallsThroughToFile() async throws {
        let fixture = makeFixture()
        defer { cleanup(fixture) }
        let env = EnvironmentKeySource(
            variableName: "ZODSOL_HELIUS_API_KEY",
            environment: { ["ZODSOL_HELIUS_API_KEY": ""] })
        let store = makeStore(fixture, environment: env)
        let key = try await store.currentKey()
        XCTAssertNil(key)
    }

    // MARK: - Migration flag

    func test_save_marksMigrationComplete() async throws {
        let fixture = makeFixture()
        defer { cleanup(fixture) }
        let store = makeStore(fixture)
        try await store.save("migrated-key")
        XCTAssertTrue(fixture.defaults.bool(forKey: HeliusAPIKeyStore.migrationFlagDefaultsKey))
    }

    func test_clear_marksMigrationComplete() async throws {
        let fixture = makeFixture()
        defer { cleanup(fixture) }
        let store = makeStore(fixture)
        try await store.clear()
        XCTAssertTrue(fixture.defaults.bool(forKey: HeliusAPIKeyStore.migrationFlagDefaultsKey))
    }

    // MARK: - File-store unit tests

    func test_fileStore_clearWhenMissing_isNoOp() async throws {
        let fixture = makeFixture()
        defer { cleanup(fixture) }
        try await fixture.fileStore.clear()
        let exists = await fixture.fileStore.fileExists()
        XCTAssertFalse(exists)
    }

    func test_fileStore_overwrite_replacesValue() async throws {
        let fixture = makeFixture()
        defer { cleanup(fixture) }
        try await fixture.fileStore.write(heliusKey: "first")
        try await fixture.fileStore.write(heliusKey: "second")
        let value = await fixture.fileStore.read()
        XCTAssertEqual(value, "second")
    }

    func test_fileStore_corruptedJSON_returnsNil() async throws {
        let fixture = makeFixture()
        defer { cleanup(fixture) }
        try FileManager.default.createDirectory(
            at: fixture.tempDirectory, withIntermediateDirectories: true)
        try Data("not-json".utf8).write(to: fixture.fileURL)
        let value = await fixture.fileStore.read()
        XCTAssertNil(value)
    }

    func test_fileStore_savedKeyValueShape() async throws {
        let fixture = makeFixture()
        defer { cleanup(fixture) }
        try await fixture.fileStore.write(heliusKey: "shape-key")
        let raw = try String(contentsOf: fixture.fileURL, encoding: .utf8)
        XCTAssertTrue(raw.contains("\"helius_api_key\""))
        XCTAssertTrue(raw.contains("\"shape-key\""))
    }
}
