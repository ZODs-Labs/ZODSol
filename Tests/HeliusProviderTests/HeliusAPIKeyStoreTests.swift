import KeychainKit
import XCTest
@testable import HeliusProvider

final class HeliusAPIKeyStoreTests: XCTestCase {
    private var store: HeliusAPIKeyStore?
    private let testItem = SecureItem(
        service: "dev.zods.zodsol.test",
        account: "helius.apiKey.test")

    override func setUp() async throws {
        guard ProcessInfo.processInfo.environment["ZODSOL_KEYCHAIN_TEST"] != nil else {
            store = nil
            return
        }
        let secureStore = SecureItemStore(service: "dev.zods.zodsol.test")
        let store = HeliusAPIKeyStore(secureStore: secureStore, item: testItem)
        self.store = store
        try await store.clear()
    }

    override func tearDown() async throws {
        try? await self.store?.clear()
        self.store = nil
    }

    func test_missingKey_returnsNil() async throws {
        let store = try requireStore()
        let key = try await store.currentKey()
        XCTAssertNil(key)
    }

    func test_roundTrip() async throws {
        let store = try requireStore()
        try await store.save("test-api-key-12345")
        let key = try await store.currentKey()
        XCTAssertEqual(key, "test-api-key-12345")
    }

    func test_clear_removesKey() async throws {
        let store = try requireStore()
        try await store.save("test-api-key-12345")
        try await store.clear()
        let key = try await store.currentKey()
        XCTAssertNil(key)
    }

    func test_emptyString_rejected() async throws {
        let store = try requireStore()
        do {
            try await store.save("")
            XCTFail("Should have thrown")
        } catch let error as HeliusError {
            XCTAssertEqual(error, .missingAPIKey)
        }
    }

    func test_whitespaceOnly_rejected() async throws {
        let store = try requireStore()
        do {
            try await store.save("   \n  ")
            XCTFail("Should have thrown")
        } catch let error as HeliusError {
            XCTAssertEqual(error, .missingAPIKey)
        }
    }

    func test_save_trimsWhitespace() async throws {
        let store = try requireStore()
        try await store.save("  trimmed-key  ")
        let key = try await store.currentKey()
        XCTAssertEqual(key, "trimmed-key")
    }

    // MARK: - Environment override (no Keychain dependency)

    func test_environmentOverride_returnsValue_withoutTouchingKeychain() async throws {
        let store = self.makeEnvOnlyStore(value: "env-key")
        let key = try await store.currentKey()
        XCTAssertEqual(key, "env-key")
    }

    func test_environmentOverride_trimsWhitespace() async throws {
        let store = self.makeEnvOnlyStore(value: "  spaced-key  \n")
        let key = try await store.currentKey()
        XCTAssertEqual(key, "spaced-key")
    }

    func test_environmentOverride_emptyValue_fallsThrough_andReturnsNil() async throws {
        // No keychain item exists for the test SecureItem and env is empty,
        // so the store should fall through to the Keychain path and return nil
        // (errSecItemNotFound is mapped to .loaded(nil) by the store).
        try XCTSkipUnless(
            ProcessInfo.processInfo.environment["ZODSOL_KEYCHAIN_TEST"] != nil,
            "Fall-through verification touches the real Keychain")
        let store = HeliusAPIKeyStore(
            secureStore: SecureItemStore(service: "dev.zods.zodsol.test"),
            item: testItem,
            environment: EnvironmentKeySource(
                variableName: "ZODSOL_HELIUS_API_KEY",
                environment: { ["ZODSOL_HELIUS_API_KEY": ""] }))
        try? await store.clear()
        let key = try await store.currentKey()
        XCTAssertNil(key)
    }

    private func makeEnvOnlyStore(value: String) -> HeliusAPIKeyStore {
        HeliusAPIKeyStore(
            secureStore: SecureItemStore(service: "dev.zods.zodsol.test.env"),
            item: SecureItem(
                service: "dev.zods.zodsol.test.env",
                account: "unreachable.\(UUID().uuidString)"),
            environment: EnvironmentKeySource(
                variableName: "ZODSOL_HELIUS_API_KEY",
                environment: { ["ZODSOL_HELIUS_API_KEY": value] }))
    }

    private func requireStore() throws -> HeliusAPIKeyStore {
        try XCTSkipUnless(
            ProcessInfo.processInfo.environment["ZODSOL_KEYCHAIN_TEST"] != nil,
            "Keychain-backed API key tests require ZODSOL_KEYCHAIN_TEST=1")
        return try XCTUnwrap(self.store)
    }
}
