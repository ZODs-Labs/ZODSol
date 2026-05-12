import Foundation
import KeychainKit
import SolanaKit
import XCTest
@testable import WalletOverviewDomain

private struct Fixture {
    let store: WalletStore
    let secureStore: SecureItemStore
    let service: String
    let defaultsSuiteName: String
}

private func makeFixture() throws -> Fixture {
    try XCTSkipUnless(
        ProcessInfo.processInfo.environment["ZODSOL_KEYCHAIN_TEST"] != nil,
        "Keychain tests require ZODSOL_KEYCHAIN_TEST=1")
    let uniqueSuffix = UUID().uuidString
    let service = "dev.zods.zodsol.test.\(uniqueSuffix)"
    let suite = "test.\(uniqueSuffix)"
    let secureStore = SecureItemStore(service: service)
    guard let defaults = UserDefaults(suiteName: suite) else {
        throw XCTSkip("Could not create test UserDefaults suite")
    }
    let store = WalletStore(
        secureStore: secureStore,
        defaults: defaults,
        service: service,
        selectedWalletKey: "test.selectedWalletId.\(uniqueSuffix)")
    return Fixture(
        store: store,
        secureStore: secureStore,
        service: service,
        defaultsSuiteName: suite)
}

private func cleanup(_ fixture: Fixture) async {
    for wallet in await fixture.store.wallets() {
        try? await fixture.store.remove(walletId: wallet.id)
    }
    try? await fixture.secureStore.delete(SecureItem(service: fixture.service, account: "wallets.index"))
    UserDefaults.standard.removePersistentDomain(forName: fixture.defaultsSuiteName)
}

final class WalletStoreTests: XCTestCase {
    func testAddAndList() async throws {
        let fixture = try makeFixture()
        let material = makeTestPrivateKey()
        let importedKey = try ImportedPrivateKey.parse(material.base58Key)
        let identity = try await fixture.store.add(privateKey: importedKey, label: "Main")

        let wallets = await fixture.store.wallets()
        XCTAssertEqual(wallets.count, 1)
        XCTAssertEqual(wallets.first?.id, identity.id)
        XCTAssertEqual(wallets.first?.label, "Main")
        XCTAssertEqual(wallets.first?.address.base58, material.base58Address)

        await cleanup(fixture)
    }

    func testAddPersistsAddressLookup() async throws {
        let fixture = try makeFixture()
        let material = makeTestPrivateKey()
        let importedKey = try ImportedPrivateKey.parse(material.base58Key)
        let identity = try await fixture.store.add(privateKey: importedKey, label: "X")

        let resolved = try await fixture.store.address(for: identity.id)
        XCTAssertEqual(resolved.base58, material.base58Address)

        await cleanup(fixture)
    }

    func testRemoveDropsFromList() async throws {
        let fixture = try makeFixture()
        let material = makeTestPrivateKey()
        let importedKey = try ImportedPrivateKey.parse(material.base58Key)
        let identity = try await fixture.store.add(privateKey: importedKey, label: "ToRemove")

        try await fixture.store.remove(walletId: identity.id)
        let wallets = await fixture.store.wallets()
        XCTAssertTrue(wallets.isEmpty)

        do {
            _ = try await fixture.store.address(for: identity.id)
            XCTFail("expected error fetching removed wallet")
        } catch let error as WalletOverviewError {
            XCTAssertEqual(error, .needsSetup)
        }

        await cleanup(fixture)
    }

    func testRenameUpdatesLabel() async throws {
        let fixture = try makeFixture()
        let material = makeTestPrivateKey()
        let importedKey = try ImportedPrivateKey.parse(material.base58Key)
        let identity = try await fixture.store.add(privateKey: importedKey, label: "Initial")

        try await fixture.store.rename(walletId: identity.id, to: "Renamed")
        let wallets = await fixture.store.wallets()
        XCTAssertEqual(wallets.first(where: { $0.id == identity.id })?.label, "Renamed")

        await cleanup(fixture)
    }

    func testRenameMissingWalletThrows() async throws {
        let fixture = try makeFixture()
        do {
            try await fixture.store.rename(walletId: UUID(), to: "Ghost")
            XCTFail("expected needsSetup")
        } catch let error as WalletOverviewError {
            XCTAssertEqual(error, .needsSetup)
        }

        await cleanup(fixture)
    }

    func testSelectedWalletRoundTrip() async throws {
        let fixture = try makeFixture()
        let id = UUID()
        await fixture.store.setSelectedWallet(id)
        let read = await fixture.store.selectedWalletId()
        XCTAssertEqual(read, id)

        await fixture.store.setSelectedWallet(nil)
        let cleared = await fixture.store.selectedWalletId()
        XCTAssertNil(cleared)

        await cleanup(fixture)
    }

    func testRemovingSelectedWalletClearsSelection() async throws {
        let fixture = try makeFixture()
        let material = makeTestPrivateKey()
        let importedKey = try ImportedPrivateKey.parse(material.base58Key)
        let identity = try await fixture.store.add(privateKey: importedKey, label: "Pick")

        await fixture.store.setSelectedWallet(identity.id)
        let beforeRemoval = await fixture.store.selectedWalletId()
        XCTAssertEqual(beforeRemoval, identity.id)

        try await fixture.store.remove(walletId: identity.id)
        let afterRemoval = await fixture.store.selectedWalletId()
        XCTAssertNil(afterRemoval)

        await cleanup(fixture)
    }

    func testConcurrentAddsAllAppearInIndex() async throws {
        let fixture = try makeFixture()
        let materials = (0..<5).map { _ in makeTestPrivateKey() }
        let importedKeys = try materials.map { try ImportedPrivateKey.parse($0.base58Key) }

        try await withThrowingTaskGroup(of: WalletIdentity.self) { group in
            let store = fixture.store
            for (i, key) in importedKeys.enumerated() {
                group.addTask {
                    try await store.add(privateKey: key, label: "Wallet \(i)")
                }
            }
            var count = 0
            for try await _ in group {
                count += 1
            }
            XCTAssertEqual(count, 5)
        }

        let wallets = await fixture.store.wallets()
        XCTAssertEqual(wallets.count, 5, "expected all 5 concurrently-added wallets in index")
        let labels = Set(wallets.map(\.label))
        XCTAssertEqual(labels.count, 5, "labels should be unique")
        let addressBase58 = Set(wallets.map(\.address.base58))
        XCTAssertEqual(addressBase58, Set(materials.map(\.base58Address)))

        await cleanup(fixture)
    }

    func testWithPrivateKeyExposesBuffer() async throws {
        let fixture = try makeFixture()
        let material = makeTestPrivateKey()
        let importedKey = try ImportedPrivateKey.parse(material.base58Key)
        let identity = try await fixture.store.add(privateKey: importedKey, label: "Read")

        let snapshot: Data = try await fixture.store
            .withPrivateKey(walletId: identity.id, prompt: "Authorize") { buffer in
                buffer
            }
        XCTAssertEqual(snapshot, material.secretKey64)

        await cleanup(fixture)
    }

    func testWithPrivateKeyMissingThrowsBiometricInvalidated() async throws {
        let fixture = try makeFixture()
        do {
            _ = try await fixture.store.withPrivateKey(walletId: UUID(), prompt: "x") { _ in
                Data()
            }
            XCTFail("expected biometricInvalidated")
        } catch let error as WalletOverviewError {
            XCTAssertEqual(error, .biometricInvalidated)
        }

        await cleanup(fixture)
    }
}
