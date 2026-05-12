import CryptoKit
import Foundation
import SolanaKit
import XCTest
@testable import WalletOverviewDomain

/// `UserDefaults` is documented as thread-safe but the Swift compiler does
/// not infer `Sendable` for it under strict concurrency. We wrap each test
/// in a local fixture so the reference never escapes a task boundary the
/// compiler can't reason about.
private struct DefaultsFixture: @unchecked Sendable {
    let defaults: UserDefaults
    let suiteName: String
    let key: String
}

private func makeFixture() -> DefaultsFixture {
    let suiteName = "RecentRecipientsStoreTests-\(UUID().uuidString)"
    let defaults = UserDefaults(suiteName: suiteName)!
    defaults.removePersistentDomain(forName: suiteName)
    return DefaultsFixture(defaults: defaults, suiteName: suiteName, key: "test.recentRecipients")
}

private func cleanup(_ fixture: DefaultsFixture) {
    fixture.defaults.removePersistentDomain(forName: fixture.suiteName)
}

private func makeStore(_ fixture: DefaultsFixture) -> RecentRecipientsStore {
    RecentRecipientsStore(defaults: fixture.defaults, key: fixture.key)
}

private func makeAddress() -> WalletAddress {
    let pk = Curve25519.Signing.PrivateKey()
    return try! WalletAddress(base58: Base58.encode(pk.publicKey.rawRepresentation))
}

final class RecentRecipientsStoreTests: XCTestCase {
    func testRecordThenListReturnsRecipient() async {
        let fixture = makeFixture()
        defer { cleanup(fixture) }
        let store = makeStore(fixture)
        let walletId = UUID()
        let address = makeAddress()
        let when = Date(timeIntervalSince1970: 1_000_000)
        await store.record(address, walletId: walletId, at: when)
        let list = await store.list(walletId: walletId)
        XCTAssertEqual(list.count, 1)
        XCTAssertEqual(list.first?.address.base58, address.base58)
        XCTAssertEqual(list.first?.walletId, walletId)
        XCTAssertEqual(list.first?.lastSentAt, when)
    }

    func testRecordSameAddressTwiceBumpsTimestamp() async {
        let fixture = makeFixture()
        defer { cleanup(fixture) }
        let store = makeStore(fixture)
        let walletId = UUID()
        let address = makeAddress()
        let t1 = Date(timeIntervalSince1970: 1_000_000)
        let t2 = t1.addingTimeInterval(120)
        await store.record(address, walletId: walletId, at: t1)
        await store.record(address, walletId: walletId, at: t2)
        let list = await store.list(walletId: walletId)
        XCTAssertEqual(list.count, 1)
        XCTAssertEqual(list.first?.lastSentAt, t2)
    }

    func testCapPerWallet10() async {
        let fixture = makeFixture()
        defer { cleanup(fixture) }
        let store = makeStore(fixture)
        let walletId = UUID()
        let base = Date(timeIntervalSince1970: 1_000_000)
        var addresses: [WalletAddress] = []
        for index in 0..<12 {
            let addr = makeAddress()
            addresses.append(addr)
            await store.record(addr, walletId: walletId, at: base.addingTimeInterval(Double(index)))
        }
        let list = await store.list(walletId: walletId)
        XCTAssertEqual(list.count, RecentRecipientsStore.maxEntriesPerWallet)
        let kept = Set(list.map(\.address.base58))
        // The newest 10 are indices 2..11 - oldest (0, 1) must have been evicted.
        XCTAssertFalse(kept.contains(addresses[0].base58))
        XCTAssertFalse(kept.contains(addresses[1].base58))
        XCTAssertTrue(kept.contains(addresses[11].base58))
        XCTAssertTrue(kept.contains(addresses[2].base58))
    }

    func testPerWalletIsolation() async {
        let fixture = makeFixture()
        defer { cleanup(fixture) }
        let store = makeStore(fixture)
        let walletA = UUID()
        let walletB = UUID()
        let addrA = makeAddress()
        let addrB = makeAddress()
        let now = Date(timeIntervalSince1970: 1_000_000)
        await store.record(addrA, walletId: walletA, at: now)
        await store.record(addrB, walletId: walletB, at: now)
        let listA = await store.list(walletId: walletA)
        let listB = await store.list(walletId: walletB)
        XCTAssertEqual(listA.map(\.address.base58), [addrA.base58])
        XCTAssertEqual(listB.map(\.address.base58), [addrB.base58])
        XCTAssertFalse(listA.contains { $0.walletId == walletB })
    }

    func testPersistenceRoundTrip() async {
        let fixture = makeFixture()
        defer { cleanup(fixture) }
        let storeA = makeStore(fixture)
        let walletId = UUID()
        let address = makeAddress()
        let when = Date(timeIntervalSince1970: 1_000_000)
        await storeA.record(address, walletId: walletId, at: when)
        let storeB = makeStore(fixture)
        let listed = await storeB.list(walletId: walletId)
        XCTAssertEqual(listed.count, 1)
        XCTAssertEqual(listed.first?.address.base58, address.base58)
        XCTAssertEqual(listed.first?.lastSentAt, when)
    }

    func testClearWalletId() async {
        let fixture = makeFixture()
        defer { cleanup(fixture) }
        let store = makeStore(fixture)
        let walletA = UUID()
        let walletB = UUID()
        let addrA = makeAddress()
        let addrB = makeAddress()
        let now = Date()
        await store.record(addrA, walletId: walletA, at: now)
        await store.record(addrB, walletId: walletB, at: now)
        await store.clear(walletId: walletA)
        let listA = await store.list(walletId: walletA)
        let listB = await store.list(walletId: walletB)
        XCTAssertTrue(listA.isEmpty)
        XCTAssertEqual(listB.map(\.address.base58), [addrB.base58])
    }

    func testClearAll() async {
        let fixture = makeFixture()
        defer { cleanup(fixture) }
        let store = makeStore(fixture)
        let walletA = UUID()
        let walletB = UUID()
        await store.record(makeAddress(), walletId: walletA)
        await store.record(makeAddress(), walletId: walletB)
        await store.clearAll()
        let listA = await store.list(walletId: walletA)
        let listB = await store.list(walletId: walletB)
        XCTAssertTrue(listA.isEmpty)
        XCTAssertTrue(listB.isEmpty)
    }

    func testOrderingByLastSentAtDesc() async {
        let fixture = makeFixture()
        defer { cleanup(fixture) }
        let store = makeStore(fixture)
        let walletId = UUID()
        let addrA = makeAddress()
        let addrB = makeAddress()
        let addrC = makeAddress()
        let base = Date(timeIntervalSince1970: 1_000_000)
        let t1 = base
        let t2 = base.addingTimeInterval(10)
        let t3 = base.addingTimeInterval(20)
        await store.record(addrA, walletId: walletId, at: t1)
        await store.record(addrB, walletId: walletId, at: t3)
        await store.record(addrC, walletId: walletId, at: t2)
        let list = await store.list(walletId: walletId)
        XCTAssertEqual(
            list.map(\.address.base58),
            [addrB.base58, addrC.base58, addrA.base58])
    }

    func testGlobalCap50() async {
        let fixture = makeFixture()
        defer { cleanup(fixture) }
        let store = makeStore(fixture)
        let base = Date(timeIntervalSince1970: 1_000_000)
        // Spread 60 records across 10 wallets, 6 each - per-wallet cap (10)
        // does not bite, so the global cap (50) is the only thing trimming.
        let walletIds = (0..<10).map { _ in UUID() }
        var counter = 0
        for walletId in walletIds {
            for _ in 0..<6 {
                let when = base.addingTimeInterval(Double(counter))
                await store.record(makeAddress(), walletId: walletId, at: when)
                counter += 1
            }
        }
        var total = 0
        for walletId in walletIds {
            total += await store.list(walletId: walletId).count
        }
        XCTAssertLessThanOrEqual(total, RecentRecipientsStore.maxEntriesTotal)
    }
}
