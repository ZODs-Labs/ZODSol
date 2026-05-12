// # Manual Smoke Check
// To run Keychain-backed tests locally:
//   ZODSOL_KEYCHAIN_TEST=1 swift test --filter SecureItemStoreTests
//
// To run the user-presence round-trip locally:
//   ZODSOL_KEYCHAIN_USER_PRESENCE_SMOKE=1 swift test --filter SecureItemStoreTests/testUserPresenceRoundTrip
// This requires a Mac with local authentication available.
// Unsigned SwiftPM XCTest processes can return errSecMissingEntitlement, so
// default test runs skip all real Keychain operations.
import XCTest
@testable import KeychainKit

final class SecureItemStoreTests: XCTestCase {
    func testPlainRoundTrip() async throws {
        try self.requireKeychainTestsEnabled()
        let service = "dev.zods.zodsol.test.\(UUID().uuidString)"
        let store = SecureItemStore(service: service)
        let item = SecureItem(service: service, account: "roundtrip")
        let payload = Data("hello".utf8)

        try await store.write(payload, to: item, accessibility: .whenUnlockedThisDeviceOnly, gate: .none)
        let read = try await store.read(item)
        XCTAssertEqual(read, payload)

        try await store.delete(item)
        let gone = await store.contains(item)
        XCTAssertFalse(gone)
    }

    func testUpdateOnDoubleWrite() async throws {
        try self.requireKeychainTestsEnabled()
        let service = "dev.zods.zodsol.test.\(UUID().uuidString)"
        let store = SecureItemStore(service: service)
        let item = SecureItem(service: service, account: "update")

        let first = Data("first".utf8)
        let second = Data("second".utf8)

        try await store.write(first, to: item, accessibility: .whenUnlockedThisDeviceOnly, gate: .none)
        try await store.write(second, to: item, accessibility: .whenUnlockedThisDeviceOnly, gate: .none)
        let result = try await store.read(item)
        XCTAssertEqual(result, second)
        try await store.delete(item)
    }

    func testDeleteNonExistentIsIdempotent() async throws {
        try self.requireKeychainTestsEnabled()
        let service = "dev.zods.zodsol.test.\(UUID().uuidString)"
        let store = SecureItemStore(service: service)
        let item = SecureItem(service: service, account: "ghost")
        try await store.delete(item)
    }

    func testContainsReturnsFalseForMissing() async throws {
        try self.requireKeychainTestsEnabled()
        let service = "dev.zods.zodsol.test.\(UUID().uuidString)"
        let store = SecureItemStore(service: service)
        let item = SecureItem(service: service, account: "missing")
        let found = await store.contains(item)
        XCTAssertFalse(found)
    }

    func testUserPresenceRoundTrip() async throws {
        try self.requireKeychainTestsEnabled()
        try XCTSkipUnless(
            ProcessInfo.processInfo.environment["ZODSOL_KEYCHAIN_USER_PRESENCE_SMOKE"] != nil,
            "Set ZODSOL_KEYCHAIN_USER_PRESENCE_SMOKE=1 to run user-presence round-trip locally")
        let service = "dev.zods.zodsol.test.\(UUID().uuidString)"
        let store = SecureItemStore(service: service)
        let item = SecureItem(service: service, account: "userPresenceSmoke")
        let payload = Data("user-presence-test".utf8)

        try await store.write(
            payload,
            to: item,
            accessibility: .whenUnlockedThisDeviceOnly,
            gate: .userPresence(prompt: "Authorize to continue"))
        let read = try await store.read(item, prompt: "Authorize to read")
        XCTAssertEqual(read, payload)
        try await store.delete(item)
    }

    private func requireKeychainTestsEnabled() throws {
        try XCTSkipUnless(
            ProcessInfo.processInfo.environment["ZODSOL_KEYCHAIN_TEST"] != nil,
            "Keychain tests require ZODSOL_KEYCHAIN_TEST=1")
    }
}
